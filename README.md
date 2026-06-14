# Perch 🪶

Small groups of adults meeting around real activities — the low-pressure way to make friends. This repo is the **interactive v1 product demo**: a single-file, no-build prototype of the whole app, shown in an iPhone mock with a clickable flow map. Everything is simulated (no backend, no real accounts, no payments), fully bilingual **en / fr-CA**, with **dark + light** themes and working accessibility settings.

## Run it

No build step, no dependencies:

```sh
# any static server works
python3 -m http.server 8000      # then open http://localhost:8000
# or:  npx serve .
```

Or just open `index.html` in a browser. It also installs as a PWA (manifest + icons included).

## What's in the demo

**Onboarding & profile**
- Landing → 7-question social-type quiz → **12 in-depth archetypes** → 18+ age gate → sign-in → terms (with a separate returning-user path)
- Profile set up **on demand** (name, **@username**, bio, emoji, interests) — browse first; only required the moment you join or host
- **Pick-a-prompt bios**, an "In a group, I'm…" trait line, and a gentle profile-depth nudge

**Discovery & matching**
- Perch Thursdays (the pinned weekly guaranteed group) + an Explore catalogue with day / size / **vibe** filters
- A real **fit engine** — groups are **ranked by your fit**, each card shows a fit pill, and group detail explains **"why this group"** in plain language (shared archetype *and* interests), with a stylized neighbourhood map
- Your **interests feed the matching** ("You both love…")

**The hang**
- Join → **reserve your spot** (confirmation code; ticketed events are pay-at-venue) → pre-event chat → **day-of coordination** (on-my-way / late / here / split-a-ride) → **post-hang recap** → friends & DMs

**Retention & delight**
- Per-hang memory → **"Your Perch story,"** a private **show-up streak + milestones**, a "come back this week" nudge, and one-tap re-join

**Trust & safety**
- **Tracked reports** (reference + 24h receipt + outcome) in a private **"Your boundaries"** hub; working **mute** and **block**; **report straight from a chat message**; severity-aware urgent reports
- **In-person safety**: share tonight's plan with a trusted contact, a "made it home safe" loop, and a discreet silent help action
- Optional verified-identity badge (never blocks joining/hosting); warm **reliability** framing — New → Building → 100%, never a public ranking

**Plus:** enforced free tier (2 hangs/week) + Perch+ paywall, waitlists with automatic backfill, hosting, tappable notifications, invite QR.

## Project layout

| Path | Purpose |
|---|---|
| `index.html` | The entire demo — styles, markup, data, and logic (~4.3k lines) |
| `manifest.json`, `icon.svg`, `icon-*.png` | PWA install support |
| `supabase/` | The real backend, ready to run — `migrations/0001_init.sql` (thin-slice schema + RLS + cap/join/check-in functions, one paste into Supabase) |
| `backend/` | `perch-api.js` (live data layer, no build step) + `test.html` (a smoke-test page that proves the backend before it's wired into the app) |
| `config.example.js` | Template for your Supabase URL + anon key → copy to `config.js` |
| `CLAUDE.md` | Guide for working in this repo with Claude Code |
| `docs/` | Product, launch, backend-design, and legal docs (below) |

### `docs/`

| File | Purpose |
|---|---|
| [`docs/PLAN.md`](docs/PLAN.md) | Product plan & strategy — thesis, risks, MVP cut |
| [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md) | **Zero-budget launch plan** (the current path: prove by hand → free web app → stores) |
| [`docs/LAUNCH.md`](docs/LAUNCH.md) | Funded, hire-a-team launch roadmap (the destination once resourced) |
| [`docs/DEPLOY.md`](docs/DEPLOY.md) | **Deploy & backend runbook** — stand up the real backend (Supabase) + host the site, step by step |
| [`docs/BACKEND.md`](docs/BACKEND.md) | Backend architecture & decisions (full design) |
| [`docs/schema.sql`](docs/schema.sql) | Validated PostgreSQL schema for that backend (the `supabase/` migration is its first slice) |
| [`docs/API.md`](docs/API.md) | REST API contract for every demo flow |
| [`docs/LEGAL.md`](docs/LEGAL.md) | Legal-text inventory + placeholder map for counsel |
| [`docs/COUNSEL_BRIEF.md`](docs/COUNSEL_BRIEF.md) | Quebec privacy-lawyer brief + founder decision memo |
| [`docs/REVIEW.md`](docs/REVIEW.md) | QA log (code audit + live verification) |

The demo itself is simulated. The backend it implies is **fully designed** ([`docs/BACKEND.md`](docs/BACKEND.md), [`docs/schema.sql`](docs/schema.sql), [`docs/API.md`](docs/API.md)) and its **critical path is now built and runnable** — the `supabase/` migration + `backend/` data layer turn *sign in → book this Thursday → chat → check in* into real, server-authoritative Postgres. To stand it up: **[`docs/DEPLOY.md`](docs/DEPLOY.md)** (≈10 min, free tier). Legal text is a template pending attorney review (mapped in [`docs/LEGAL.md`](docs/LEGAL.md)). **No budget? Start with [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md).**
