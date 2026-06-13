# Perch — Launch Readiness Roadmap

*The path from this interactive demo to a Montreal soft launch on the App Store / Play Store. Companion to [PLAN.md](PLAN.md) (product strategy) and [REVIEW.md](REVIEW.md) (demo QA log).*

> ⚠️ **Not legal, tax, or financial advice.** The legal / privacy / compliance items below are framed as **questions to bring to a qualified Quebec privacy & tech lawyer** — they are starting points, not authoritative requirements. Verify Law 25, PIPEDA, age-verification, app-store, and payment/tax specifics with counsel before relying on anything here.
>
> **Planning estimates, not commitments.** Effort sizes, dollar figures, timelines, and vendor picks are first-pass estimates to enable sequencing and decisions — validate against real quotes and your team's reality. The 8-week timeline is aggressive and assumes everything below breaks your way.

---

## TL;DR

**The single biggest gate to a Montreal launch is legal + identity-verification clarity.** Until a Quebec privacy lawyer confirms whether SMS + age self-attestation is sufficient (or if proof-of-age ID verification is mandatory), you can't finalize the onboarding flow, can't be confident of App Store review, and shouldn't ship. Almost everything else can proceed in parallel.

**Critical path to soft launch (50–200 users, ~4–8 weeks of focused work):**

1. **Week 1:** Retain a Quebec privacy lawyer; get answers to 3 existential questions (age-verification requirement, Law 25 consent ordering, data residency).
2. **Weeks 2–4:** Backend (auth, matching, moderation queue); identity-verification vendor integration; legal templates drafted + reviewed.
3. **Weeks 4–6:** iOS + Android testable (Capacitor), payment processor onboarding started, moderation plan in place.
4. **Weeks 6–8:** App Store / Play Store submission + approval; soft-launch invites (50–200); run the first Perch Thursdays batch match.

**You will *not* have at launch:** per-event card payments, photo uploads, ML matching, or full venue partnerships. All are post-MVP (weeks 8–16). Perch Thursdays is the wedge, and low-density matching can be **ops-assisted** (a human reviews the batch) at first.

---

## Do Now (this week — repo polish & setup)

Small items (< ~4 hours each) that unblock decisions and build momentum.

