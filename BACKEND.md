# BACKEND.md — Perch Backend Architecture & Decisions

> This is a design document, **not a final infrastructure commitment**. It proposes a stack and the reasoning behind it so the founder and first engineer can argue with it before anything is built. Cross-references: [`schema.sql`](./schema.sql) (table DDL) and [`API.md`](./API.md) (endpoint contracts).

_Drafted 2026-06-13 — design, not yet built._

---

## 1. Overview

### What exists today

The entire Perch product is `index.html` — one ~3,900-line file with **no backend**. All application state lives in a single in-memory JavaScript `state` object (index.html ~L1699). The only thing that persists across reloads is the chosen language (`localStorage perch_lang`); theme is in-session by design, and everything else — your quiz answers, profile, joins, waitlist entries, chats, day-of statuses — evaporates on refresh. `resetDemo()` (~L1873) wipes it back to zero.

That is fine for a demo. The real product needs a server because every core promise is multi-user and stateful across time:

- **Group formation** mixes real strangers by archetype — it cannot be faked client-side.
- **The free-tier cap (2 hangs/week)** must be enforced where the client can't lie about it.
- **Waitlist backfill** fires a time-limited offer to *the next real person* when a spot opens — needs a durable queue and a scheduler, not a `setTimeout`.
- **Chat, day-of coordination, and notifications** are inherently realtime and cross-device.
- **Law 25 / PIPEDA** require server-side consent records, retention, audit, and a real deletion pipeline.

### What the backend must do

Concretely, the server owns everything the demo currently simulates with module-level timers and the `state` object:

| Demo behaviour (index.html) | Backend responsibility |
|---|---|
| `state` object, reset on reload | Durable per-account state in Postgres (`accounts`, `profiles`, `group_memberships`, …) |
| `requestJoin` cap check `state.plus?5:2` (~L3508) | Server-authoritative weekly cap, counted per ISO week from `check_ins`/`group_memberships` |
| `finishJoin` → `reservation:{code,ticket,price}` (~L3491) | `reservations` rows; `resvCode()` → server-generated `PCH-XXXX` |
| `makeGroups()` static templates (~L1226) | Real group-formation job writing `groups` + `group_memberships` |
| `scheduleBackfillOffer`/`fireBackfillOffer`/`expireBackfillOffer` (~L3631) | `backfill_offers` rows + scheduled jobs (offer + 90s-equivalent expiry) |
| `chatTimers` simulated chat (~L1801) | Real `group_messages`/`direct_messages` over a realtime channel |
| `checkIn` bumping `state.attended` (~L3614) | `check_ins` rows; reliability derived, never stored as a public score |
| `state.verified` via `openVerify` (~L3532) | `phone_verifications` (OTP), `accounts.verified_at` |
| Quiz in `state.answers` before sign-in (~L1702) | Anonymous `quiz_responses`, attached to an account on sign-in |

The mapping principle: **every field on `state` that isn't pure UI ephemera (theme, `activeCat`, `fbStep`, scroll position) gets a home in a table.** The client keeps a local cache for offline/optimistic UI, but the server is the source of truth for anything another user can see or that gates an action.

---

## 2. Recommended stack

**Recommendation: managed Postgres + a thin Node/TypeScript API, hosted in a Canadian region.** Specifically:

- **Database:** Managed Postgres (Supabase or Neon, Canadian region — see §8).
- **API:** Node 20 + TypeScript, Fastify (or NestJS if the team prefers structure), deployed as containers.
- **Realtime:** Postgres-backed pub/sub (Supabase Realtime) or a managed WebSocket layer (see §5).
- **Jobs:** A durable queue + scheduler (pg-boss on the same Postgres, or a managed cron) — see §6.
- **Push:** APNs + FCM directly, or via a thin abstraction.

### Rationale

