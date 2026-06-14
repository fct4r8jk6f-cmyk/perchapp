# Perch — full sweep review

A complete trace of `index.html` (every screen, button, and state transition). Items are grouped by priority. Line numbers are approximate anchors — confirm before editing.

> Note: this was a **static code trace**, not a live browser click-through (no browser-automation tool was available in this session). Every item below is grounded in the actual code, but please verify each in a running browser (`npx serve .`) before/after fixing.
>
> **Update (2026-06-12):** a full live browser click-through (every screen, en + fr) has since been completed — the findings and fixes are in the **"Second sweep"** section below.
>
> **Update (2026-06-14):** the four feature areas (Discovery & matching, Retention & delight, Profiles & onboarding, Trust & safety depth) plus the warm-editorial de-AI redesign and deepened archetypes have since shipped — each designed via a multi-agent workflow, built in verified batches, and pushed. A fresh **7-dimension QA audit** (i18n, state/reset, invariants, escaping, feature-logic, navigation, theming/a11y) then ran with adversarial verification: **7 of 20 candidate findings confirmed, 6 fixed** (commit `765b3eb`) — `resetDemo` now resets theme/rating; the chat member name is `esc()`'d; the share-plan guardian is scoped to its event; the post-recap redirect is silent; light-theme brand tokens were darkened for contrast. *Not fixed by design:* `resetDemo` intentionally does **not** reset accessibility settings — they should persist across a restart, not be re-imposed. i18n parity holds at **723 = 723**.

---

## P0 — Functional bugs

> **Status: all four P0 items fixed in commit `f86df9d` (2026-06-12).** Kept here for the repro steps and as context for the P1/P2 lists below, which are still open.

### 1. Joined-group detail can show the WRONG activity
**Where:** `renderGroups` group click handler (~line 1982) + `renderGroupDetail` (~line 1995).
**What:** A joined group's detail screen reads `state.chosenActivity`, but the `[data-group]` click handler only sets `state.chosenGroup` — it never restores the activity you actually joined with (stored in `j.activity`).
**Repro:** Join the Trivia group → go to Explore → tap "Cooking Class" (this sets `chosenActivity` to cooking) → open the **Groups** tab → tap your joined Trivia group. The detail shows Cooking Class's venue, icon, price, and Plan B instead of Trivia's.
**Fix:** In the `[data-group]` handler, if the clicked group is in `state.joinedGroups`, set `state.chosenActivity` to that entry's `j.activity` before `goTo("groupdetail")`. (The chat path already does this correctly in `openGroupChat`.)

### 2. Unescaped user name → self-XSS in the chat check-in message
**Where:** `runChatIntro` (~line 2296). Compare to the correct version in the check-in handler (~line 2079, which uses `esc(fn)`).
**What:** `${fn} is here 👋` / `${fn} est là 👋` injects `state.name` into a system chat bubble **without `esc()`**. `msgRowHTML` inserts `m.text` as raw HTML.
**Repro:** Edit profile → set name to `<img src=x onerror=alert(1)>` → check in to a group → reopen that group's chat. The injected HTML runs.
**Fix:** Wrap `fn` in `esc()` here, matching line 2079. (CLAUDE.md: "any dynamic string interpolated into HTML goes through `esc()`.")

### 3. "This week" filter is a silent no-op
**Where:** `openFilter` apply handler (~line 3126).
**What:** Applying day = "This week" maps to `null` (same as "Any day"), so the visible "This week" chip does nothing and the filter dot never lights up.
**Fix:** Either implement it (e.g. show all non-today upcoming) or remove the option to avoid a dead control.

### 4. Hardcoded English toast where a translated key already exists
**Where:** Requests "Accept" handler (~line 2455): `showToast(\`You and ${n} are now friends\`)`.
**What:** `t("toast_friends")` (used correctly at line 2434) exists in both languages but is bypassed here.
**Fix:** Use `t("toast_friends").replace("{n}", n)`.

---

## P1 — i18n leakage (CLAUDE.md says this is non-negotiable)

