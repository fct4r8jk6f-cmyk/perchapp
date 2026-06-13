# Perch — Bootstrap Plan (the zero-budget path to first users)

*How to launch Perch with little or no money. This is the **current plan**: prove the idea by hand, then ship a free-tier web app, and only spend money once it's working. Companion to [PLAN.md](PLAN.md) (product strategy) and [LAUNCH.md](LAUNCH.md) (the full hire-a-team roadmap, for later/funded growth).*

> ⚠️ **Not legal, tax, or financial advice.** Dollar figures, grants, and legal resources below are starting points to verify, not commitments. Confirm current grant terms and any legal questions with the actual programs and a Quebec lawyer (see [COUNSEL_BRIEF.md](COUNSEL_BRIEF.md)).

---

## TL;DR

**The ~$120–180k figure in [LAUNCH.md](LAUNCH.md) is the *hire-a-team, move-fast* number — not what it costs to start.** The money in that plan buys **speed and risk-reduction**, not **possibility**. Bootstrapped, the cost to get a working Perch in front of real Montrealers is **~$0–300 + your time.**

The order that matters:

1. **Prove it by hand — $0.** Run one real Perch Thursday with a form + a group chat. No code. If strangers show up and want to come back, you have the only thing that matters.
2. **Launch as a web app — ~$15/yr.** Your demo is already a PWA; deploy it on free-tier infrastructure. Skip the App Store at first.
3. **Pay for the stores only once it works — $124.** Capacitor-wrap the same web app when you have traction.

Spend money on exactly one thing early if you can: **a single legal consult** (or a free clinic). Everything else can wait.

---

## What you actually need vs. what can wait

| Thing | Bootstrap cost | Notes |
|---|---|---|
| Validate the idea (first events) | **$0** | A form, a chat, you. No backend. |
| Domain | **~$15/yr** | Optional even — can start on a free `*.vercel.app` / `*.netlify.app` URL. |
| Backend (DB, auth, realtime, storage) | **$0** | Supabase free tier covers 50–200 users. [`schema.sql`](schema.sql) targets it. |
| Auth | **$0** | Email magic-link or Apple/Google sign-in. **Skip paid SMS** (see below). |
| Push / email | **$0** | Free tiers (FCM/APNs, Resend/Supabase) cover early volume. |
| Apple Developer Program | **$99/yr** | Only when you go to the App Store. Defer. |
| Google Play Developer | **$25 once** | Only for Play Store. Defer. |
| Legal consult | **$0–250** | One paid hour, or a free clinic. The one early spend worth making. |
| Incorporation | **$0 to start / ~$500–2k later** | *Not* a technical gate to publishing — see below. A liability decision, not a launch blocker. |
| Contractors, lawyer retainer, paid vendors | **$0 now** | These are the LAUNCH.md "go fast" costs. Later, ideally funded by grants/revenue. |

**Bootstrap total to be live as a web app: the price of a domain.** To add the app stores later: ~$124.

---

## Phase A — Prove it by hand ($0, this is the most important step)

Build nothing. Run **one real Perch Thursday** for 5–6 strangers and see what happens. This de-risks everything and is exactly what grants and (later) investors want to see.

**The playbook:**
1. **Recruit ~8–10 people** (you need 5–6 to show). Free channels: friends-of-friends, r/montreal and r/montreal-area university subs, McGill / Concordia / UdeM Discord & Facebook groups, Meetup.com (free to attend), Bumble BFF, local Slack/Discord communities, and **the quiz itself as a share hook** (the demo is your landing page — send the link).
2. **Sign-up = a Google Form** (name, the 7-quiz answers or a short version, availability). Free.
3. **Form the group yourself** — mix the personalities by hand (you have the archetype logic in the demo). Pick a cheap/free venue (a café, a park, a board-game bar).
4. **Run it.** Show up. Be the host. First names + an icebreaker.
5. **Measure the only two things that matter:** *did they show up?* and *would they come again / did anyone exchange contacts?* Send a 3-question feedback form after.
6. **Repeat 2–4 times.** Tweak each round.

**Success bar before you build anything:** show-up ≥ ~80% and most people say they'd come back. If that's not happening, no backend fixes it — change the format, not the code. If it *is* happening, you have proof.

---

## Phase B — Lean web-app launch (~$15, only after Phase A works)

Now turn the demo into a real product on free infrastructure.

