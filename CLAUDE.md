# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An interactive product demo for **Perch** — a small-group friend-making app. Everything is simulated: no backend, no real accounts, no payments. `docs/PLAN.md` is the product source of truth (thesis, risks, MVP cut); the demo expresses that plan, so check it before changing product behavior. (All planning/design/legal docs live in `docs/`; only `README.md` and this file sit at the repo root.)

The backend the demo *implies* is **fully designed**: `docs/BACKEND.md` (architecture & decisions), `docs/schema.sql` (validated PostgreSQL DDL — every demo invariant encoded), and `docs/API.md` (REST contract for every flow). Its **critical-path slice is now built AND wired into the app** (live when `config.js` is present, pure simulation otherwise): `supabase/migrations/0001_init.sql` (thin-slice schema + RLS + `SECURITY DEFINER` cap/join/check-in functions, one paste into Supabase), `backend/perch-api.js` (the live data layer — auth, profile, group, realtime chat, join, check-in; imports supabase-js from a CDN, **no build step**), `backend/test.html` (a smoke-test harness that proves the backend before integration), and `config.example.js` → `config.js` (gitignored Supabase keys). `docs/DEPLOY.md` is the runbook to stand it all up on free tiers. **The single-file demo stays single-file:** the live backend is *additive and optional* — when `config.js` is absent the app is the pure simulation; the integration is a guarded `<script type="module">` bridge (sets `window.Perch`/`window.PERCH_LIVE`) plus per-flow `if(window.PERCH_LIVE…)` branches (auth, profile, join, check-in, chat) that fall back to the sim — not a rewrite. The simulated Explore catalogue stays simulated by design; **Perch Thursdays is the one real, bookable group** (per `docs/PLAN.md`). `docs/BOOTSTRAP.md` is the zero-budget launch plan (the current plan: prove by hand → free-tier web app → stores later); `docs/LAUNCH.md` the full funded roadmap; `docs/LEGAL.md` the legal-placeholder map; `docs/COUNSEL_BRIEF.md` the Quebec-lawyer brief + founder decision memo; `docs/REVIEW.md` the QA log; `docs/DEPLOY.md` the deploy/backend runbook.

## Run it

No build step, no dependencies, no package manager — and keep it that way (single-file, no-build is a deliberate constraint).

```sh
npx serve .                   # Node — prints the URL, usually http://localhost:3000
# or, if Python is available:
python3 -m http.server 8000   # then open http://localhost:8000
```

Or open `index.html` directly. There are no tests or linters.

When asked to test or screenshot the app in a browser (e.g. via Playwright), start one of the servers above yourself and use its URL — don't ask the user for a URL.

## Architecture: everything lives in index.html

One file (~3.8k lines), three blocks:

- `<style>` (top): CSS custom properties define the **dark theme (default)**; a light theme overrides the same tokens under `[data-theme="light"]` (set on `<html>` by `applyTheme`). The app renders inside a fixed iPhone-proportioned frame.
- Static markup: each screen is a `<section class="screen" id="s-NAME">` (29 screens: landing, q, result, explore, groupdetail, chat, discover, settings, …).
- `<script>` (bottom), ordered: data constants (`ARCH` 12 archetypes, `QUESTIONS`, `ACTIVITIES`, `INTERESTS`, the `PEOPLE` searchable directory, `I18N`) → the single global `state` object → helpers (`$`, `$$`, `esc`, `t`) → navigation (`goTo`, `goBack`, `runEnter`) → per-screen `renderX()` functions → event wiring.

Key conventions:

- **Navigation:** `goTo("name")` activates `#s-name` and calls `runEnter(name)`, which dispatches to that screen's render function. Numbered comments (`U1`, `U2`, `U4`, `P5`…) mark navigation/UX rules — read them before touching history or back-button logic. Onboarding screens are firewalled out of the back stack once the app proper is reached (U1); bottom-nav tab switches must not push history.
- **State:** all app state is the one `state` object. Nothing persists except language (`localStorage perch_lang`); theme is in-session only by design. `resetDemo()` must keep working after any change.
- **Escaping:** any dynamic string interpolated into HTML goes through `esc()`.

## i18n — non-negotiable

