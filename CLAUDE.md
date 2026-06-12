# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An interactive product demo for **Perch** — a small-group friend-making app. Everything is simulated: no backend, no real accounts, no payments. `PLAN.md` is the product source of truth (thesis, risks, MVP cut); the demo expresses that plan, so check it before changing product behavior.

## Run it

No build step, no dependencies, no package manager — and keep it that way (single-file, no-build is a deliberate constraint).

```sh
python3 -m http.server 8000   # then open http://localhost:8000
```

Or open `index.html` directly. There are no tests or linters.

## Architecture: everything lives in index.html

One file (~3.2k lines), three blocks:

- `<style>` (top): CSS custom properties define the **dark theme (default)**; a light theme overrides the same tokens under `body.light`. The app renders inside a fixed iPhone-proportioned frame.
- Static markup: each screen is a `<section class="screen" id="s-NAME">` (28 screens: landing, q, result, explore, groupdetail, chat, settings, …).
- `<script>` (bottom), ordered: data constants (`ARCH` 12 archetypes, `QUESTIONS`, `ACTIVITIES`, `I18N`) → the single global `state` object → helpers (`$`, `$$`, `esc`, `t`) → navigation (`goTo`, `goBack`, `runEnter`) → per-screen `renderX()` functions → event wiring.

Key conventions:

- **Navigation:** `goTo("name")` activates `#s-name` and calls `runEnter(name)`, which dispatches to that screen's render function. Numbered comments (`U1`, `U2`, `U4`, `P5`…) mark navigation/UX rules — read them before touching history or back-button logic. Onboarding screens are firewalled out of the back stack once the app proper is reached (U1); bottom-nav tab switches must not push history.
- **State:** all app state is the one `state` object. Nothing persists except language (`localStorage perch_lang`); theme is in-session only by design. `resetDemo()` must keep working after any change.
- **Escaping:** any dynamic string interpolated into HTML goes through `esc()`.

## i18n — non-negotiable

Full en / fr-CA coverage, including legal docs. Every user-visible string must exist in both `I18N.en` and `I18N.fr` (plus the parallel tables `CAT_FR`, `ARFR`, `QFR` for data-driven content). Static markup is translated via `data-i18n` attributes; script-built strings via `t("key")`. Never hardcode visible English in markup or render functions without an fr counterpart.

## Other invariants

- **Accessibility settings are functional, not cosmetic** — text size, bold, contrast, larger targets, reduced motion all apply for real; verify them after UI changes, along with both themes and both languages.
- **Free tier is enforced:** 2 hangs/week; the third join opens the Perch+ paywall. Don't break this when touching join flows.
- **Legal text** uses the `LEGAL` placeholder constants (`[Legal Entity Name, Inc.]` etc.) and is flagged in-app as pending attorney review — keep the placeholders, don't invent a real entity.
- 18+ age gate: the age stepper floors at 18, and 18+ is disclosed before the quiz.
