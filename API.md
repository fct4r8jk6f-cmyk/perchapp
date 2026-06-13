# Perch REST API — Specification (v1)

> The backend the single-file Perch demo implies. Server-authoritative model for a bilingual (en / fr-CA) Montreal small-group friend-making app. Every product invariant the demo enforces in JS (weekly cap, the single join funnel, attendance-based reliability, pay-at-venue, optional verification, deterministic waitlist, Law 25 / Bill 96 rights) is enforced here server-side.
>
> Table and column names below match `schema.sql` exactly. Read `schema.sql` for the authoritative data model; this document is the wire contract over it.

---

## 1. Conventions

### 1.1 Base URL & versioning
- Base: `https://api.perch.app/v1`
- Versioned by URL prefix (`/v1`). Breaking changes ship under `/v2`; additive fields are not breaking.
- All times are ISO-8601 UTC (`timestamptz`); clients render in `America/Toronto`. **The weekly-cap ISO week is computed server-side in `America/Toronto`** (matches `group_memberships.join_iso_week`), never from a client clock.

### 1.2 Content type & casing
- Request and response bodies are `application/json; charset=utf-8`.
- JSON fields are `snake_case`, mirroring schema columns. UUIDs are canonical hyphenated form.

### 1.3 Auth & session model
Three principal states, matching the demo's onboarding firewall:

| Principal | Obtained via | Can do |
|---|---|---|
| **Anonymous quiz session** | `POST /quiz/sessions` → `anonymous_session_id` (sent as `X-Anon-Session: <uuid>`) | Take the quiz, browse catalog. No account row. |
| **Authenticated, no profile** | Phone-OTP sign-in → `access_token` (Bearer) | Browse, search, read public cards, manage settings/verification. **Cannot join/host** (profile gate). |
| **Authenticated, profile complete** | Same token, after `POST /profile` | Everything, subject to weekly cap. |

- `Authorization: Bearer <access_token>` on all authenticated calls. Tokens are short-lived JWT access + rotating refresh (`POST /auth/token/refresh`).
- The quiz runs **before** sign-in by design (it is the shareable acquisition artifact); the anonymous result is **attached** to the account at sign-up (§3.3).
- Browsing requires no profile; the join/host endpoints return `403 profile_required` until `profiles.profile_complete = true`.

### 1.4 Locale header (Bill 96)
- `Accept-Language: fr-CA` (default) or `en`. Resolution order: header → `accounts.preferred_locale` → `fr-CA` (Quebec default).
- All localized response strings (catalog names, legal docs, notification copy) are served in the resolved locale via the `translations` table / `legal_documents` rows. Canonical-English keys/ids are **always** returned alongside translated display strings so the client can filter on canonical values (e.g. `activity.id`, `category`, `archetype_key`).
- The resolved locale is echoed back as `Content-Language` and recorded in `consent_records.locale_shown` / `audit_log` for any consent-bearing call.

### 1.5 Error envelope
All non-2xx responses share one shape:
```json
{ "error": { "code": "profile_required",
             "message": "Set up your profile to join.",
             "message_fr": "Configure ton profil pour participer.",
             "details": { "field": "username" } } }
```
- `code` is a stable machine string (documented per-endpoint); `message`/`message_fr` are display-ready in the resolved locale-pair. Common codes: `unauthenticated` (401), `forbidden` (403), `not_found` (404), `conflict` (409), `validation_failed` (422), `rate_limited` (429).

### 1.6 Pagination
- Cursor-based: `?limit=<1-100, default 20>&cursor=<opaque>`. Responses include `{ "items": [...], "next_cursor": "<opaque|null>" }`. Lists are newest-first unless noted (e.g. waitlist queue is position-first).

### 1.7 Idempotency
- All state-changing **side-effect-once** calls (join confirm, reservation create, friend request, report, subscription start, verification send) accept an `Idempotency-Key: <uuid>` header. The server stores the first response keyed by `(account_id, key)` and replays it on retry. The join-confirm path additionally relies on the DB unique index `uq_one_active_membership` so a double-tap can never create two active memberships.

### 1.8 Realtime
REST is the default. The following surfaces also push over a single authenticated **WebSocket** at `wss://api.perch.app/v1/ws` (subscribe by channel). Each has a REST fallback for history/initial load:

