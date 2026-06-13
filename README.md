# Perch 🪶

Small groups of adults meeting around real activities — the low-pressure way to make friends. This repo contains the **interactive v1 product demo**: a single-file, no-build prototype of the full app flow, framed in an iPhone mock with a clickable flow map.

**The product plan — thesis, risks, metrics, MVP cut — lives in [PLAN.md](PLAN.md).** The path from this demo to a Montreal launch (phased, with the legal/backend/store blockers) is in [LAUNCH.md](LAUNCH.md).

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
- Profile: optional profile setup (name, **@username**, bio, emoji, interests) that is *not* forced at signup — you can browse first and it's only required the moment you join or host (or set it up early via the Explore nudge / Profile card)
- Core loop: Perch Thursdays (the pinned weekly guaranteed group) + Explore catalogue with working day/size filters → join a matched group → **reserve your spot** (booking step + confirmation code; ticketed events are pay-at-venue) → pre-event chat with scripted replies → **day-of coordination panel** (on-my-way / running late / here / split-a-ride) → post-event reflection → friends & DMs
- People: **find & add other members by name or @username** (Discover), friend requests (received/sent), and a **verified-identity** badge (simulated phone check) shown across profiles and the directory
- Reliability & waitlists: a warm **show-up reputation** (New → Building → 100%) surfaced on the profile with an explainer; full groups offer a **waitlist** with your queue position, and an **automatic backfill** offer (notification + claim) when a spot frees — claims still respect the free-tier cap and reservation flow
- Monetization: enforced free tier (2 hangs/week), Perch+ paywall with trial terms and manage/cancel in Settings, per-event ticket pricing on premium activities
- Supporting: hosting (with detail view and cancel), tappable notifications with per-thread unread, settings, safety flows (report / block / take a break), invite with a real QR code
- Quality: full en / fr-CA coverage including legal docs, dark (default) & light themes, keyboard navigation with functional accessibility settings (text size, bold, contrast, larger targets, reduced motion)

## Files

| File | Purpose |
|---|---|
| `index.html` | The entire demo — styles, markup, data, and logic |
| `manifest.json`, `icon.svg`, `icon-*.png` | PWA install support |
| `PLAN.md` | Product plan and strategy |
| `LAUNCH.md` | Phased launch-readiness roadmap (demo → App Store) |
| `BACKEND.md` | Backend architecture & decisions (the server the demo implies) |
| `schema.sql` | PostgreSQL schema — validated DDL for that backend |
| `API.md` | REST API contract (every demo flow as an endpoint) |
| `LEGAL.md` | Legal-text inventory + placeholder map for counsel |
| `COUNSEL_BRIEF.md` | Brief for a Quebec privacy lawyer + founder decision memo |
| `REVIEW.md` | Demo QA log (full-sweep code trace + live click-through) |

Everything in the demo is simulated — no backend, no real accounts. The backend it *implies* is **designed but not built** — see [BACKEND.md](BACKEND.md) (architecture), [schema.sql](schema.sql) (Postgres DDL), and [API.md](API.md) (REST contract). Legal text is a template pending attorney review (mapped in [LEGAL.md](LEGAL.md)).