Full en / fr-CA coverage, including legal docs. Every user-visible string must exist in both `I18N.en` and `I18N.fr` (plus the parallel tables `CAT_FR`, `ARFR`, `QFR`, `ACTFR`, `BADGE_FR`, `GRPFR`, `INT_FR` for data-driven content). Static markup is translated via `data-i18n` attributes (`data-i18n-html` for strings with markup, `data-i18n-ph` for placeholders); script-built strings via `t("key")`. Data constants (`ACTIVITIES`, `ARCH`, `INTERESTS`, the `makeGroups()` demo groups) stay canonical English — search and filters match on them — and are translated only at render time through helpers (`actVibe`, `actPlanb`, `actBadge`, `actSize`, `actSocial`, `frWhen`, `archBring`/`archLoves`/`archDesc`, `hostedName`/`hostedWhen`/`hostedTags`, `grpName`/`grpTags`/`grpPersonality`/`grpCompat`, `intLabel`). Adding an activity means adding its `ACTFR` entry (`name`, `vibe`, `planb` — and `BADGE_FR` if it introduces a new badge); adding a demo group means adding its `GRPFR` entry; adding an interest means adding its `INT_FR` entry. The `PEOPLE` directory (names + `@username`) is proper nouns — **not** translated; their archetype shows via `archName`/`archBadge`. Group and activity names translate (they're descriptive, not proper nouns); venue names don't. Prose that embeds canonical activity names (e.g. friends' `met` strings) goes through `frActText`. Never hardcode visible English in markup or render functions without an fr counterpart. There's a `check-i18n` skill that verifies key parity — run it after any copy change.

## Other invariants

- **Accessibility settings are functional, not cosmetic** — text size, bold, contrast, larger targets, reduced motion all apply for real; verify them after UI changes, along with both themes and both languages.
- **Free tier is enforced:** 2 hangs/week; the third join opens the Perch+ paywall. Don't break this when touching join flows. All joins funnel through `requestJoin(g,a)` → cap check → profile gate → `beginJoin` (→ `openReservation` for ticketed) → `finishJoin`. The waitlist **claim** path (`openClaimSpot`) must route through `requestJoin` too, so the cap/gate/reservation all still apply — never call `finishJoin` directly to bypass them.
- **Profile is set up on demand, not at signup** (`state.profileComplete`). `needsProfile()` gates the first join/host via `openProfileSetup(onComplete, gated)`; browsing is free. Don't move the gate earlier. `state.username` is validated by `usernameStatus()` (3–20 chars, `a-z0-9._`, checked against the `PEOPLE` directory + `RESERVED_NAMES`).
- **Reservations:** every join stores `{code, ticket, price}` on its `joinedGroups` entry (`resvCode()` makes `PCH-XXXX`); ticketed activities (those with `price`) get an `openReservation` booking step that is **pay-at-venue** (no card captured — honour the no-payments constraint). The code shows on the Joined screen and the joined group detail.
- **Waitlist + backfill:** full groups offer `openWaitlist`; entries live in `state.waitlisted` (array of `{group,activity}`). Joining the waitlist schedules an automatic offer via module-level `backfillTimers` (NOT on `state`, like `chatTimers`) — `clearBackfillTimers()` runs in `resetDemo`. The offer (`state.backfillOffer`) surfaces a tappable toast + a notification; claiming routes through `requestJoin`. `wlPosition(g)` is deterministic (never #1).
- **Reliability is attendance-based:** `isReliable() = checkedIn || attended>0` — joining alone does **not** make you reliable; `state.attended` is bumped only on check-in. `relTier()` drives the warm New → Building → 100% framing; keep it kind (no public ranking, no numeric score for others — PLAN: "not a popularity contest").
- **Verification is optional** (`state.verified`) and must never block joining/hosting. The `vbadge(on)` helper is the single source of the ✓ Verified pill (distinct from the 🛡️ Reliable pill); a seeded subset of `PEOPLE`/`MET_SEED` carry `verified:true`.
- **Day-of coordination** (`coordPanelHTML`) only renders on event day (`state.dayOf===g.id`); status lives in `state.dayStatus[gid]`, "here" routes through the shared `checkIn(g)` (don't duplicate check-in), and `seedDaySim`/`state.daySimSeeded` posts simulated peers once.
- **Legal text** uses the `LEGAL` placeholder constants (`[Legal Entity Name, Inc.]` etc.) and is flagged in-app as pending attorney review — keep the placeholders, don't invent a real entity.
- 18+ age gate: the age stepper floors at 18, and 18+ is disclosed before the quiz.