> **Status: all 13 items fixed in commit `c72a1d4` (2026-06-12),** verified with `check-i18n` and an in-browser FR walkthrough. Scope call on the footnote below: ACTIVITIES `vibe`/`planb` (plus size/social/badge/day-time patterns) now translate at render time via `ACTFR`/`BADGE_FR`/`frWhen`. The remaining follow-up — `makeGroups` seed data (group names, vibetags, personality, compat) — was fixed in `28c568d` (2026-06-12) via the `GRPFR` table and `grpName`/`grpTags`/`grpPersonality`/`grpCompat` render-time helpers; group names translate since they're descriptive, not proper nouns. Activity names followed in `a3feee1` (2026-06-12) via `ACTFR.name`/`actName` (plus `frActText` for names embedded in prose like the friends' "met" strings). Venue names stay canonical (proper nouns), except prose "venues" like Perch Thursdays' "Rotating spot · revealed Monday", which translate via an `ACTFR.venue` override (`actVenue`). The footnote's scope question is now fully resolved.

The core happy path (landing → quiz → explore → join → chat → feedback) is fully bilingual. Many **secondary screens hardcode English** and show English even when the app is set to Français. Each needs `t()` keys added to both `I18N.en` and `I18N.fr` (and, for data, parallel FR tables like the existing `ARFR`).

1. **Archetype detail screen** (`renderArchetype`, ~1806–1813) — fully English: "Your type", "What you bring to a group", "Activities you tend to love", "People often describe you as…", "You vibe well with", "and", "Retake quiz"/"Take the quiz". The underlying data (`bring`, `loves`, `desc` in `ARCH`) is English-only too — needs FR equivalents (extend `ARFR`).
2. **Group chat intro messages** (`runChatIntro`, ~2287–2293) — the scripted conversation ("Hey everyone! So glad this came together", "I'll grab a table near the back…", the private-chat system notice) is English-only. Very visible in FR.
3. **Host confirmation screen** (markup ~866–871) — "You're on 🎉", the two body lines, "Back to Explore" have no `data-i18n`.
4. **Mood check screen** (markup ~1039–1043) — "How are you feeling about tonight?", "Ready", "A bit nervous", "Not feeling it"; plus its toasts (~3195–3196): "See you there 🌿", "Totally normal — the group will be glad you came."
5. **Explore activity cards** (`actCardHTML`, ~1831–1832) — "Plan B if needed ·" and "View groups →".
6. **Friends / Met tabs** (`_populateFriends`, ~2411–2420) — "Your people are out there", "47 people in your area…", "See people you've met", "No one new right now", "People from your events", the "Friends" badge, and "Met at {x}".
7. **Requests screen** (`renderRequests`, ~2446–2451) — "No requests right now", "Accept", "Decline", "Request sent", "Cancel", "No pending sent requests", etc.
8. **Friend profile** (`renderFriendProfile`, ~2480–2483) — "Where you met", "A bit about {name}", the bio sentence, "Add {name} as a friend…", "Message", "Add friend".
9. **DM thread** (`renderDM`, ~2495–2501) — "Friends · private", "Seen", and the seeded "Hey! Good meeting you 😊".
10. **Chat safety sheet** (`openChatSafety`, ~3137–3146) — "Safety options", "Report a problem", "Leave this group", "Community guidelines", "Wellbeing resources", "Report a member", "Cancel".
11. **Blocked-accounts sheet** (`openBlockedList`, ~3063–3067) — "Blocked accounts", "No one blocked.", "Unblock", "Close".
12. **Pinned chat detail** (~2273) — "Plan B ·".
13. **Stray English toasts/labels:** "Photo updated" (~3203), "Unblocked" (~3069), "Report received — thank you" (~3149), and the hosted-group name `Your ${cat} hang` + `${size} people` vibetags (~2147–2148).