| Channel | Pushes |
|---|---|
| `group:{group_id}` | group chat messages, system join/leave/check-in lines, day-of statuses |
| `dm:{thread_id}` | direct messages, seen receipts |
| `user:{account_id}` | notifications, **backfill offers** (with `expires_at`), friend requests, group-match |

Endpoints that are realtime-backed are tagged **[RT]** below.

---

## 2. Catalog & Browse  *(no auth required; no profile required)*

Reference data is canonical-English in the DB and returned with locale-resolved display strings + canonical keys.

### `GET /activities`
- **Auth:** none. **Purpose:** list activity templates for the browse rail.
- **Query:** `category` (`activity_category` enum incl. `For you`), `day` (date, filters by `activity_occurrences.starts_at`), `size` (min group size), `cursor`/`limit`.
- **Response:** items of `{ id, icon, name, category, schedule_text, group_size_text, min_size, max_size, vibe, plan_b, social_proof, badge, price, is_recurring, default_venue }`. `price != null` ⇒ **ticketed** (pay-at-venue). `For you` ranks against the caller's `profile_key` when authenticated.
- **Notes:** `category` and `id` are canonical; `name`/`vibe`/`plan_b`/`badge` are locale-resolved.

### `GET /activities/{activity_id}`
- **Auth:** none. **Purpose:** full activity detail + upcoming occurrences. **Errors:** `404 not_found` if inactive/unknown.

### `GET /activities/{activity_id}/occurrences`
- **Auth:** none. **Purpose:** dated instances (`activity_occurrences`). **Query:** `from`/`to` dates. **Response:** `{ id, starts_at, venue, groups_forming, status }` (defaults to upcoming-only).

### `GET /occurrences/{occurrence_id}/groups`  ·  `GET /activities/{activity_id}/groups`
- **Auth:** none (joinability is evaluated at join time). **Purpose:** groups forming for an activity/occurrence.
- **Response:** `{ id, emoji, name, when_text, starts_at, filled, max_size, min_size, vibe_tags, archetype_mix, personality, compatibility, status, open_waitlist, is_recommended }`. `filled == max_size` ⇒ full (waitlist only). `name`/`vibe_tags`/`personality`/`compatibility` are locale-resolved (`GRPFR`); member identities are **not** exposed here beyond `archetype_mix`.

### `GET /people`
- **Auth:** none. **Purpose:** people directory search. **Query:** `q` (matches name or `@username`), `cursor`/`limit`.
- **Response:** **public cards only** — `{ account_id, name, emoji, username, archetype_key, archetype_name, archetype_badge, verified, mutual_count }`. Names/usernames are proper nouns — **never translated**. `archetype_name`/`badge` are locale-resolved.

### `GET /people/{account_id}`  ·  `GET /people/by-username/{username}`
- **Auth:** none for the public card. **Purpose:** a person's public card.
- **Response:** public fields above. **`photo_url`, `bio`, and `interests` are withheld unless the caller is an accepted friend** (`friendships`), per the friends-only visibility rule. **Errors:** `404 not_found`; `410 gone` if `deleted_at` set.

### `GET /interests`  ·  `GET /archetypes`  ·  `GET /archetypes/{key}`
- **Auth:** none. **Purpose:** reference lists for profile setup and the result screen. Locale-resolved labels (`INT_FR`, `ARFR`) + canonical keys.

---

## 3. Auth & Onboarding

### `POST /quiz/sessions`  *(anonymous)*
- **Auth:** none. **Purpose:** start an anonymous quiz session before sign-in.
- **Response:** `{ anonymous_session_id }` (use as `X-Anon-Session`). No `accounts` row created.

### `GET /quiz`  *(anonymous)*
- **Auth:** none. **Purpose:** the 7 `quiz_questions` + `quiz_options` (locale-resolved labels). Response ordered by `question_id` 0–6.