The project's defining constraint is its **lightweight, no-build ethos** (CLAUDE.md: "single-file, no-build is a deliberate constraint"). The backend should honour the same spirit: **one primary datastore, minimal moving parts, boring technology.** Postgres alone covers relational data, JSON columns (for `user_settings.notif`, `quiz_responses`), full-text search (replacing the client-side `PEOPLE` directory filter), row-level security, *and* — via pg-boss — the job queue. That collapses what would otherwise be four vendors into one.

TypeScript is the obvious API language because the entire existing codebase is JavaScript; the team already reasons in this paradigm, and the `esc()` escaping discipline (index.html L1751) and validation logic (`usernameStatus` L1779) port directly. A schema-first API (zod or TypeBox) lets `usernameStatus`'s rules (`3–20 chars, /^[a-z0-9._]+$/`, checked against `reserved_usernames`) live as one shared validator on both client and server.

### Strong alternative: Supabase as a BaaS

**Supabase deserves first consideration** because it bundles exactly what Perch needs: managed Postgres, row-level security (maps perfectly to the ownership model in §10), Realtime (chat/day-of/backfill), Auth (though we override with phone OTP), Storage (profile photos — `state.photo`), Edge Functions (jobs), and **a Toronto/Montreal-eligible region for Canadian residency** (§8). It would let the first engineer ship the read/browse paths with almost no server code, writing custom functions only for the *invariant-critical* flows (`requestJoin` cap+gate, group formation, backfill).

- **Trade-off:** RLS-heavy logic can get hard to test and reason about as invariants grow (the join funnel is genuinely intricate). The mitigation is to keep the *complex, multi-step* flows (`requestJoin → beginJoin → openReservation → finishJoin`) in explicit Edge Functions / RPCs rather than expressing them purely as RLS + client writes. Vendor lock-in is real but Postgres-portable.

### Second alternative: self-managed Node + Postgres on a Canadian VPS/PaaS

Full control, no per-seat platform fees, trivially Canada-resident (pick a Montreal/Toronto region). **Trade-off:** you now own realtime infrastructure, connection pooling, backups, and the scheduler yourself — directly against the lightweight ethos and a poor use of a two-person team's time pre-product-market-fit. **Recommended only if** Supabase's residency or pricing becomes a blocker.

### What we explicitly avoid

Microservices, Kafka, a separate search cluster, a separate cache tier (Postgres + a small in-process cache is plenty at launch), and any payment processor for activity tickets (§7 — there are none to process).

---

## 3. Client & packaging

### Recommendation: Capacitor-wrap the existing PWA first; keep native rebuild as a later option.

