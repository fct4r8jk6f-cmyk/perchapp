// ============================================================================
// Perch — live data layer (perch-api.js)
// ============================================================================
//
// The real backend client for the thin slice: auth + profile + this Thursday's
// group + chat (realtime) + join + check-in, talking to the Supabase schema in
// supabase/migrations/0001_init.sql.
//
// NO BUILD STEP: this is a browser ES module that imports supabase-js straight
// from a CDN. Use it from a `<script type="module">` (see backend/test.html).
// Later it bridges into index.html via a small module shim that assigns the
// returned object to window.Perch — the single-file demo stays single-file.
//
//   import { createPerch } from "./perch-api.js";
//   const perch = createPerch(window.PERCH_CONFIG);   // {url, anonKey}
//
// Every method returns a Promise. Mutating, invariant-bearing operations
// (join, check-in) call SECURITY DEFINER RPCs — the cap/capacity/reservation
// are enforced in Postgres, not here.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const THURSDAY_GROUP_ID = "11111111-1111-1111-1111-111111111111"; // seeded in 0001_init.sql

export function createPerch(config) {
  if (!config || !config.url || !config.anonKey) {
    throw new Error(
      "Perch backend not configured. Copy config.example.js to config.js and fill in your Supabase url + anon key."
    );
  }

  const sb = createClient(config.url, config.anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });

  // ---- helpers -------------------------------------------------------------
  const unwrap = ({ data, error }) => {
    if (error) throw error;
    return data;
  };

  // ---- auth ----------------------------------------------------------------
  const auth = {
    // Magic-link / OTP sign-in. The email contains a link back to redirectTo
    // (defaults to wherever the app is open); supabase-js auto-detects the
    // session on return. shouldCreateUser lets new emails register.
    async signInWithEmail(email, captchaToken, redirectTo) {
      return unwrap(
        await sb.auth.signInWithOtp({
          email,
          options: {
            shouldCreateUser: true,
            emailRedirectTo: redirectTo || (typeof window !== "undefined" ? window.location.href : undefined),
            // Only sent when the Turnstile widget produced a token. Required once
            // CAPTCHA is enabled in Supabase Auth; harmless (ignored) when it isn't.
            ...(captchaToken ? { captchaToken } : {}),
          },
        })
      );
    },
    // Alternative to clicking the link: enter the 6-digit code from the email.
    // (Requires the email template to expose {{ .Token }} — see docs/DEPLOY.md.)
    async verifyEmailCode(email, token) {
      return unwrap(await sb.auth.verifyOtp({ email, token, type: "email" }));
    },
    async getSession() {
      return unwrap(await sb.auth.getSession()).session;
    },
    async getUser() {
      const { data } = await sb.auth.getUser();
      return data ? data.user : null;
    },
    onChange(cb) {
      const { data } = sb.auth.onAuthStateChange((_event, session) => cb(session));
      return () => data.subscription.unsubscribe();
    },
    async signOut() {
      return unwrap(await sb.auth.signOut());
    },
  };

  // ---- profile -------------------------------------------------------------
  const profile = {
    // The signed-in user's profile row, or null if they haven't set one up yet.
    async mine() {
      const user = await auth.getUser();
      if (!user) return null;
      const { data, error } = await sb.from("profiles").select("*").eq("id", user.id).maybeSingle();
      if (error) throw error;
      return data;
    },
    // usernameStatus() — server-checked (taken + reserved + format).
    async usernameAvailable(username) {
      return unwrap(await sb.rpc("username_available", { uname: username }));
    },
    // Create/update the on-demand profile and mark it complete (the join gate).
    // (bio/photo are friends-only and not in this slice — see 0001_init.sql.)
    async save({ name, username, emoji, profileKey }) {
      const user = await auth.getUser();
      if (!user) throw new Error("Not signed in.");
      const row = {
        id: user.id,
        name,
        username,
        emoji: emoji || "🙂",
        profile_key: profileKey || null,
        profile_complete: true,
      };
      return unwrap(await sb.from("profiles").upsert(row).select().single());
    },
  };

  // ---- groups --------------------------------------------------------------
  const groups = {
    // This Thursday's seeded group (the guaranteed-cadence group).
    async thursday() {
      const { data, error } = await sb.from("groups").select("*").eq("id", THURSDAY_GROUP_ID).maybeSingle();
      if (error) throw error;
      return data;
    },
    async get(groupId) {
      const { data, error } = await sb.from("groups").select("*").eq("id", groupId).maybeSingle();
      if (error) throw error;
      return data;
    },
    // Groups the signed-in user has joined (with their reservation code).
    async mine() {
      return unwrap(
        await sb
          .from("group_memberships")
          .select("id,status,joined_at,group:groups(*),reservation:reservations(code,ticket,price)")
          .order("joined_at", { ascending: false })
      );
    },
    // Roster: who's in this group (first name + emoji + archetype only).
    async roster(groupId) {
      return unwrap(
        await sb
          .from("group_memberships")
          .select("status,role,attended,profile:profiles(name,emoji,profile_key)")
          .eq("group_id", groupId)
          .in("status", ["active", "attended"])
      );
    },
    async weeklyJoinCount() {
      return unwrap(await sb.rpc("weekly_join_count"));
    },
    // The join funnel (cap -> gate -> capacity -> reservation), server-side.
    // Returns { ok, error?, code?, ticket?, price?, cap? }.
    async join(groupId, activityId) {
      return unwrap(await sb.rpc("join_group", { p_group_id: groupId, p_activity_id: activityId || null }));
    },
  };

  // ---- chat ----------------------------------------------------------------
  const chat = {
    async messages(groupId) {
      return unwrap(
        await sb
          .from("group_messages")
          .select("id,kind,body,sent_at,sender:profiles(name,emoji)")
          .eq("group_id", groupId)
          .order("sent_at", { ascending: true })
      );
    },
    async send(groupId, body) {
      const user = await auth.getUser();
      if (!user) throw new Error("Not signed in.");
      const text = (body || "").trim();
      if (!text) return null;
      return unwrap(
        await sb
          .from("group_messages")
          .insert({ group_id: groupId, sender_id: user.id, kind: "user", body: text })
          .select()
          .single()
      );
    },
    // Live new-message stream for a group. Returns an unsubscribe fn.
    subscribe(groupId, onMessage) {
      const channel = sb
        .channel(`group:${groupId}`)
        .on(
          "postgres_changes",
          { event: "INSERT", schema: "public", table: "group_messages", filter: `group_id=eq.${groupId}` },
          (payload) => onMessage(payload.new)
        )
        .subscribe();
      return () => sb.removeChannel(channel);
    },
  };

  // ---- attendance ----------------------------------------------------------
  const attendance = {
    // checkIn(): idempotent. Returns { ok, attended, first_time }.
    async checkIn(groupId) {
      return unwrap(await sb.rpc("check_in", { p_group_id: groupId }));
    },
  };

  return {
    sb, // escape hatch for ad-hoc queries / debugging
    THURSDAY_GROUP_ID,
    auth,
    profile,
    groups,
    chat,
    attendance,
  };
}