### `POST /quiz/sessions/{anonymous_session_id}/responses`  *(anonymous)*
- **Auth:** `X-Anon-Session`. **Purpose:** submit answers, get archetype.
- **Request:** `{ answers: [i0..i6] }` — 7 option indices (0–3). **Validation:** `array_length = 7`.
- **Response:** `{ result_archetype, archetype: { key, name, tag, traits, bring, loves, descr, gradient_class } }`. Persists a `quiz_responses` row keyed by `anonymous_session_id` (`account_id` null until attach). **Errors:** `422 validation_failed`.

### `POST /auth/otp/start`
- **Auth:** none. **Purpose:** begin phone-OTP sign-up/sign-in. **Request:** `{ phone }` (E.164). **Response:** `{ otp_token, expires_at }` (a 4-digit code is sent; never returned). **Errors:** `429 rate_limited` (per-phone throttle). *This is the account-auth OTP — distinct from optional phone verification (§7).*

### `POST /auth/otp/verify`
- **Auth:** none. **Purpose:** complete sign-in, mint tokens, create the account on first use.
- **Request:** `{ otp_token, code, anonymous_session_id?, age, age_attested, accepted_doc_version_ids[], preferred_locale? }`.
- **Behaviour (first sign-in):** creates `accounts` (`age >= 18` enforced — **18+ self-attested gate, disclosed before the quiz**; sets `age_attested_at`, `agreed=true`), **merges the anonymous `quiz_responses`** (`anonymous_session_id` → `account_id`) so the archetype carries over, writes `consent_records` (`age_18_plus`, `terms`, `privacy`, `guidelines`, `moderation`, `wellbeing`) with `locale_shown`, and `legal_acceptances` for each `doc_version_id`. Seeds `user_settings`.
- **Response:** `{ access_token, refresh_token, account: {...}, profile_complete: false }`.
- **Errors:** `422` (`age < 18` → `age_below_minimum`; missing required consent → `consent_required`; bad code → `invalid_code`).

### `POST /auth/token/refresh`  ·  `POST /auth/signout`
- **Auth:** refresh token / Bearer. Rotate access token; revoke session.

### `GET /me`
- **Auth:** Bearer. **Purpose:** the caller's account snapshot — `{ account_id, email, age, verified, attended, checked_in, subscription_tier, preferred_locale, region, break_until, profile_complete, reliability_tier }` (see §8 for the tier — **no public numeric score**).

---

## 4. Profile  *(auth required)*

### `GET /profile/username-available`
- **Auth:** Bearer. **Purpose:** live username availability (mirrors `usernameStatus`).
- **Query:** `username`. **Response:** `{ available: bool, code }` where `code ∈ { ok, too_short (<3), invalid (>20 or not ^[a-z0-9._]+$), taken }`. Taken = present in `profiles` (citext, case-insensitive) **or** `reserved_usernames`. Always 200 (validity is in the body).

### `POST /profile`
- **Auth:** Bearer (no profile yet). **Purpose:** **on-demand** profile creation (the `needsProfile` gate). Browsing never requires this; it is created at first join/host.
- **Request:** `{ name (≤30), username (3–20, ^[a-z0-9._]+$), emoji, bio? (≤120), photo_url?, interests[] (1–5 interest keys) }`. `profile_key` is taken from the attached `quiz_responses` (not client-supplied).
- **Response:** the profile with `profile_complete: true`; writes `profiles` + `user_interests`.
- **Errors:** `409 conflict` (`username_taken`), `422 validation_failed`, `409 profile_exists` (already complete).

### `PATCH /profile`
- **Auth:** Bearer (profile complete). **Purpose:** edit name/username/emoji/bio/interests/photo. Username change re-runs availability. Same validation/errors as create.

### `POST /profile/photo`
- **Auth:** Bearer. **Purpose:** upload avatar; returns `{ photo_url }`. **Friends-only** — the API withholds it from non-friends on every read.

### `GET /profile`
- **Auth:** Bearer. **Purpose:** the caller's own full profile (all fields visible to self).

---

## 5. Join Funnel  *(the single path — enforced server-side)*

> **Invariant:** every confirmed join — including a waitlist **claim** — flows through this exact order: **weekly-cap check → profile gate → (reservation step *only if ticketed*) → confirm**. No endpoint creates a `group_memberships` row outside this funnel. This mirrors `requestJoin → beginJoin → (openReservation) → finishJoin`.