The demo is already a single-file, mobile-first, iPhone-proportioned PWA. The fastest credible path to the App Store and Play Store is to **wrap the existing HTML/CSS/JS in [Capacitor](https://capacitorjs.com/)** rather than rebuild natively:

- Capacitor produces real iOS/Android app shells around the web UI, satisfying store requirements while preserving the no-build, single-codebase spirit.
- It provides the **native plugins Perch specifically needs**: push notifications (APNs/FCM, §5), **Apple/Google In-App Purchase for Perch+** (§7), camera/photo picker (for `state.photo`), and secure token storage (refresh tokens, §4).
- One web codebase ships to web + iOS + Android, which keeps the team small and the i18n surface (en / fr-CA, including legal docs) single-sourced.

**Trade-off vs native rebuild:** a wrapped webview is slightly less fluid than fully native for animation-heavy screens; the demo already respects `reduceMotion` so this is manageable. Revisit a native rebuild only if store performance review or a richer realtime UI demands it.

### How the client talks to the backend

- **REST + JSON over HTTPS** for request/response (browse, join, profile) — see API.md. The client keeps thin local caches mirroring today's `state` for optimistic UI.
- **One realtime channel** (WebSocket/SSE, §5) for chat, day-of statuses, and backfill offers.
- **Push** for out-of-app notifications.

### Offline / caching

A service worker caches the app shell and last-seen browse data so the **quiz and browsing work offline** (consistent with "browsing is free" — CLAUDE.md). Action endpoints that touch invariants (join, claim, check-in) **require connectivity and are confirmed server-side** — the client must never finalize a join offline, because the cap, profile gate, and reservation all live on the server. Offline writes queue and replay; conflicting ones (e.g. spot filled) surface the same "group full → waitlist" path.

---

## 4. Auth & sessions

### Phone OTP as the primary credential

The demo's `openVerify` (~L3532) already models phone-number + 4-digit code. In production this becomes the **sign-in** mechanism (not just an optional badge):

1. `POST /auth/otp/start { phone }` → server creates a `phone_verifications` row (hashed code, short TTL, attempt counter), sends SMS via the chosen vendor (§8).
2. `POST /auth/otp/verify { phone, code }` → on match, finds-or-creates an `accounts` row and issues tokens.

> **Note the distinction the demo is careful about:** *signing in* with a phone number is not the same as the **optional "✓ Verified" badge** (`vbadge`, `state.verified`). Both can use OTP, but verification must **never block joining or hosting** (CLAUDE.md invariant). Model them as two flags — `accounts.phone` (auth identity) and a separate `accounts.verified_at` (the trust badge) — so we can later allow, e.g., social sign-in without conflating it with the badge.

### Tokens / refresh

- Short-lived **access JWT** (~15 min) carrying `account_id` and a coarse scope; long-lived **refresh token** stored in the device secure store (Capacitor Secure Storage / Keychain / Keystore).
- `POST /auth/refresh` rotates refresh tokens (one-time-use, reuse-detection revokes the family).
- Logout, "take a break", and account deletion all revoke token families server-side.

### The anonymous-quiz-then-attach flow (important)

The quiz is deliberately the **shareable acquisition artifact** and runs **before sign-in/consent** (CLAUDE.md, PLAN.md). The demo holds this in `state.answers` / `state.profileKey` with no account. The backend mirrors that:

1. On first quiz start, issue an **anonymous session token** (no account, no PII).
2. Quiz answers persist to `quiz_responses` keyed by that anonymous session (so a half-finished quiz survives a refresh — better than today).
3. When the user later signs in (phone OTP), the anonymous `quiz_responses` (and resulting `profile_key`/archetype) are **attached** to the new `accounts` row, and the anonymous session is retired.

This preserves "quiz before consent" while still capturing the result — and it's the cleanest place to record the **consent event** at attach time (§9), since that's the first moment we hold an identity.

### 18+ age gate

Self-attested, floored at 18, **disclosed before the quiz** (CLAUDE.md: "18+ is disclosed before the quiz"; demo `state.age` stepper). The server records the attestation (a `consent_records` row of type `age_attestation` with the attested DOB/age and timestamp) at account attach. The gate is **not** a hard identity check (see Open Decisions, §12).

---

## 5. Realtime

Three demo behaviours are realtime; all three can ride **one channel abstraction**:

| Demo feature | Source in index.html | Realtime need |
|---|---|---|
| Group chat & DMs | `chatThreads`, `chatTimers` (~L1801), `pushMsg` | Bidirectional messages, read state |
| Day-of coordination | `coordPanelHTML`/`seedDaySim`/`checkIn` (~L3596) | Live status pills (omw/late/here), "X is here" system posts |
| Backfill offers | `fireBackfillOffer` (~L3635) | Push a time-limited offer + a tappable in-app toast/notification |

### Transport

**WebSocket as the in-app transport** (or **Supabase Realtime**, which is Postgres-change-feed over WebSocket — letting `group_messages` / `day_of_statuses` / `backfill_offers` inserts fan out to subscribers with no custom socket server). SSE is a fallback for restrictive networks. Each connection authenticates with the access JWT; the server scopes subscriptions to channels the account is authorized for (a group chat channel requires an active `group_memberships` row — §10).

- **Group chat** → channel per `groups.id`; messages → `group_messages`; per-user read cursor → `chat_read_state` (replaces `state.unreadChats`).
- **Day-of** → the same group channel; statuses → `day_of_statuses`; "here" writes a `check_ins` row via the shared check-in (don't duplicate — mirror the demo's single `checkIn` path).
- **Backfill** → user-scoped channel; an inserted `backfill_offers` row pushes the offer; expiry (below) flips its status and notifies.

### Push (out-of-app)

When the socket is disconnected, deliver via **APNs (iOS)** and **FCM (Android)**, gated by `user_settings.notif` (the demo's `notif:{reminders,messages,friendReq,matches,updates}`). Device tokens live in `notifications`-adjacent storage (or a `device_tokens` table — add if not present). Every realtime event that the user might miss has a push fallback: new messages (`messages` pref), event reminders (`reminders`), friend requests (`friendReq`), new group matches (`matches`), product updates (`updates`).

---

## 6. Background jobs & schedulers

Every time-based behaviour in the demo is a `setTimeout`; in production each becomes a **durable, idempotent job** (pg-boss queue on Postgres, or managed cron + worker). Enumerated:

| # | Behaviour | Demo source | Production job |
|---|---|---|---|
| 1 | **Backfill offer fires** when a spot opens | `scheduleBackfillOffer` → `fireBackfillOffer` (6s, ~L3631) | On a membership freeing a spot in a full group, enqueue an *offer* job for the next deterministic waitlist entry (`waitlist_entries`, ordered by `wlPosition` rule — never #1). Writes `backfill_offers`, pushes notification. |
| 2 | **Backfill offer expires** | `expireBackfillOffer` (90s, ~L3640) | Delayed job (real window, e.g. 30–60 min) flips the offer to `expired`, keeps the waitlist entry (demo copy: "still on the waitlist"), and cascades the offer to the next person. |
| 3 | **Weekly cap reset boundary** | implicit in `requestJoin` cap (~L3508) | The cap is **counted, not reset** — query joins/check-ins within the **current ISO week** (America/Toronto). No destructive reset job; a small materialized counter can be recomputed at the ISO-week boundary for performance. This makes "2 hangs/week (free) / 5 (Perch+)" robust to clock skew and time zones. |
| 4 | **Event reminders** | demo's `notif.reminders` pref | Scheduled per `activity_occurrences` (e.g. T-24h and T-2h): notify members of upcoming hangs. |
| 5 | **Group formation / fill** | `makeGroups()` is static (~L1226) | Periodic matcher: take open join intents per `activity_occurrences`, form 4–8 person groups mixing archetypes (the `mix` + `compat` logic the demo fakes), write `groups` + `group_memberships`, flag `filling_up`/`rec`. This is the real engine behind the demo's static templates. |
| 6 | **Day-of windows open/close** | `state.dayOf`, `seedDaySim` (~L3604) | On event day, a job opens the coordination window for each `activity_occurrences` (enables status posting + check-in), and closes it after the event, finalizing attendance from `check_ins`. |
| 7 | **Simulated-peer seeding** | `seedDaySim`/`daySimSeeded` | Not needed in production (real peers post real statuses) — drop. |
| 8 | **Retention / deletion sweeps** | n/a in demo | Scheduled jobs enforce the §9 retention schedule and process `data_deletion_requests` / `data_export_requests`. |

**Job principles:** all jobs idempotent (safe re-run), keyed so a duplicate enqueue is a no-op (mirrors the demo's `daySimSeeded`/`backfillSeen` one-shot guards), and run in the same Canadian region as the DB. Timers are server-owned — the client never holds the authoritative timer (today's `backfillTimers` being module-level, not on `state`, foreshadows this: the timer must survive independent of any single client's `state`).

---

## 7. Payments

There are **two distinct money concepts** in Perch, and only one of them touches a payment processor.

### Perch+ subscription → Apple / Google IAP

Perch+ (the demo's `state.plus`, `ppBill:"mo"`, `openPerchPlus`) raises the weekly cap from 2 to 5. Because the app ships through the App Store and Play Store, **the subscription must use Apple In-App Purchase and Google Play Billing** (store policy requires it for digital subscriptions). Flow:

- Purchase happens via the native IAP sheet (Capacitor IAP plugin).
- The store issues a receipt; the client sends it to `POST /billing/verify`; the server validates it with Apple/Google's verification API and writes/updates a `subscriptions` row (`plan`, `status`, `current_period_end`, store transaction id).
- **The cap check in `requestJoin` reads `subscriptions`, not a client flag** — the client can't grant itself Perch+. Server-to-server store webhooks keep `subscriptions.status` current (renewals, cancellations, refunds).

GST/QST and receipts for the subscription are **handled by Apple/Google** as merchant of record — Perch does not invoice the subscriber directly for IAP, which sidesteps Quebec sales-tax collection on the subscription itself.

### Activity tickets → PAY-AT-VENUE, no card captured

This is a **hard product invariant** and the backend honours it explicitly: **Perch never captures a card for activity tickets.** Ticketed activities are those with a `price` (e.g. `cooking $35`, `paint $30`, `axe $28`, index.html L1203/1214/1220). The demo's `openReservation` (~L3456) states `rsv_pay_note` ("pay at venue") and captures **no payment details** — `finishJoin` stores only `{code, ticket, price}` (~L3493).

In production:

- A join on a ticketed occurrence creates a `reservations` row with a server-generated **`PCH-XXXX` code** (`resvCode()` → `code: "PCH-" + 4 chars` from the unambiguous alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789`), `ticket: true`, and the `price` **as a display string only**.
- **No `payment_method`, no Stripe, no card vault.** The `price` is informational; the member pays the venue directly on arrival, showing the code.
- This deliberately keeps Perch **out of PCI scope for tickets entirely** and honours the no-payments constraint. The code is the only artifact — surfaced on the Joined screen and the joined group detail, exactly as the demo does.

If Perch ever collects ticket money (not in scope), it would require Stripe + **GST/QST** registration and Quebec-compliant receipts — flagged here as a future decision, not a launch feature.

---

## 8. Data residency & hosting

**Quebec's Law 25 makes data residency a first-class constraint, not a preference.** Default posture: **store personal data in a Canadian region**, and if any processing leaves Canada, run a privacy impact assessment and disclose the transfer (Law 25 requires it). Concrete vendor options, each with a residency note:

| Layer | Recommended | Canadian-residency note |
|---|---|---|
| **Database** | Supabase (AWS `ca-central-1`, Montreal/Toronto) **or** Neon CA region | Supabase supports `ca-central-1`; pin the project region at creation. |
| **Object storage** (profile photos `state.photo`) | Supabase Storage in CA region, **or** AWS S3 `ca-central-1` | Keep the bucket in `ca-central-1`; serve via CA-edge CDN. |
| **SMS / OTP** | Twilio (has Canadian infrastructure & local numbers) or Telnyx | Confirm message content/routing residency; OTP payloads are minimal PII. **Decision in §12.** |
| **Push** | APNs (Apple) + FCM (Google) | Push tokens aren't sensitive PII; payloads should be content-light (no message body in the push). |
| **Email** (receipts/notices) | AWS SES `ca-central-1`, or Postmark | Pin SES to `ca-central-1`. |
| **App hosting / API** | Containers in `ca-central-1` (Fly.io Montreal `yul`, AWS, or Render CA) | Co-locate API + workers + DB in the same Canadian region to minimize cross-border flow and latency. |

**Compute and data should share the Canadian region** so that ordinary request handling never moves personal data across the border. Backups stay in-region. CDN edge caching of *non-personal* assets (app shell, public activity content) may use global edges; personal data does not.

---

## 9. Privacy & compliance

Perch operates under **Quebec Law 25, federal PIPEDA, and Bill 96 (French-first)**. The backend bakes these in rather than bolting them on.

### Consent model (including quiz-before-sign-in)

- **The quiz runs before sign-in and before consent** — by design (acquisition artifact). During the anonymous phase we collect quiz answers under an anonymous session with **no PII** (§4). This is defensible because there's no identifiable individual yet.
- **Consent is captured at the attach moment** (first sign-in), when identity first exists: a `consent_records` row per consent type (terms acceptance, privacy policy, age attestation, marketing/`updates` notifications). Granular and revocable.
- **Legal acceptance** is recorded in `legal_acceptances` against a specific versioned `legal_documents` row, so we can prove *which version* of Terms/Privacy/Guidelines/Moderation/Wellbeing the user accepted (the demo's 5 in-app legal docs, en + fr, currently using the `LEGAL` placeholders — keep placeholders until counsel finalizes the entity; index.html L1103).

### Retention schedule (table → retention)

| Table(s) | Data | Retention |
|---|---|---|
| `quiz_responses` (anonymous) | Pre-account quiz answers | 30 days if never attached, then purge |
| `phone_verifications` | OTP codes/attempts | Minutes (TTL); purge verified/expired rows within 24h |
| `direct_messages`, `group_messages` | Chat content | Retain while account active; purge on account deletion; consider rolling purge of very old group chats |
| `day_of_statuses`, `backfill_offers`, `notifications` | Transient coordination | 30–90 days (operational), then purge |
| `check_ins`, `group_memberships` | Attendance/participation | Retain for reliability derivation while active; **anonymize** (strip account link) on deletion rather than dropping aggregate stats |
| `audit_log`, `consent_records`, `legal_acceptances` | Compliance evidence | Retain per legal-hold requirements even after account deletion (these *prove* we complied) |
| `accounts`, `profiles`, `user_interests`, `user_settings`, `friendships`, `friend_requests`, `blocks`, `past_connections`, `reservations`, `waitlist_entries`, `subscriptions` | Core PII | Deleted/anonymized on account deletion (§ below) |
| `reports` | Safety reports | Retained for safety/legal duration even past reporter deletion (anonymize reporter link) |

### Access, deletion, portability (rights endpoints)

These tie directly to API.md rights endpoints and the DB request tables:

- **Access / portability:** `POST /me/export` → a `data_export_requests` row → async job assembles the user's data (profile, interests, quiz result, memberships, reservations, messages they sent, settings) into a portable archive (JSON), delivered via a time-limited link. PIPEDA access right + Law 25 portability.
- **Deletion (in-app, permanent):** `POST /me/delete` → a `data_deletion_requests` row → async job **permanently** removes/anonymizes PII per the table above, revokes tokens, cancels realtime subscriptions, and tombstones the account. This satisfies the invariant "Account deletion is in-app and permanent." Compliance tables (`audit_log`, `consent_records`, `legal_acceptances`, `reports`) are retained as legally required, with the account link anonymized where possible.
- **Take-a-break** (safety feature, distinct from deletion): pauses visibility/joining without destroying data — a status on `accounts`, reversible.

### Audit log

Every privileged or rights-relevant action (consent given/revoked, export requested, deletion executed, report filed, moderation action, role/permission change) writes an `audit_log` row (`actor`, `action`, `subject`, `timestamp`, `metadata`). This is the evidence trail Law 25 / PIPEDA expect.

### Vendor DPAs

Sign Data Processing Agreements with every sub-processor (DB host, storage, SMS, push, email). Maintain a public sub-processor list. Prefer vendors offering Canadian residency and DPAs out of the box (§8).

### French-first content (Bill 96)

i18n parity is already a project invariant ("Full en / fr-CA coverage, including legal docs" — CLAUDE.md). The backend extends it: **all server-generated user-facing content** — notification copy, SMS/OTP messages, emails, error messages surfaced to users, legal documents — must exist in **both languages**, with **French available by default** for Quebec users. Server-side copy lives in a `translations` table (parity-checked the way the `check-i18n` skill checks the client). The user's language (today `localStorage perch_lang`) becomes a stored `accounts`/`user_settings` preference so server-sent messages match their choice.

---

## 10. Security

### Authorization model — ownership / row-level

The demo has no auth, but its `state` is implicitly "the current user's." Production makes ownership explicit and enforced:

- **Default-deny.** Every row that belongs to a user (`profiles`, `user_settings`, `reservations`, `waitlist_entries`, `direct_messages`, …) is readable/writable only by its owner, enforced by **Postgres row-level security** (or equivalent middleware) keyed on `account_id` from the JWT — not by client-supplied ids.
- **Group-scoped access:** reading a `group_messages` thread or posting a `day_of_statuses` requires an active `group_memberships` row for that group. Realtime subscriptions check the same.
- **Relationship-gated visibility** mirrors the demo's settings (`whoMessage`, `whoAdd`): DMs and friend requests respect "friends-only / everyone" preferences server-side; **blocks** (`blocks` table) hard-cut visibility and messaging both ways. Photos are **friends-only** (brand invariant) — the storage URL for `state.photo` is access-controlled, not public.

### The invariant-critical join funnel must be server-enforced

The single join path — **cap check → profile gate → begin join → (reservation if ticketed) → finish join**, and the waitlist **claim** routing through the *same* path (`requestJoin`, ~L3508; `openClaimSpot` → `requestJoin`, ~L3527) — must live on the server. The client may *render* the paywall or profile sheet, but:

- The **cap** is recomputed server-side per ISO week against `subscriptions` (2 free / 5 Perch+).
- The **profile gate** (`needsProfile()` / `state.profileComplete`) is enforced at the join endpoint — a join without a complete profile is rejected and triggers `openProfileSetup`.
- The **reservation step** is created server-side only for ticketed occurrences.
- **A claim can never call finish-join directly** to bypass cap/gate/reservation (the demo is explicit about this) — the endpoint for claiming a backfill offer routes through the same join handler.

### Rate limiting

Per-account and per-IP limits on: OTP requests (`phone_verifications` — strict, with lockout/backoff to prevent SMS-pumping fraud), join/claim attempts, message sends, friend requests, reports, and search. Tighter limits on anonymous (pre-auth) endpoints.

### Abuse / report tooling + 24h review SLA

- `reports` rows are created by users (report a person/message/group). A report enqueues a **human-review task with a 24-hour SLA** (brand invariant: "report → human review within 24h"). A lightweight internal moderation queue (could start as an admin view over `reports`) tracks state and SLA breach.
- Moderation actions (warn, remove from group, suspend, ban) write to `audit_log` and may set account status. Blocking is private (the blocked user isn't told).

### Secrets

All secrets (JWT signing keys, store IAP credentials, SMS/push/email keys, DB creds) in a managed secret store / platform secrets — never in the repo, never shipped to the client. Rotate signing keys with overlap.

### Input validation & escaping parity

Port the demo's discipline to the server:

- **Validation:** `usernameStatus()` rules (3–20 chars, `/^[a-z0-9._]+$/`, uniqueness vs `profiles` + `reserved_usernames`) become a shared server validator — the client check is convenience, the server check is authority. Same for age ≥ 18, interest values within `interests`, archetype keys within `archetypes`.
- **Escaping:** the demo escapes every interpolated string via `esc()` (L1751). The server stores raw user text but **escapes on output** in any server-rendered context (emails, notifications, exports) and relies on parameterized queries everywhere (no string-built SQL). User-generated content is treated as untrusted end-to-end.

---

## 11. Observability

### Logging, metrics, errors

- **Structured JSON logs** (request id, account id where authorized, route, latency) — never log message bodies, OTP codes, or other PII.
- **Metrics:** request rates/latency/error rates per endpoint, job queue depth and failure counts (backfill, formation, reminders), realtime connection counts, OTP send/verify success rates, push delivery rates.
- **Error tracking:** Sentry (or equivalent), client + server, with PII scrubbing.
- **Uptime/health checks** on API, DB, realtime, and the worker.

### Product KPIs worth tracking

These flow from PLAN.md's thesis (strangers → friends, reliability as the currency):

- **Show-up rate** — `check_ins` ÷ `group_memberships` for past occurrences. *The* north-star: friendship can't form if people don't show. Reliability is attendance-based (`isReliable`), so this is also the health of the reputation system.
- **Group fill rate** — how often forming groups reach 4–8 (`groups.filled` ÷ `size`); low fill means the matcher or supply is weak.
- **Week-2 retention** — share of new members who join a second hang the following week; the real test of whether the product makes friends, not just bookings.
- **Quiz → sign-in conversion** — the acquisition artifact's effectiveness (anonymous `quiz_responses` that attach to an account).
- **Free → Perch+ conversion** — share hitting the 2/week cap who subscribe.
- **Waitlist → backfill claim rate** — does the offer loop actually convert.
- **Time-to-first-friend** and **report rate per 1k hangs** (safety health).

KPIs are computed from the same tables that run the product (no separate analytics pipeline at launch); revisit a warehouse only when query load justifies it.

---

## 12. Open decisions for the founder

Each needs a call before build; a recommendation is given.

1. **Self-attested vs verified age (18+).**
   The demo self-attests (`state.age` stepper, floored at 18). Hard ID verification adds friction and privacy burden (storing government ID is itself a Law 25 liability).
   **Recommendation:** Launch **self-attested**, recorded as a `consent_records` age attestation, with phone verification as a soft signal. Add stronger checks only if abuse or regulation demands it.

2. **Quiz-before-consent flow (Law 25 exposure).**
   The quiz intentionally runs before sign-in/consent, which means collecting answers before any consent dialog.
   **Recommendation:** Keep the flow, but collect the quiz **fully anonymously** (no PII, anonymous session) and capture consent at the attach moment (§4/§9). This preserves the acquisition magic while staying defensible. Have counsel confirm the anonymous-collection framing.

3. **Data residency: Canada-only vs allow US processing.**
   Canada-only is the safest Law 25 posture but narrows vendor choice (some SMS/push/error tools are US-centric).
   **Recommendation:** **Canada-only for stored personal data and primary compute.** Tolerate US processing *only* for low-sensitivity, content-light flows (push token relay, error traces with PII scrubbed), each covered by a DPA and disclosed. Run a PIA before any cross-border flow.

4. **Build vs buy chat/realtime.**
   Building a socket server is real work against a lightweight ethos.
   **Recommendation:** **Buy** — use Supabase Realtime (Postgres change feeds) so chat, day-of, and backfill ride the database we already run. Reconsider building only if message volume or features (typing, presence at scale) outgrow it.

5. **SMS vendor (OTP).**
   Drives auth reliability, cost, fraud exposure, and residency.
   **Recommendation:** **Twilio** at launch (mature Verify product with built-in OTP fraud controls, Canadian numbers), with strict server-side rate limiting and lockout to prevent SMS-pumping. Re-evaluate Telnyx/AWS for cost at scale. Confirm message routing residency with the vendor.

6. **(Bonus) Group-formation cadence and supply.**
   The matcher (§6, job #5) is the product's beating heart and the demo entirely fakes it.
   **Recommendation:** Start with a **simple, scheduled batch matcher** per `activity_occurrences` that mixes archetypes toward 4–8, and instrument fill/show-up before investing in anything cleverer. The demo's `compat`/`mix` framing is a UI promise the matcher must eventually earn.

---

*End of BACKEND.md. See `schema.sql` for table DDL and `API.md` for endpoint contracts. All copy, legal text, and server-sent messages must ship in en and fr-CA (Bill 96); placeholders in the `LEGAL` constants stay until counsel finalizes the legal entity.*