- **Frontend:** your existing `index.html` PWA, deployed free on Vercel / Netlify / Cloudflare Pages. Users "Add to Home Screen" and it behaves like an app — **no App Store needed to get real users.**
- **Backend:** **Supabase free tier** — Postgres + Auth + Realtime + Storage in one. Implement [`schema.sql`](schema.sql) (it was designed for exactly this) and the endpoints in [`API.md`](API.md). The realtime needs (chat, day-of, backfill) ride Supabase Realtime — no socket server to run (see [BACKEND.md](BACKEND.md) §5, §12).
- **Auth — the big money-saver:** use **email magic-link or Apple/Google sign-in (free)** instead of paid SMS OTP. Phone verification becomes the *optional* "✓ Verified" badge later — the app already treats verification as optional and non-gating. This removes the Twilio cost **and** the SMS-fraud risk in one move.
- **Notifications:** start with in-app + email (free tiers). Add push when you wrap with Capacitor.
- **Keep the free-tier enforcement honest** server-side (the 2-hangs/week cap lives in the DB — see `schema.sql`), so Perch+ has something to sell later.

**Build it yourself.** The backend is fully designed ([`schema.sql`](schema.sql) + [`API.md`](API.md) + [`BACKEND.md`](BACKEND.md)) and the demo is the frontend. This is the work that replaces the contractor line in LAUNCH.md — and it can be built incrementally against the free tier.

---

## Phase C — App Store / Play Store (only when it's working, ~$124)

Once the web app has steady users, wrap it for the stores:
- **Capacitor** (free, open-source) wraps the *same* web codebase into iOS + Android shells — one codebase, both stores (see [BACKEND.md](BACKEND.md) §3 and LAUNCH.md Phase 3).
- Costs: **$99/yr Apple + $25 once Google.**
- This is also when push notifications and (if/when you add it) Perch+ via Apple/Google IAP come online.

There is no rule that an app must be on the App Store to have users. The web-first path lets you grow to real traction for ~$15 before paying Apple a cent.

---

## The one thing not to skip — legal/safety, done cheaply

Perch is an **18+, in-person, stranger-meetup app handling personal data in Quebec.** Law 25 has real penalties and there's genuine physical-safety liability. You don't need a $2–5k retainer to be responsible — but don't go to zero here. The budget version:

- **You already have disclaimed Terms / Privacy / Community Guidelines** in the app (templates flagged "pending attorney review"). That's a real starting point — keep the flag until counsel signs off ([LEGAL.md](LEGAL.md)).
- **Prioritize one ~$250 one-hour consult** over almost any other spend — or use **free options**: Quebec university legal clinics, [CIPPIC](https://cippic.ca) (public-interest tech-law clinic), and pro-bono startup-law programs. Hand them [COUNSEL_BRIEF.md](COUNSEL_BRIEF.md) — it exists to make a short/free consult go far.
- **Scope down to lower risk:** at launch, run **your own hosted events** (you vet the venue and attend) rather than open user-hosted hangs — this removes most host-screening liability until you can afford to handle it.
- **Incorporation is not a publish gate.** You *can* ship as an individual. Incorporating limits personal liability (worth doing for a meetup app once there's traction/money), but it doesn't block Phase A or B.

---

## Free money (so you don't have to self-fund)

A working Phase-A pilot ("we ran 4 Thursdays, ~85% showed up") is exactly what non-dilutive programs fund. Worth a few hours of applications — **verify current terms, these change:**

- **Futurpreneur Canada** — young-entrepreneur loans + mentorship.
- **PME MTL** — Montreal small-business support and grants.
- **Quebec youth-entrepreneurship grants** (e.g. via the provincial programs / local CLDs).
- **Bank startup programs** (RBC/BDC and others run founder support + small grants).
- **Student/startup credits** — AWS Activate, Google for Startups, Microsoft for Startups, and Supabase/Vercel startup credits (free infra beyond the free tier).

---

## Do this week — the $0 checklist

- [ ] Pick a date and venue for **Perch Thursday #1**.
- [ ] Make the **sign-up Google Form** + a **feedback form**.
- [ ] Post the **quiz/demo link** in 2–3 free Montreal channels to recruit ~10 people.
- [ ] Run the event. Measure show-up + would-come-again.
- [ ] Book a **free or one-hour legal consult**; bring [COUNSEL_BRIEF.md](COUNSEL_BRIEF.md).
- [ ] Shortlist **2–3 grant programs** to apply to once you have pilot numbers.
- [ ] *(After Phase A works)* create a **Supabase free project** and start the backend against [`schema.sql`](schema.sql).

---

*The expensive plan in [LAUNCH.md](LAUNCH.md) is still the destination once you're funded. This is how you get there from $0: prove it by hand, ship it free, and let traction pay for the rest.*