### `GET /groups/{group_id}/join/preview`  *(eligibility/preview)*
- **Auth:** Bearer. **Purpose:** single source of truth for "can I join, and what happens next" — render the CTA from this.
- **Query:** `activity_id?` (the activity chosen at join; may differ from the group default).
- **Response:**
  ```json
  { "eligible": true,
    "cap": { "tier": "free", "used": 2, "limit": 2, "iso_week": "2026-24", "exceeded": true },
    "profile_required": false,
    "ticketed": true, "price": 12.00,
    "group_full": false, "open_waitlist": false,
    "next_step": "paywall" }
  ```
- `cap.limit` = 2 (free) / 5 (plus), counted from `group_memberships` where `status IN (active, attended)` in the current `join_iso_week`; **waitlist entries never count**. `next_step ∈ { confirm, reservation, profile, paywall, waitlist }`. **This is advisory** — the confirm endpoint re-checks every gate authoritatively.

### `POST /groups/{group_id}/join`  *(confirm join — the funnel entry)*
- **Auth:** Bearer. **Idempotency-Key** required. **Purpose:** the one mutation that confirms a join.
- **Request:** `{ activity_id?, reservation_token? }`.
- **Server sequence (authoritative, in order):**
  1. **Cap check** → if confirmed joins this ISO week ≥ tier limit ⇒ `402 cap_exceeded` (`{ paywall: "perch_plus" }`). *(3rd free join hits the Perch+ paywall.)*
  2. **Profile gate** → if `profile_complete = false` ⇒ `403 profile_required`.
  3. **Capacity** → if `filled == max_size` ⇒ `409 group_full` (`{ open_waitlist: true }`, client routes to §6).
  4. **Reservation gate** → if the activity is **ticketed** (`price != null`) and no valid `reservation_token` is presented ⇒ `409 reservation_required` (`{ reservation_endpoint }`). Free activities skip straight to confirm.
  5. **Confirm** → create `group_memberships` (`status='active'`, `role='member'`, `activity_id`), increment `groups.filled` (atomic, `filled <= max_size` enforced by `filled_within_capacity`), create the `reservations` row (**every** join gets a `PCH-XXXX` code; `ticket`/`price` set only for ticketed), clear any `waitlist_entries` for this group, post a system join message to `group_messages`, open/seed the chat thread.
- **Response:** `{ membership_id, status, reservation: { code, ticket, price }, group: {...} }`.
- **Errors:** `402 cap_exceeded`, `403 profile_required`, `409 group_full`, `409 reservation_required`, `409 already_member` (`uq_one_active_membership`).

### `POST /groups/{group_id}/reservation`  *(reservation create — ticketed step)*
- **Auth:** Bearer. **Idempotency-Key** required. **Purpose:** the booking step for **ticketed** activities. **PAY-AT-VENUE — no card is captured, no payment instrument is stored** (honours the no-payments constraint).
- **Request:** `{ activity_id }`. **Response:** `{ reservation_token, code: "PCH-XXXX", ticket: true, price, pay_note: "Pay at the venue" }`. Hand `reservation_token` to `POST .../join` to confirm.
- **Notes:** Code matches `^PCH-[A-Z0-9]{4}$` (unambiguous alphabet, no `0/O/1/I/L`), unique across `reservations`. The reservation is finalized (persisted, `filled++`) only on confirm; cancelling a join voids it (`voided_at`).
- **Errors:** `402 cap_exceeded` and `403 profile_required` are re-checked here too (the reservation step never bypasses the gates), `404 not_found`, `422` (activity not ticketed).

### `POST /hosts/groups`
- **Auth:** Bearer (**profile required**). **Purpose:** host a new group for an occurrence. Hosting honours the **same profile gate** but does **not** require verification. **Request:** `{ occurrence_id, activity_id, max_size (≤10; >8 only for Perch+ hosts), name?, vibe_tags? }`. Creates `groups` (`host_account_id`) + a host `group_memberships` row. **Errors:** `403 profile_required`, `422` (`max_size` out of range for tier).

### `GET /me/groups`
- **Auth:** Bearer. **Purpose:** the Joined screen — active/hosted/past memberships with their `reservations.code`, `when_text`, `status`. **Query:** `state ∈ { active, hosted, past }`.

