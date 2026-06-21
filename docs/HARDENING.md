# Perch — Abuse / DoS / Cost Hardening (live backend)

*The RLS/data-access model is solid (see [BACKEND.md](BACKEND.md) §10), but RLS protects **data correctness**, not **availability or cost**. Because [`config.js`](../config.js) ships the project URL + public anon key, the Supabase project is internet-reachable, so the auth + RPC endpoints can be spammed today. This is the runbook to close that. Maps to the "LIVE-BACKEND HARDENING" review items (#5–#10).*

> Split by who can do it: **[CODE]** is in the repo (done / a migration you run); **[CONSOLE]** is a Supabase dashboard task; **[EDGE]** needs a Cloudflare account + a DNS change. The CODE layer is defence-in-depth; the EDGE layer is the real per-IP/DoS protection.

---

## What's already done — [CODE] migration `0003_rate_limits.sql`

A per-**account** fixed-window throttle at the database layer. Apply it like 0002: Supabase **SQL Editor → New query →** paste [`supabase/migrations/0003_rate_limits.sql`](../supabase/migrations/0003_rate_limits.sql) **→ Run** (idempotent, safe to re-run).

It adds:
- a `rate_limits` table + `rl_check(action, max, window)` helper (no client access),
- a **chat-spam trigger**: user messages throttled to **20/min/account**,
- guards on **`join_group`** (8/min), **`check_in`** (12/min), and **`username_available`** (20/min for authenticated callers).

**Its one real limit:** it keys on `account_id`, so it does **not** stop an *anonymous* attacker (e.g. hammering `username_available` or `signInWithOtp` with just the anon key and no session). Postgres RPCs can't see the caller IP — **per-IP throttling is the edge layer's job (Cloudflare, below).** Treat `0003` as defence-in-depth, not the whole answer.

---

## #6 Email-OTP abuse / "email bombing" — [CONSOLE]

Email OTP is the only real sign-in, and anyone with the anon key can drive it to blast emails at arbitrary addresses. Two console fixes:

1. **Enable a CAPTCHA on Auth** (the highest-value single toggle). Supabase Dashboard → **Authentication → Attack Protection → Enable CAPTCHA**. You'll need a provider first:
   - Create a free **Cloudflare Turnstile** site (or **hCaptcha**) → copy the **site key** + **secret key**.
   - Paste the secret into Supabase; add the site key to the sign-in widget. *(The single-file frontend currently has no CAPTCHA widget — wiring one in is a small follow-up; until then, the toggle still protects the hosted Supabase auth UI / direct API calls.)*
2. **Custom SMTP** so legit OTP isn't throttled to ~2/hr (Supabase free default) and you control limits. Dashboard → **Authentication → Emails / SMTP Settings** → plug in **Resend** (free tier) or similar. (Noted already in [DEPLOY.md](DEPLOY.md).)
3. **Tighten built-in auth rate limits.** Dashboard → **Authentication → Rate Limits** → lower the per-hour email/OTP send ceilings to sane values.

---

## #7 / #8 WAF + IP-ban — [EDGE] (Cloudflare)

GitHub Pages → direct-to-Supabase means **no WAF and no IP throttling you control**, and no way to block an abusive client. Fix by putting Cloudflare in front:

1. Add your domain to **Cloudflare** (free plan), point DNS at the Pages site (CNAME), enable the **orange-cloud proxy**.
2. **WAF / Rate Limiting Rules** → add a rule throttling requests to the Supabase REST/Auth hostnames (or your API path) per-IP (e.g. 60 req/min).
3. **Security → block/challenge** rules give you the **IP-ban** ability (#8) — block or CAPTCHA-challenge an abusive IP/ASN.
4. Optionally restrict the Supabase project to Cloudflare via **Supabase → Settings → Network Restrictions** (allow-list) so attackers can't bypass the proxy by hitting Supabase directly.

This is the layer that actually absorbs API-spam and denial-of-service; the DB throttle (`0003`) only complements it.

---

## #9 Monitoring / alerting — [CONSOLE]

You currently have no visibility — an attack or runaway would be silent.

- Supabase Dashboard → **Reports / Logs** → set up **usage + log alerts**: spikes in auth volume, RPC error rates, DB egress, and approaching free-tier quotas.
- Add **Cloudflare** analytics/alerts once it's in front (#7).
- Lightweight app signal: the live bridge already `console.warn`s on backend failures — pipe those to a free error tracker (e.g. Sentry free tier) if/when you want client-side visibility.

---

## #10 Denial-of-wallet / quota exhaustion — [CONSOLE] + the above

Free-tier Supabase has DB/email/egress/realtime quotas; spamming the public endpoints could exhaust them and take the demo down (or, on a paid plan, run up cost).

- Mitigated by rate limits (#5 `0003` + Cloudflare #7) and alerts (#9).
- While it's just a demo, keep the project on the **free tier** (hard quota = a cap, not a bill) and/or set a **spend cap** if you upgrade. Dashboard → **Organization → Billing**.

---

## Suggested order (fastest risk reduction first)

1. **[CODE]** Run `0003_rate_limits.sql` — 1 min, done.
2. **[CONSOLE]** Enable CAPTCHA + tighten auth rate limits — biggest win vs email bombing.
3. **[CONSOLE]** Usage/error alerts — so you'd actually know.
4. **[EDGE]** Cloudflare in front + per-IP WAF rule — the real DoS/IP-ban layer.
5. **[CONSOLE]** Custom SMTP — removes the OTP throttle bottleneck for real users.

*If you'd rather not run a live backend at all while these are open, the alternative is to ship the public demo in pure-sim mode (remove/rename `config.js`) — the app falls back to the simulation automatically.*
