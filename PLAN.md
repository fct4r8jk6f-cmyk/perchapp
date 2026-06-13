# Perch — Product Plan

*"Perch" is a working name. This repo holds the interactive v1 demo (`index.html`); this document is the plan the demo expresses.*

## One line

Small groups (4–6) of adults meeting around real activities — friends, not dates — matched by social-style compatibility, starting in Montreal.

## Why this can work

- **Validated category.** Timeleft, Pie, 222 and others have proven adults will pay to be matched into small-group IRL meetups. Adult loneliness is a durable, growing market; "making friends after 25" is a felt problem people actively search for.
- **Real differentiation.** The 12-archetype quiz does three jobs at once: it's a shareable result (organic acquisition), it gives matching a visible reason to exist (trust in the group), and it lets us compose *balanced* groups rather than similar ones — always someone to start the conversation, never five people waiting for someone else to talk.
- **Safety as positioning, not compliance.** First names + emoji only before friendship, friends-only photos, private blocking, no public votes or kicks, mood check before events, take-a-break mode. For the target user (people nervous about showing up alone), this *is* the brand.
- **Beachhead, not everywhere.** One city (Montreal), bilingual en/fr-CA from day one — an underserved, dense, social market where the big comps are weakest.
- **The full loop is designed**: discover → join → pre-event chat → check-in → reflection → add friends → DMs → next event.

## The three risks that kill apps like this — and our answers

### 1. Flaking (the #1 killer)

A 4-person group with one no-show is a bad night; with two it's a failed product promise.

- **Norm, stated everywhere:** leaving is always fine — *early*. Copy across the app frames leaving as "freeing your spot," and the Community Guidelines make "show up or give notice" a core rule.
- **Show-up rate is a first-class profile stat** (visible in the demo) — and earned by *attending* (checking in), not merely joining. Reliability is the reputation currency of Perch, not follower counts. The demo frames it warmly (New → Building → 100%) with a tap-through explainer that states there's no public ranking.
- **Reliability-aware matching and waitlist backfill are now expressed in the demo:** reliability is surfaced on group matching, waitlisted users see their queue position (reliable members ranked higher), and a freed spot triggers an **automatic backfill offer** (notification + time-boxed "claim your spot"). A claim still routes through the free-tier cap and the per-event reservation step.
- **Roadmap (still real backend work):** matching that actually weights reliability, and — only if needed — a small refundable hold on high-demand events.

### 2. Cold start / liquidity

A browse-everything marketplace with 80 users means empty groups and a dead app.

- **Launch with one guaranteed cadence, not a catalogue: Perch Thursdays.** Every week, every signup gets matched into a Thursday group — a group *always* forms. Batch matching on a fixed day beats browse-and-hope at low density (this is the mechanic behind Timeleft's Wednesday dinners). The demo pins this as a guaranteed-group banner at the top of Explore, above the catalogue.
- 2–3 neighbourhoods at launch, venues pre-arranged by us. The Explore catalogue and "Host a hang" unlock progressively as density allows — they are growth-stage features, not launch features.
- Invites are tied to the quiz ("find your type"), so acquisition spreads through a shareable artifact rather than a bare referral link.

### 3. Revenue vs. frequency

A friendship app is *supposed* to be low-frequency — success means people need it less. Subscription-only monetization fights that.

- **Perch+ ($4.99/mo / $39/yr)** stays the convenience tier (priority matching, more groups/week, host perks, travel mode). Core matching stays free — paywalling friendship is both wrong and bad funnel math. The demo enforces the free tier's 2-hangs/week cap (the third join opens the paywall) and shows trial terms plus manage/cancel in Settings.
- **The roadmap revenue is per-event:** ticketed premium activities (cooking class, axe throwing, paint & sip — venues already charge for these) with a take rate, and venue partnerships for free hangs (we deliver committed groups on slow weeknights; venues pay or discount). The demo shows ticket pricing on these activities end-to-end (card badge, detail tile, Join CTA) and now a full **reservation step** — a booking sheet, a pay-at-venue framing (no card captured), and a confirmation code on the joined screen and group detail.
- Per-event payment is also the strongest anti-flake mechanic — the two problems share a solution.

## Metrics that matter (in order)

1. **Show-up rate** — target ≥ 85%. Below that, fix this before anything else.
2. **Week-4 repeat attendance** — does a first event lead to a second?
3. **Friend-adds per event** — the product's actual output is relationships, not sessions.
4. **Time-to-first-group** for a new signup — target < 7 days (Perch Thursdays exists to make this structural).

Explicitly *not* goals: DAU, time-in-app, message volume. Perch should be a low-screen-time app.

## Demo → MVP

The demo intentionally fakes: auth, the matching backend, payments, push, moderation tooling, identity verification (the phone-code flow accepts any code), and all content (groups, chats, people, the searchable directory).

**MVP cut:** profile setup (name + @username) → quiz + archetypes → Perch Thursdays batch matching → reserve → group chat → day-of coordination → check-in → reflection → friends/DMs.
**Deferred:** Host a hang, Explore catalogue beyond the weekly cadence, travel mode, Perch+ billing.

**Open items before any real launch:**
- Legal templates (Terms, Privacy, Guidelines) need attorney review — flagged in-app, now in both en and fr-CA.
- Age verification beyond self-attestation, per Quebec/Canada requirements. The demo floors the age stepper at 18 and discloses 18+ before the quiz, but the quiz still runs before sign-in by design (it's the shareable acquisition artifact) — real verification and the data-before-consent ordering remain open legal questions.
- **Identity verification & payments are simulated:** the verification flow accepts any code and reservations are pay-at-venue with no card captured — a real launch needs an SMS/identity provider and a payment processor with the take-rate logic.
- Trust & safety operations: the 24-hour report-review promise in the app is a staffing commitment, not just copy.