### `POST /memberships/{membership_id}/leave`
- **Auth:** Bearer. **Purpose:** leave a group. Sets `status='left'`/`left_at`, decrements `filled`, **voids** the reservation, posts a system leave line, and **frees a spot → triggers a backfill offer** to the next waitlisted person (§6). Leaving does **not** refund a cap slot retroactively within the same week (the join already occurred).

---

## 6. Waitlist & Automatic Backfill  *(auth required)* **[RT]**

### `POST /groups/{group_id}/waitlist`
- **Auth:** Bearer. **Purpose:** join the waitlist for a full group. **Request:** `{ activity_id? }`.
- **Response:** `{ waitlist_entry_id, position, status: "waiting" }`. **`position` is deterministic and never #1** (`CHECK position >= 2`; reliable members rank one slot higher) — you're never the only one waiting. **No cap check here** (waitlisting is not a confirmed join). **Errors:** `409 already_waiting` (`uq_one_active_waitlist`), `409 not_full` (group still has room — join instead).

### `DELETE /groups/{group_id}/waitlist`
- **Auth:** Bearer. **Purpose:** leave the waitlist (`status='left'`).

### `GET /me/waitlist`
- **Auth:** Bearer. **Purpose:** the caller's waitlist entries with `position` and any active offer.

### `POST /backfill-offers/{offer_id}/accept`  *(claim — routes through the funnel)*
- **Auth:** Bearer. **Idempotency-Key** required. **Purpose:** accept a time-limited backfill offer.
- **Behaviour:** **re-enters the §5 join funnel** (`requestJoin`) — cap, profile gate, and reservation step **all re-apply**. If the cap blocks it (e.g. hit the Perch+ limit), the user **stays on the waitlist** (the entry is not dropped). On success: marks `backfill_offers.status='claimed'`, the `waitlist_entries` row `claimed`, creates the membership exactly as a normal join.
- **Errors:** `410 offer_expired` (past `expires_at` ≈ 90s TTL; user remains waitlisted), `402 cap_exceeded`, `403 profile_required`, `409 group_full` (race lost).

### `POST /backfill-offers/{offer_id}/decline`
- **Auth:** Bearer. **Purpose:** decline; offer marked `expired`, queue advances to the next person.

> **[RT]** When a spot frees (a leave/cancel), the server fires **one** active offer per group (`uq_one_active_offer_per_group`) to the next `waiting` entry (`idx_waitlist_queue`), pushes it on `user:{account_id}` + a `notifications` row (`backfill_offer` type) with `expires_at`, and a sweep job expires it after the TTL. On expiry the user **keeps** their waitlist entry.

---

## 7. Phone Verification  *(auth required; OPTIONAL — never gates join/host)*

### `POST /verification/phone/start`
- **Auth:** Bearer. **Idempotency-Key**. **Purpose:** begin optional phone verification (trust signal only). **Request:** `{ phone }` (E.164). **Response:** `{ verification_id, code_expires_at }` (4-digit code sent, never returned; `phone_verifications` row, `status='pending'`).

### `POST /verification/phone/confirm`
- **Auth:** Bearer. **Purpose:** confirm the code. **Request:** `{ verification_id, code }` (4 digits). **On success:** sets `accounts.verified=true`/`verified_at`, `phone_verifications.status='verified'`; writes `audit_log` (`verify.success`).
- **Errors:** `422 invalid_code`, `410 code_expired`.
- **Invariant:** `verified` is a trust badge only. **No join, reservation, host, or waitlist endpoint may check it.** A subset of seeded people carry `verified:true` for display.

---

## 8. Reliability & Day-Of Coordination  *(auth required)* **[RT]**

> Reliability is **attendance-based and private**: `is_reliable = (attended > 0 OR checked_in)`. `attended` is bumped **only** by check-in, never by joining. There is **no public numeric show-up score and no ranking** ("not a popularity contest").

### `GET /me/reliability`
- **Auth:** Bearer. **Purpose:** the caller's own warm tier. **Response:** `{ tier, label }` where `tier ∈ { new, building, good }` (`new` = no joins/waitlist yet; `building` = booked but not yet attended; `good` = attended/checked-in → framed as 100%). **Only the caller sees their own tier**; other people's cards expose `verified` and `mutual_count`, never a reliability number.

