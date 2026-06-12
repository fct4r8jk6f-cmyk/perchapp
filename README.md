# Perch 🪶

Small groups of adults meeting around real activities — the low-pressure way to make friends. This repo contains the **interactive v1 product demo**: a single-file, no-build prototype of the full app flow, framed in an iPhone mock with a clickable flow map.

**The product plan — thesis, risks, metrics, MVP cut — lives in [PLAN.md](PLAN.md).**

## Run it

No build step, no dependencies:

```sh
# any static server works
python3 -m http.server 8000
# then open http://localhost:8000
```

Or just open `index.html` in a browser. It also installs as a PWA (manifest + icons included).

## What's in the demo

- Onboarding: landing → 7-question social-type quiz → 12 archetypes → age gate (18+) → sign-in → terms, with a separate returning-user path
- Core loop: Perch Thursdays (the pinned weekly guaranteed group) + Explore catalogue with working day/size filters → join a matched group → pre-event chat with scripted replies → day-of check-in → post-event reflection → friends & DMs
- Monetization: enforced free tier (2 hangs/week), Perch+ paywall with trial terms and manage/cancel in Settings, per-event ticket pricing on premium activities
- Supporting: hosting (with detail view and cancel), tappable notifications with per-thread unread, settings, safety flows (report / block / take a break), invite with a real QR code
- Quality: full en / fr-CA coverage including legal docs, dark (default) & light themes, keyboard navigation with functional accessibility settings (text size, bold, contrast, larger targets, reduced motion)

## Files

| File | Purpose |
|---|---|
| `index.html` | The entire demo — styles, markup, data, and logic |
| `manifest.json`, `icon-*.png` | PWA install support |
| `PLAN.md` | Product plan and strategy |

Everything in the demo is simulated — no backend, no real accounts. Legal text is a template pending attorney review.