*(Scope decision for you/Claude: the activity `vibe`/`planb`/`venue` text in `ACTIVITIES` is also English-only. Venue names are proper nouns — fine — but `vibe` lines like "Low-key, great for first timers" arguably should translate. Decide whether that's in scope.)*

---

## Second sweep — live browser QA (2026-06-12)

> **Status: all items below fixed in commit `43b4a0e` (2026-06-12).** Found via a full live click-through of every screen in both languages — the in-browser walkthrough the top note asked for — cross-checked with a source-level i18n audit. Re-verified in-browser after fixing; `check-i18n` clean (key parity 506 = 506, 0 unresolved `t()` refs). These are **13 distinct fr-CA leaks beyond the original P1 batch**, plus two layout bugs.

### i18n leaks (13 strings) — English shown under `state.lang==="fr"`
Each was a hardcoded literal bypassing `t()`; the fix adds a key to both `I18N.en`/`I18N.fr` (12 new keys) and routes the call through `t()`.

1. **Notification timestamps** (`renderNotifs`, ~2947/2952/2962) — "2h ago", "2d", "3d" were raw literals while sibling timestamps already used `t()`. Now `notif_2hago` / `notif_2day` / `notif_3day` → "il y a 2 h" / "2 j" / "3 j".
2. **Perch+ paywall table** (`openPerchPlus`, ~2778/2791) — the "Free" column header and the "2 / wk" / "5 / wk" quota cells. Now `pp_free` → "Gratuit" and `pp_quota_free` / `pp_quota_plus` → "2 / sem." / "5 / sem." ("Perch+" stays — brand).
3. **Friend profile "where you met"** (`renderFriendProfile`, ~2624) — interpolated `p.met` raw, so activity names rendered in English ("Trivia Night…") even though the identical string translated on the Friends / Met / Requests lists. Now `frActText(p.met)`, matching the other renderers (the already-documented convention for prose with embedded activity names).
4. **Iris seed met-string** (~1634) — "Coffee Meetup · Café Pages" had no `ACTIVITIES` match, so `frActText` couldn't translate it in *any* renderer. Changed to "Book Club · Café Pages" — a real activity with an `ACTFR` entry (→ "Club de lecture") — which also fixes a latent venue mismatch, since Café Pages is Book Club's own venue.
5. **Sign-in toast** (~1828) — `showToast("Signed in with Apple" / "Signed in")` hardcoded both branches. Now `toast_signed_apple` / `toast_signed`.
6. **Settings footer** (`renderSettings`, ~2863) — "Made with care". Now `set_madewith` → "Fait avec soin".
7. **Arrival-dot tooltip** (`renderGroupDetail`, ~2147) — `title="arrived"` (the adjacent visible label already used `t("gd_here_tag")`). Now `t("gd_arrived")` → "sur place".
8. **DM-inbox presence tooltip** (`enterChats`, ~2394) — `title="online"`. Now `t("dm_online")` → "en ligne".
9. **Swipe-reply placeholder** (`wireReactTargets`, ~2483) — `inp.placeholder = "Reply to " + who + "…"` (the reset path already used `t("chat_say")`). Now `t("chat_replyto").replace("{who}", who)` → "Répondre à …".

### Layout (2)
10. **"Join this group" floated mid-screen** (`.cta-bar`, CSS ~631) — `position:sticky;bottom:88px` on content much taller than the viewport pins the bar at a fixed offset that lands mid-content, and the screen's `pad-nav` 96px bottom padding double-counted the nav clearance. Dropped sticky positioning; the CTA now sits in normal flow at the content bottom, just above the nav (the joined-view "Open group chat" / check-in CTAs share the bar and behave the same).
11. **Map preview collapsed to a 20px strip** (`.map-stub`, CSS ~212) — declared `height:120px` but, as a flex item in the `overflow-y:auto` `.screen` column with default `flex-shrink:1`, it was squeezed to its one text line. Added `flex-shrink:0` → restores the 120px box.

All re-verified in-browser (en + fr): no console errors; `resetDemo`, the 18+ age-stepper floor, and the 3rd-join Perch+ paywall still hold; light/dark themes and the accessibility toggles unaffected.

---

## P2 — Polish / improvements

1. **`theme-color` / manifest don't follow light theme** — `applyTheme` updates the `<meta theme-color>` (good); the PWA `manifest.json` `theme_color`/`background_color` stay dark. **Resolved as intentional (2026-06-13):** the app boots to the dark default and a manifest carries a single theme color, so dark is the correct install/splash chrome. The manifest was instead polished for store readiness (`id`/`lang`/`dir`/`categories`/`scope`, a vector `icon.svg`), and a real branded SVG icon replaced the emoji-data-URI favicon. See `LAUNCH.md` (do-now items) and `LEGAL.md`.
2. **"Today" filter == Thursday-only** (`renderExplore`, ~1884) — labeled "Today" but matches `when` starting with "Thu". Confusing if read literally; fine if intentional (Perch Thursdays). Consider relabeling.
3. **`state.dayOf` / `state.checkedIn` are global, not per-group** — checking into one group makes the profile "Show-up" stat 100% globally and the day-of state can bleed across groups. Acceptable for a demo; note it.
4. **"Picked for you" matching is fragile** (`renderExplore`, ~1865) — matches activity vs archetype `loves` by first word only. Works for current data but breaks silently if names change.
5. **Default theme is `"dark"`, not `"system"`** (`state.theme`, ~1475) — the appearance sheet offers System/Light/Dark but the app boots to Dark regardless of OS. Confirm this is intended.

---

## What's solid (don't break)

- Escaping of user input in profile name/bio/interests, chat & DM messages, venue note (all via `esc()`), except bug #2 above.
- Free-tier enforcement (2 hangs/week → paywall), Perch+ trial/cancel, ticket pricing end-to-end.
- Accessibility toggles (text size, bold, contrast, larger targets, reduced motion) are genuinely functional.
- Back-button / history firewall (U1/U2/U4 rules), legal-gate sequencing, full FR coverage on the core path and all legal docs.

---

## Feature build (2026-06-13) — profile/username, reservations, reliability, verification, day-of, backfill

Two batches of work landed on top of the sweeps above. All verified in-browser (en + fr, dark + light) with no console errors; `check-i18n` clean (key parity 624 = 624, no duplicate keys, 0 unresolved `t()` refs).

**Batch 1 — user-requested core additions:**
1. **Profile setup, deferred or upfront** — `openProfileSetup(onComplete, gated)` (emoji, display name, `@username` with live availability, bio, interests). Not forced at signup: `needsProfile()` gates the *first* join/host (`requestJoin` / `doHost`); you can also set it up early via the Explore nudge or the Profile card. `state.profileComplete`/`state.username`; reset-covered.
2. **Username + Discover** — new `s-discover` screen (🔎 in the Friends header), searches the `PEOPLE` directory by name or `@username`, sorts by mutual friends, and sends friend requests (Requested → Sent). Editable username/interests in Edit Profile too.
3. **Reservations** — every join stores `{code, ticket, price}`; ticketed activities get an `openReservation` booking step (pay-at-venue, no card). Confirmation code on the Joined screen *and* the joined group detail.
4. **Waitlist** — full groups offer `openWaitlist`; `state.waitlisted` renders a section in Groups and a status block in detail.

**Batch 2 — the 4 proposed features (designed + reviewed via multi-agent workflows):**
5. **Reliability-aware matching** — `isReliable()` (attendance-based: `checkedIn || attended>0`, *not* mere joining), warm `relTier()` (New → Building → 100%) on the profile Show-up stat with a tap-through `openReliability` explainer; waitlist queue position (`wlPosition`, reliable members ranked higher); a system-level "reliability-aware matching" line on group detail.
6. **Verification** — `openVerify` (phone → code → `state.verified`); wired the previously-dead `#setVerify` Settings row; reusable `vbadge()` ✓ pill on own profile, friend profiles, and the directory; seeded `verified:true` subset; optional dismissible profile prompt. Strictly optional — never blocks join/host.
7. **Day-of coordination** — `coordPanelHTML` (on-my-way / running late / here / split-a-ride) shown only on event day; `state.dayStatus[gid]` persists the chosen status (dedup on re-tap), "here" routes through the shared `checkIn(g)`, and `seedDaySim` posts two simulated peers once. Status pills use `pill-mint`/`pill-amber` (theme-safe).
8. **Waitlist auto-backfill** — joining a waitlist schedules (module-level `backfillTimers`) an offer ~6s later: tappable toast + a `wlclaim` notification; claiming routes through `requestJoin` (cap + gate + reservation all preserved). Leaving a full group shows the "freed a spot" toast.

**Bugs fixed during the build/review:**
- `openClaimSpot` no longer eagerly drops the waitlist entry (a paywalled claim would have stranded the user); `finishJoin` clears it only on a real join.
- `#setVerify` Settings row was a dead control (no handler) — now wired.
- Adversarial review (8 read-only reviewers) caught & fixed: unescaped `grpName`/name interpolation in `openClaimSpot`/`openMuteOptions`/`renderNotifs` (now `esc()`'d); `coordStatusHTML` hardcoded rgba pills → themed `pill-mint`/`pill-amber`; an orphaned backfill-expiry timer when leaving the waitlist (now cleared); and the over-broad "everyone here has a strong show-up record" copy → softened to a system-level statement.

**P2 items from above, now addressed:** #3 (the Show-up stat is no longer a blunt global "100%/—" — it's the warm reliability tier, attendance-gated). #1/#2/#4/#5 remain as previously noted (intentional or minor).

**Process note:** the design-phase workflow agents, despite a "spec only" instruction, *implemented* a partial first pass directly into `index.html`; the review-phase workflow used read-only `Explore` agents to prevent that. Lesson for future workflows here: pass `agentType: 'Explore'` for any read-only/review fan-out.
