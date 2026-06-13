# Perch — full sweep review

A complete trace of `index.html` (every screen, button, and state transition). Items are grouped by priority. Line numbers are approximate anchors — confirm before editing.

> Note: this was a **static code trace**, not a live browser click-through (no browser-automation tool was available in this session). Every item below is grounded in the actual code, but please verify each in a running browser (`npx serve .`) before/after fixing.

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

> **Status: all 13 items fixed in commit `c72a1d4` (2026-06-12),** verified with `check-i18n` and an in-browser FR walkthrough. Scope call on the footnote below: ACTIVITIES `vibe`/`planb` (plus size/social/badge/day-time patterns) now translate at render time via `ACTFR`/`BADGE_FR`/`frWhen`; venue names stay (proper nouns). The remaining follow-up — `makeGroups` seed data (group names, vibetags, personality, compat) — was fixed in `28c568d` (2026-06-12) via the `GRPFR` table and `grpName`/`grpTags`/`grpPersonality`/`grpCompat` render-time helpers; group names translate since they're descriptive, not proper nouns.

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

## P2 — Polish / improvements

1. **`theme-color` / manifest don't follow light theme** — `applyTheme` updates the `<meta theme-color>` (good), but the PWA `manifest.json` `theme_color`/`background_color` stay dark. Minor.
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