### Code / UX (in this repo)
- [ ] **Manifest colors follow theme** — `manifest.json` `theme_color` / `background_color` are dark-only; the runtime already flips `<meta theme-color>`, but the install splash stays dark. (Known gap from REVIEW.md P2 #1.)
- [ ] **Accessibility/store audit** — Lighthouse + Axe pass; confirm icon-button `aria-label`s, focus rings, contrast → WCAG 2.1 AA (the in-app a11y toggles are already functional).
- [ ] **Real app icons** — turn the 🪶 wordmark into a vector glyph; export 1024/512/192/384 + Android adaptive (with safe zone). (Today: emoji favicon + 2 PNGs.)
- [ ] **Account-deletion guarantee** — the Settings → Delete account flow exists; spec the real SLA (confirm + grace period before hard-delete). Apple/Google both *require* in-app account deletion.
- [ ] **`check-i18n`** after any copy/placeholder change (parity is currently 624 = 624).

### Legal / entity
- [ ] **Incorporate** (Quebec Inc. or federal). Needed for bank, payment processors, contracts. (~$500–2k.)
- [ ] **Book the lawyer consult** (~1–2 h, ~$250–500) with the 3 critical questions ready.
- [ ] **Inventory the legal placeholders** — every `[Legal Entity Name, Inc.]`, `[yourdomain]`, `[Effective date]` in `index.html`; stub a `LEGAL.md` structure for Terms / Privacy / Guidelines.

### Vendor shortlist (create test accounts)
- [ ] **SMS:** Twilio Verify (recommended — Canada coverage, built-in rate limiting) vs. Telnyx (cheaper/SMS).
- [ ] **Payments:** Stripe (recommended — Connect for venue payouts) vs. Square.
- [ ] **Push/email:** Firebase Cloud Messaging (free; APNs+FCM) + SendGrid/Postmark (transactional email).

### Decisions to make (see "Founder Decisions" below)
- [ ] **PWA vs. Capacitor vs. native** → **Capacitor recommended** (the demo is already a web app; wrap it, ship iOS+Android from one codebase).
- [ ] **Who builds mobile** (you / contractors / co-founder) and **who moderates** (you first, contractor by ~week 4).

---

## Phased Plan

### Phase 0 — Foundations & Legal (Weeks 1–2, parallel)
**Goal:** legal clarity, entity, vendor + stack decisions.

| Task | Where | Effort | Exit criteria |
|---|---|---|---|
| Quebec privacy lawyer brief (1–2 h) | legal | S | Written advice on: (1) minimum viable age verification, (2) Law 25 consent ordering for the pre-signin quiz, (3) data residency |
| Incorporate entity | legal/ops | M | Bank account, tax IDs, articles filed |
| Terms/Privacy/Guidelines skeleton (placeholders → structure) | in-repo | S | `LEGAL.md`; every placeholder mapped |
| Lock the mobile stack (Capacitor vs. native vs. PWA) | infra | S | Stack chosen; iOS+Android owners committed |
| Retain lawyer for templates (ongoing) | legal | S | Retainer signed; templates session booked |

**Exit:** lawyer's written advice in hand; entity formed; stack + team locked.

### Phase 1 — MVP backend & core flows (Weeks 2–5, parallel)
**Goal:** auth, identity verification, (ops-assisted) matching, moderation queue, core APIs on staging.

> **The backend is already designed in-repo** — [BACKEND.md](BACKEND.md) (stack + decisions), [schema.sql](schema.sql) (validated PostgreSQL DDL: 41 tables, 24 enums, every demo invariant encoded — weekly cap, single join funnel, attendance-based reliability, pay-at-venue, Law 25 surface), and [API.md](API.md) (the REST contract for every flow below). Phase 1 is **implementing** these, not designing from scratch.

Key tasks (where · effort): PostgreSQL schema — *backend · S*; phone sign-in + SMS code (Twilio Verify) — *backend · M*; Apple/Google OAuth — *backend · M*; **weekly batch-matching engine** (greedy: filter by neighbourhood → sort by reliability → form balanced 4–6 groups → assign to Perch Thursdays; ops reviews output Friday AM) — *backend · M*; REST API (groups/join/reserve/leave/waitlist, with the free-tier cap enforced server-side) — *backend · M*; realtime chat (Firestore at MVP) — *backend · M*; admin panel (group review + reports queue + user actions) — *backend · L*; 24h moderation queue — *backend · M*; account lifecycle (delete / pause / block, PIPEDA-aware) — *backend · L*; deploy to staging — *infra · L*; OpenAPI contract for mobile — *backend · S*.

**Exit:** a test user can sign up → verify phone → quiz → browse groups → join → chat, on staging. API contract published.

### Phase 1b — Legal templates (Weeks 2–4, sequential with Phase 1)
Attorney-drafted **Terms** (IRL liability framing, age gate, refunds), **Privacy** (PIPEDA + Law 25: consent, retention, access/deletion rights, residency), **Community Guidelines** (moderation rules, 24h SLA, appeals), and **DPAs** for each US vendor (Twilio/Stripe/Firebase/SendGrid). Then replace the `LEGAL` placeholders in `index.html` and prep the **App Privacy / Data Safety** forms + age rating.

**Exit:** all docs lawyer-signed; placeholders replaced; store metadata templates ready.

### Phase 2 — Payments, notifications, mobile integration (Weeks 4–6)
**Goal:** Perch+ status + feature flags wired (real billing can lag to Phase 3); push/email/SMS live; iOS+Android boot and sign in.

Highlights: subscription billing decision (**Apple IAP / Google Play Billing are mandatory for in-app digital subscriptions** — you cannot route Perch+ through Stripe inside the app) — *backend/mobile · M/L*; Perch+ status API + the 2-vs-5 join cap — *backend · L*; FCM push + transactional email + real SMS — *backend · L*; backfill-offer + event-reminder delivery (respect the low-screen-time ethos — don't over-notify) — *backend · M*; CASL-compliant email/SMS consent + unsubscribe — *backend · S*; Capacitor scaffolding + IAP/Billing SDKs + client auth — *mobile · L*; bilingual notification copy — *content · S*.

**Exit:** Perch+ works (pay-at-venue mode, no card capture yet); notifications tested in staging; apps sign in on simulators.

### Phase 3 — Store readiness & submission (Weeks 6–8)
Finalize icons + bilingual store listings (5–8 screenshots, copy, keywords, en + fr-CA); **Apple Privacy Nutrition Label + Google Data Safety form**; TestFlight + Play Internal Testing builds; QA the core flows; fix the usual rejections (privacy label, age-gate clarity, **account-deletion requirement**); submit; budget 2–14 days + 1–2 rejection rounds. In parallel: train the moderator on the Guidelines + admin panel; pre-sign 2–3 venues for Perch Thursdays.

**Exit:** both apps approved + live; invite system ready; first Perch Thursdays batch scheduled.

### Phase 4 — Soft launch & iteration (Weeks 8–12)
Run the first ops-assisted Thursday match; watch the metrics that matter (from PLAN.md), do user calls, fix top bugs, tune moderation triage, then decide: scale invites or iterate.

**Validate before public launch:** show-up ≥ 85% · repeat-join ≥ 50% · NPS ≥ 40 · moderation-SLA ≥ 95% · flaking ≤ 15%.

---

## Build vs. Buy (recommended vendors)

| Area | MVP pick | Rough cost | Notes |
|---|---|---|---|
| SMS / phone verify | **Twilio Verify** | $25–50/mo + ~$0.01/SMS | Strong Canada coverage, rate-limiting built in. Alt: Telnyx. |
| Email (transactional) | **SendGrid / Postmark** | $0 → $15–50/mo | CASL-compliant unsubscribe, good deliverability. |
| Push notifications | **Firebase Cloud Messaging** | Free | Unified APNs + FCM. Alt: OneSignal. |
| Realtime chat | **Firestore** | Free tier ample at MVP | Managed, low ops. Alt: WebSocket + Redis (~$40/mo). |
| Payments (ticketing/venues) | **Stripe (+ Connect)** | 2.9% + $0.30/txn | Venue payouts/splits; handles QST/GST. Alt: Square. |
| In-app subscriptions | **Apple IAP + Google Play Billing** | ~15% (small-biz, first US$1M/yr) → 30% | Mandatory for in-app digital subs — not optional. |
| Hosting | **Railway / DigitalOcean** | $30–50/mo | DigitalOcean has Canadian regions if Law 25 needs residency. |
| Moderation tooling | Slack + sheet → **Zendesk** later | $0 → $50–200/mo | Fine to start lightweight at < ~100 MAU. |
| Monitoring | **Sentry + Plausible** | ~$50/mo | Crash + privacy-friendly analytics. |
| Legal | **Quebec privacy/tech boutique** | $2–5k + ~$1–2k/mo | Non-negotiable; PIPEDA + Law 25 + social-app experience. |

---

## Founder Decisions & Legal Questions

### Decide this week (blocks everything)
1. **Minimum viable age verification** — is 18+ self-attestation enough, or is SMS / government-ID proof required? *(Consequence: ID proof forces the quiz behind signup, hurting the viral loop.)*
2. **Quiz-before-consent ordering** — does collecting the 7-question quiz (+ a few demographics) *before* signup/consent violate Law 25's "consent before collection"? Options: re-run post-signup, treat as implicit via ToS, or require signup first.
3. **Mobile stack** — Capacitor (recommended) vs. native vs. PWA-only.
4. **Who builds mobile** — solo isn't realistic alongside backend; 2 contractors or a co-founder.
5. **Moderation staffing** — you (weeks 1–4) → part-time bilingual contractor by week 4. The 24h SLA is a real commitment.
6. **Payment flow** — pay-at-venue (current; no PCI, lower friction) vs. upfront charge (anti-flake; adds PCI + processor work, defer to ~week 8–10).
7. **Data residency** — US cloud (faster/cheaper) vs. Canada-only (if Law 25 requires).

### Questions for the Quebec privacy/tech lawyer
*Identity & age:* (1) Is SMS + age self-attestation sufficient for an 18+ social app, or is ID proof required? (2) Do Apple/Google require proof-of-age beyond self-attestation here? (3) Can we exclude unverified users from groups?
*Consent & data:* (4) Does the pre-signin quiz violate Law 25 "consent before collection"? (5) Is the quiz "personal information" under PIPEDA? (6) Can we collect a phone number for verification before opt-in?
*Residency & processing:* (7) Must user data live on Canadian servers, or is encrypted US cloud OK? (8) Do US vendors (Stripe/Firebase/Twilio) each need a DPA?
*Moderation & liability:* (9) Liability exposure between a report and the 24h decision? (10) Liability for harm at an in-person meetup — does a ToS waiver suffice, or is host screening needed?
*Compliance:* (11) Minimum retention policy (chat logs / deleted accounts / reports)? (12) Breach + deletion SLAs and whether an incident-response plan is required pre-launch? (13) Must we appoint a Privacy Officer pre-launch?
*MVP scope:* (14) The minimum viable verification to launch day 1? (15) Can we launch with no card capture (pay-at-venue) to avoid PCI until month 2? (16) Can Terms disclaim IRL liability, or must we screen hosts?

**Ask the lawyer to deliver:** written answers to the identity/consent questions, plus draft Privacy Policy, Terms, Community Guidelines, and vendor DPAs.

---

## Timeline & Team (honest)

```
Wk1     Wk2      Wk3      Wk4      Wk5      Wk6      Wk7      Wk8      Wk9–12
Phase0 │ Phase 1: backend, auth, matching, admin/mod │ Phase 2: payments, push, mobile │ Phase 3: store │ Phase 4: soft launch
legal+ │ Phase 1b: Terms / Privacy / Guidelines      │ Capacitor iOS+Android builds   │ submit + QA    │ 50–200 users, 1st Thursday
entity │                                             │                                 │ approvals      │ iterate on metrics
```

**Minimum team:** founder (full-time) · 1 backend engineer (critical path, wks 1–8) · iOS + Android engineers (parallel, wks 2–8) · Quebec privacy lawyer (retainer, wks 1–4) · part-time bilingual moderator (wk 4+) · freelance copywriter + designer (store listing, icons). Rough 12-week burn at contractor rates: **~$120–180k** (validate against real quotes; a co-founder/equity model changes this materially).

---

## Top risks → mitigations

- **Law 25 consent breaks onboarding** *(high / critical)* → lawyer advice by end of week 1; redesign quiz placement in week 2 if needed.
- **App Store rejection** (privacy label / age gate / account deletion) *(medium / 2–4 wk delay)* → TestFlight by week 6, fix fast, lawyer on call.
- **Moderation SLA broken at launch** *(medium / reputational)* → moderator hired by week 4; dry-run before invites open.
- **Mobile slips past week 8** *(medium)* → Capacitor prototype by week 2 to de-risk; weekly parallel standups.
- **Show-up < 85% in beta** *(medium / product signal)* → reliability scoring + ops-assisted matching; measure weekly; gate public launch on it.

---

## Post-MVP (weeks 12+)
Public store launch + Montreal marketing (r/Montreal, Meetup, IG, Product Hunt) → per-event ticketing (Stripe Connect) + photo upload with content moderation → Perch+ real IAP + conversion tuning → 2nd/3rd neighbourhood for density → Toronto expansion planning.

## Companion repo docs
**Already drafted:** [`LEGAL.md`](LEGAL.md) (placeholder map → links to signed docs) · [`BACKEND.md`](BACKEND.md) (architecture & decisions) · [`schema.sql`](schema.sql) (Postgres DDL) · [`API.md`](API.md) (REST contract).
**Still to create as you build:** `OPS_RUNBOOK.md` (moderation checklist + 24h SLA + escalation) · `TEST_SCENARIOS.md` (QA flows) · an OpenAPI/Swagger export generated from `API.md`.

---

*Generated as a planning aid from the demo + PLAN.md via a multi-domain analysis. Treat estimates and especially legal items as drafts to validate, not decisions already made.*