### `POST /groups/{group_id}/day-of-status`
- **Auth:** Bearer (member). **Purpose:** post event-day status. **Request:** `{ status: "on_my_way" | "running_late" | "here" | "ride", want_ride? }`.
- **Behaviour:** upserts `day_of_statuses` (unique per `(group_id, account_id)`). **`status="here"` routes through the shared check-in** (§ below) — it does not duplicate logic. `ride` is display-only. **Only meaningful on event day** (`starts_at` is today); off-day posts return `409 not_event_day`. **[RT]** broadcasts on `group:{group_id}`.

### `POST /groups/{group_id}/check-in`
- **Auth:** Bearer (member). **Idempotent** (`UNIQUE(group_id, account_id)` on `check_ins`). **Purpose:** the single check-in path (= `status:"here"`).
- **Behaviour (first check-in only):** insert `check_ins`; flip `group_memberships.attended=true`; bump `accounts.attended` and set `checked_in=true` (**this is the only thing that raises reliability**); post a "X checked in" system message. Repeat calls are no-ops (200, idempotent).
- **Response:** `{ checked_in: true, attended_count, reliability_tier }`.

### `GET /groups/{group_id}/day-of`
- **Auth:** Bearer (member), event day. **Purpose:** the coordination panel — member statuses + who has checked in (first names + emoji only). Returns `409 not_event_day` off-day.

---

## 9. Social  *(auth required)*

### Friends
- **`GET /friends`** — list accepted friends (`friendships`), each with public card + `context`. *(REST.)*
- **`POST /friend-requests`** — send a request. Request: `{ recipient_id, context? }`. **Server-gated by the recipient's `user_settings.who_add`**: `no_one` ⇒ `403 recipient_not_accepting`; `friends_of_friends` and caller is not a FoF ⇒ `403 forbidden`; blocked either direction ⇒ `404 not_found` (silent). `409 already_pending`/`already_friends`. **[RT]** pushes to `user:{recipient_id}`.
- **`GET /friend-requests?direction=received|sent`** — incoming/outgoing pending requests.
- **`POST /friend-requests/{id}/accept`** — creates the `friendships` row (canonical `account_lo<account_hi`), unlocking friends-only photo/bio/interests. **`POST /friend-requests/{id}/decline`** — sets `declined`.
- **`DELETE /friends/{account_id}`** — unfriend.

### Direct Messages **[RT]** (channel `dm:{thread_id}`)
- **`GET /dm/threads`** — DM threads, recency-ordered, with last message + unread flag.
- **`GET /dm/threads/{thread_id}/messages`** — paginated history (cursor).
- **`POST /dm/threads`** — open/get a 1:1 thread. Request: `{ account_id }`. **Must be friends**; `403 not_friends`.
- **`POST /dm/threads/{thread_id}/messages`** — send. **Gated by recipient's `who_message`** and by `blocks` (a block makes sends fail silently → `404 not_found`); `403 messaging_not_allowed`. Updates `last_message_at`.
- **`POST /dm/threads/{thread_id}/seen`** — mark read (sets `seen_at`).

### Group Chat **[RT]** (channel `group:{group_id}`)
- **`GET /groups/{group_id}/chat/messages`** — members-only history. System lines (`kind='system'`, null sender) announce joins/leaves/check-ins/day-of. First-names + emoji only.
- **`POST /groups/{group_id}/chat/messages`** — send. Request: `{ body, quoted_message_id? }`. `403 not_a_member`.
- **`POST /groups/{group_id}/chat/read`** — update `chat_read_state.last_read_at` (powers the unread badge).
- **`POST /messages/{message_id}/reactions`** — toggle an emoji reaction (`group_messages.reactions` jsonb).

### Block / Unblock
- **`POST /blocks`** — Request: `{ blocked_id, reason? }`. **Private**: the blocked user is never notified, stays in shared groups (hidden, not kicked), and any friendship is dropped in-app. **`DELETE /blocks/{blocked_id}`** — unblock. **`GET /blocks`** — caller's block list (reason never exposed to the blocked party).

---

## 10. Reports & Safety  *(auth required)*

### `POST /reports`
- **Auth:** Bearer. **Idempotency-Key**. **Purpose:** report a person → **human review within 24h**.
- **Request:** `{ reported_id, reason: report_reason, description?, group_id?, message_id? }` where `reason ∈ { inappropriate_messages, harassment, made_uncomfortable, spam_scam, no_show_unsafe, other }`.
- **Response:** `{ report_id, status: "submitted", due_at }` (`due_at = now + 24h`). **Reporter identity is never disclosed** to the reported user; no public voting/ranking. Writes `audit_log`.

### `POST /me/break`  ·  `DELETE /me/break`
- **Auth:** Bearer. **Purpose:** take-a-break. Request: `{ duration_days: 7 | 14 | 30 }` → sets `accounts.break_until`. While active: **no joins, no matches, notifications suppressed** (join/host/match endpoints return `403 on_break`). `DELETE` clears it; it also auto-clears once past.

---

## 11. Notifications  *(auth required)* **[RT]** (channel `user:{account_id}`)

### `GET /notifications`
- **Auth:** Bearer. **Purpose:** inbox, newest-first, with unread count. **Query:** `unread_only?`. Localized to `preferred_locale`. Each item: `{ id, type, title, body, related_entity_id, seen_at, muted_until, created_at }`. Types: `hang_reminder, message, friend_request, group_match, product_update, backfill_offer, checkin, moderation_outcome`.

### `POST /notifications/{id}/seen`  ·  `POST /notifications/read-all`
- **Auth:** Bearer. **Purpose:** mark one/all read (`seen_at`).

### `POST /notifications/{id}/mute`
- **Auth:** Bearer. **Purpose:** snooze. Request: `{ until: "1h"|"8h"|"tomorrow"|"event_end" }` → `muted_until`.

> Delivery is gated **before** a row is written by `user_settings.notif_*` for that type; a `backfill_offer` notification always carries the offer's `expires_at`.

---

## 12. Settings  *(auth required)*

### `GET /settings`  ·  `PATCH /settings`
- **Auth:** Bearer. **Purpose:** read/update `user_settings`.
- **Server-synced + enforced:** `who_message`, `who_add` (**access control** — applied to DM send and friend requests), `notif_reminders/messages/friend_req/matches/updates` (gate delivery), `active_status`, `theme`, `preferred_locale`.
- **Server-synced, functional (accessibility — real, not cosmetic):** `reduce_motion`, `bold_text`, `high_contrast`, `larger_targets` (≥48px hit areas), `text_size` (`default`/`large`). The client applies these; they are persisted for multi-device.
- **Device-local (NOT in `user_settings`):** the **active language** is mirrored client-side in `localStorage perch_lang` for instant first paint, but the server source of truth is `accounts.preferred_locale`. The demo's in-session-only theme is **promoted to server-synced** here (`user_settings.theme`) for multi-device; treat any pre-auth theme toggle as device-local until sign-in.
- **Errors:** `422 validation_failed`.

---

## 13. Perch+ Subscription  *(auth required)*

> Raises the weekly join cap **2 → 5**, plus priority matching and host perks. **No card is captured here** — billing is delegated to **Apple / Google IAP** (or a processor); only lifecycle + display amount are stored.

### `GET /subscription`
- **Auth:** Bearer. **Purpose:** current status. **Response:** `{ tier, status, plan, amount, trial_ends_at, renews_at, cancels_at, auto_renew, weekly_cap }`. `weekly_cap` = 2 (free) / 5 (plus).

### `POST /subscription`
- **Auth:** Bearer. **Idempotency-Key**. **Purpose:** start Perch+ after an IAP purchase. **Request:** `{ plan: "monthly"|"annual", store_receipt }` (Apple/Google receipt — **not a card**). Validates the receipt server-side, creates `subscriptions` (`status='trial'|'active'`, 7-day trial), flips `accounts.subscription_tier='plus'` (denormalized for cheap cap checks; `uq_active_subscription` guarantees one active). **Errors:** `402 receipt_invalid`, `409 already_subscribed`.

### `DELETE /subscription`
- **Auth:** Bearer. **Purpose:** cancel (sets `cancels_at`, `auto_renew=false`; tier reverts to `free` at period end). Actual store cancellation is the user's responsibility in the IAP UI; this records intent + syncs from store webhooks.

> **Webhook (server-to-server):** `POST /webhooks/iap` — Apple/Google billing events reconcile `subscriptions.status` and `accounts.subscription_tier`. Not a client endpoint (signed by store).

---

## 14. Feedback  *(auth required)*

### `POST /groups/{group_id}/feedback`
- **Auth:** Bearer (member, post-event). **Purpose:** post-hang survey → shapes future matching. **Request:** `{ activity_rating?, venue_rating?, vibe_rating? }` (0–5 each), `{ note? }`. One per `(group_id, account_id)` (`409 already_submitted`). Adding new friends during feedback is a **separate** `POST /friend-requests` call.

---

## 15. Law 25 / PIPEDA / Bill 96 Rights  *(auth required)*

### `GET /legal/documents`  *(no auth required)*
- **Purpose:** current legal docs in the resolved locale. **Response:** the 5 current `legal_documents` (`terms, privacy, guidelines, moderation, wellbeing`) — `{ doc_key, locale, version, content_html, effective_at }`. **Each must exist with equal-quality en + fr-CA** (Bill 96). Uses `[Legal Entity Name, Inc.]` placeholders (pending attorney review). `GET /legal/documents/{doc_key}?locale=` for one.

### `GET /me/consents`
- **Auth:** Bearer. **Purpose:** the caller's `consent_records` history (kind, granted, doc version, `locale_shown`, timestamp) — Law 25 transparency.

### `POST /me/consents`
- **Auth:** Bearer. **Purpose:** grant/withdraw a consent (e.g. `marketing`). Request: `{ kind, granted, doc_version_id? }`. Records `locale_shown`, IP, UA; writes `audit_log`. **Re-consent flow:** if a doc's `is_current` version advances past the user's `legal_acceptances`, gated calls return `409 reconsent_required` with the new `doc_version_id`; the client re-accepts via this endpoint + `POST /legal/acceptances`.

### `POST /me/data-export`
- **Auth:** Bearer. **Purpose:** Law 25 right of access — request a full machine-readable archive (profile, messages, activity, settings, consents, connections). **Response:** `{ request_id, status: "requested" }`; a job completes within ~15 days, `GET /me/data-export/{request_id}` returns a short-lived signed `export_url`. **Errors:** `429 export_in_progress`.

### `DELETE /me`  *(account deletion — permanent)*
- **Auth:** Bearer. **Re-auth required** (recent OTP). **Purpose:** in-app **permanent** account deletion. **Request:** `{ confirm: true, reason? }`. Creates `data_deletion_requests`, sets `accounts.deleted_at`, schedules the scrub job (PII purged; messages anonymized via null `sender_id`; `id`, `email_hash`, `phone_hash` retained ~90d for dispute + re-registration block). Writes `audit_log` (`account.delete`). Irreversible after the grace window; tokens revoked immediately. **Errors:** `409 deletion_pending`.

---

## 16. REST vs Realtime — quick map

| Surface | Transport |
|---|---|
| Catalog, browse, search, profile, join funnel, reservation, waitlist join/leave, reliability, settings, subscription, feedback, reports, Law 25 rights | **REST** |
| Group chat, group system lines, **day-of statuses & check-in fan-out** | **REST write + RT** (`group:{group_id}`) |
| Direct messages, seen receipts | **REST history + RT** (`dm:{thread_id}`) |
| **Backfill offers** (time-limited, `expires_at`), notifications, friend requests, group-match | **REST poll fallback + RT** (`user:{account_id}`) |

---

*The wire contract above is consistent with [`schema.sql`](schema.sql) (tables / columns / enums) and the demo flow functions in [`index.html`](index.html): `requestJoin` / `beginJoin` / `finishJoin` / `openReservation` / `openWaitlist` / `scheduleBackfillOffer` / `fireBackfillOffer` (~L3456–3647), `resvCode` / `wlPosition` / `usernameStatus` (~L1777–1788), `checkIn` / `seedDaySim` (~L3604–3621).*
