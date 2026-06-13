# Perch — Counsel Brief & Founder Decision Memo

Perch is a bilingual (English / Quebec-French), 18+, pre-launch social app for Montreal that forms small groups around real-world activities. This single document frames the open questions for a Quebec privacy/tech lawyer (Part A) and the operational/product decisions the founder can make now (Part B). Everything in the product is still a single-file interactive demo; the production backend is designed but not built.

**Not legal advice.** This document frames *questions for counsel* and *decisions for the founder*; it does not assert what the law requires. The in-app legal documents stay flagged as "templates pending attorney review" until counsel signs off.

**How to use this:** Part A is the brief to hand the lawyer (questions and deliverables); Part B is the founder's decision memo (recommendations the founder can act on now). Both reference the repository — `LEGAL.md` (placeholder map + legally-relevant product facts), `schema.sql` (full data inventory), and `BACKEND.md` (auth / consent / residency / retention design).

---

# Part A — Brief for Counsel

**Not legal advice — prepared by the founder to brief counsel.** Nothing in this document asserts what the law requires. It frames *questions for counsel* and *decisions for the founder*. The in-app legal documents are explicitly flagged as "templates pending attorney review" and will stay that way until you sign off.

> **Note on numbering:** This brief renumbers and expands the 16-question counsel list in `LAUNCH.md` (it adds new questions and regroups them). A reader holding both should reconcile by topic, not by question number — the substance of every `LAUNCH.md` question is preserved here, with additional questions added.

---

## 1. Context for counsel

**Perch** is a bilingual (English / Quebec-French) mobile-first social app for Montreal. It forms small groups of 4–8 people (the demo and `LAUNCH.md` use 4–6; final launch group size is an open product decision) around real-world activities so strangers can become friends; its wedge is "Perch Thursdays," a weekly batch-matched in-person hang. It is **18+** and **pre-launch**. Today the product exists only as a single-file interactive demo (`index.html`) with no backend; the production server is *designed but not built* (`schema.sql`, `API.md`, `BACKEND.md`). The applicable regime is **Quebec**: Law 25 (private-sector privacy), federal **PIPEDA**, and **Bill 96** (French-language requirements), with the added exposure of an app that arranges **in-person meetups between strangers**. We are asking you to (a) give us written answers to the prioritized questions below — above all the three existential ones that currently block finalizing onboarding — and (b) draft the attorney-reviewed legal documents and vendor agreements described in Section 2, so we can lift the in-app "pending review" flag and submit to the App Store / Play Store with confidence.

## 2. What we're asking you to deliver

1. **Five attorney-drafted in-app legal documents**, each in **English and Quebec-French of equal quality** (Bill 96 — French must not read as a machine translation of an English original):
   - **Terms of Service / EULA** — IRL-meetup liability framing, the 18+ age gate, refunds, dispute resolution, and Apple/Google EULA requirements.
   - **Privacy Policy** — Law 25 + PIPEDA: consent (including the pre-sign-in quiz), retention, access / deletion / portability rights, data residency, and vendor processing disclosures.
   - **Community Guidelines** — conduct rules, the 24-hour human-review commitment, appeals, and no-show / safety policy.
   - **How moderation works** — accuracy of our human-first / no-public-voting / 24h claims as policy commitments we can stand behind.
   - **Wellbeing resources** — real Montreal/Quebec crisis and support lines, plus a "not a crisis service" disclaimer.
2. **Store-disclosure artifacts consistent with the Privacy Policy you draft** (LEGAL.md §4 lists these): the **Apple Privacy Nutrition Label**, the **Google Data Safety form**, and the **store age-rating questionnaire** — we need them to be accurate against, and consistent with, the finalized Privacy Policy and our self-attested 18+ posture.
3. **Vendor Data Processing Agreements (DPAs)** for each US-based sub-processor we expect to use (SMS/OTP, push, email, database/storage host), and guidance on a public sub-processor list.
4. **Written answers to the prioritized questions** in Section 4 — at minimum the three existential ones, ideally all.
5. **Sign-off to remove the in-app "templates pending attorney review" flag** once the documents are finalized.

To ground your work we will provide: **this repository**, the **running interactive demo**, and **`schema.sql`** — a full PostgreSQL schema that enumerates every personal-data field we intend to collect (see Section 6).

## 3. Product facts you need to know

These are the legally-relevant facts; the repository is the source of truth (LEGAL.md §3; BACKEND.md §4, §7, §9).

- **18+ gate is self-attested.** An age stepper floors at 18, and 18+ is disclosed before the quiz. There is **no government-ID check**. The production design records the attestation as a dated `consent_records` row at account creation. Whether self-attestation is sufficient is our #1 open question.
- **The 7-question personality quiz runs *before* sign-in and consent — by design**, because it is the shareable acquisition artifact (the viral loop). The mitigation in the backend design is to collect the quiz **fully anonymously** (an anonymous session, no PII), persist answers keyed to that anonymous session, and capture **consent at the "attach" moment** — the first sign-in, the first point at which an identifiable individual exists. Our **working assumption pending your confirmation** is that this framing satisfies Law 25's "consent before collection" because no identifiable individual yet exists during the anonymous phase — but we are not asserting it; it may not hold if anonymized quiz answers are still "personal information" (see Q6). We need you to confirm.
- **No card payments are captured.** Activity reservations are **pay-at-venue**: the booking flow stores only a `PCH-XXXX` confirmation code, a ticket flag, and the price *as a display string* — no card, no Stripe. We **believe no card data is captured, so Perch stays out of PCI-DSS scope for tickets** — please confirm this with us and, if relevant, the processor (PCI-DSS is an industry standard, not Quebec law). The **Perch+ subscription** (raises the weekly join cap from 2 to 5) is intended via **Apple/Google in-app purchase**. We **assume the store acts as merchant of record and collects/remits GST/QST** on the subscription — please confirm, and tell us whether Perch has any **residual Quebec sales-tax registration/remittance obligation** of its own. Real card payments are explicitly out of scope for launch.
- **Identity verification is simulated today.** The phone-code flow accepts any code. In production it becomes phone OTP sign-in, plus a separate, **optional** "✓ Verified" badge that **never gates joining or hosting**.
- **Safety posture is the brand:** first names + emoji before friendship, friends-only photos, private blocking (the blocked user is not told), take-a-break (reversible pause, distinct from deletion), and **report → human review within 24 hours**. The 24h SLA is a **staffing commitment**, not just copy.
- **Account deletion is in-app and framed as permanent** (Apple and Google both require in-app deletion). The backend models this as an async pipeline that removes/anonymizes PII and revokes tokens. We **propose** to retain certain compliance records (consent, audit, safety reports) after deletion, with the account link anonymized where possible — but we need you to confirm **what we MUST retain, what we MAY retain, and for how long** (see Q13/Q14); we are not asserting "as legally required" as settled.
- **Bilingual obligation (Bill 96):** the app, its legal documents, and its store listing must all ship in en / fr-CA, with French available by default for Quebec users.

## 4. Prioritized questions

*These are for counsel to answer — we are not asserting answers. For each, "why it matters" and the "product consequence" of likely answers are given so the stakes are visible. Where a question states a rule (e.g. "Law 25 may require…"), it is stated as a question for you to confirm, never as a settled requirement.*

### The three existential questions (these block finalizing onboarding)

**Q1 — Minimum viable age verification.** Is **18+ self-attestation** sufficient for an 18+ social app that arranges in-person meetups, or is some form of **proof-of-age (ID, or a third-party age-estimation service)** required?
- *Why it matters:* It is the single biggest gate to launch; it shapes the entire onboarding flow and our App Store review risk.
- *Product consequence:* If self-attestation stands, onboarding ships as designed. **If ID proof is required, the quiz must move behind sign-up** (you cannot present a viral, no-account quiz and then demand ID), which directly damages the acquisition loop and adds a privacy liability (storing government ID is itself regulated data).

**Q2 — Law 25 consent ordering for the pre-sign-in quiz.** Does collecting the 7-question quiz (plus a few light demographics) **before** sign-up and any consent dialog conflict with Law 25's "consent before collection"? Does our **anonymous-collection mitigation** (no PII during the quiz; consent captured at first sign-in/attach) cure the concern?
- *Why it matters:* The quiz-before-sign-in flow is the product's growth engine; if it's non-compliant as designed, onboarding must be re-architected.
- *Product consequence:* If the anonymous framing holds, we keep the flow. If not, options are to **re-run the quiz post-sign-up** (kills the share-before-account magic), **treat it as implicit consent via ToS**, or **require sign-up first** — each of which weakens the viral loop to a different degree.

**Q3 — Data residency.** Must user personal data be stored on **Canadian servers**, or is **encrypted US cloud** acceptable (with disclosure for any cross-border flow)?
- *Why it matters:* It constrains our entire vendor and hosting choice and sets our Law 25 cross-border posture.
- *Product consequence:* Canada-only narrows vendor options and may raise cost, but is the safest posture (we have identified `ca-central-1` / Montreal-region options for DB, storage, email, and compute). If encrypted US processing is acceptable for low-sensitivity flows (e.g. push-token relay, PII-scrubbed error traces), we keep a wider, cheaper toolset under DPAs and disclosure. (See Q10 on whether a privacy impact assessment / disclosure is required before any cross-border flow.)

### Identity & age

**Q4.** Do **Apple and Google** require proof-of-age beyond self-attestation for this category of app, independent of what Quebec law requires?
- *Why it matters:* Store policy can force ID even where the law would not. *Consequence:* a store requirement would override Q1's product-design choice.

**Q4a — Minors despite the 18+ gate.** If a minor self-attests as 18 and gets in, what **detect-and-remove** process should we operate, and how must we handle (and is there heightened sensitivity around) any data already collected from someone later found to be under 18? What do **Law 25 and federal rules on minors' data** require here?
- *Why it matters:* A self-attested gate will be defeated by some minors; the regime around minors' data may be stricter and the cleanup obligations specific. *Consequence:* may require a removal/escalation workflow, a special-handling/purge path for under-18 data, and possibly distinct retention treatment — all new build and ops items.

**Q4b — App-store age-rating questionnaire (compliance item).** What **age rating / content descriptors** must we declare in the Apple and Google rating questionnaires for a meetup app (a meetup/social app may trigger 17+/18+), and how do we keep the **store rating consistent with the in-app self-attested 18+** posture?
- *Why it matters:* An inconsistency between the store age rating and in-app gating is a known store-rejection cause. *Consequence:* drives the rating answers we submit and forces the store metadata and in-app gate to line up before submission.

**Q4c — Biometric / ID-data obligations (conditional on Q1).** *If* Q1's answer requires ID proof or face-based age-estimation: what **retention limits** apply to any ID images we capture; does an **age-estimation vendor introduce BIOMETRIC data** (Quebec has specific biometric rules, including a **Commission d'accès à l'information (CAI) disclosure obligation** for creating/using a biometric database); and what **vendor DPA scope** is needed for that data?
- *Why it matters:* ID/biometric data is among the most regulated categories and carries a distinct Quebec disclosure regime. *Consequence:* if ID/biometrics enter scope, we need tight retention rules, a CAI filing assessment, and a vendor DPA covering biometric processing — a materially larger compliance surface than self-attestation.

**Q5.** May we **exclude unverified users from groups**, or must the optional "✓ Verified" badge stay purely cosmetic and never gate participation?
- *Why it matters:* Bears on both safety design and potential discrimination exposure. *Consequence:* if exclusion is permitted, verification could become a safety lever; if not, it must remain a non-gating trust signal (as currently designed).

### Consent & data

**Q6.** Are the **quiz answers** "personal information" under PIPEDA / Law 25 while held under an anonymous session with no PII?
- *Why it matters:* Determines whether the anonymous phase is in or out of scope, and whether the Q2 working assumption (anonymous collection cures the consent-ordering concern) holds. *Consequence:* if they're personal information even when anonymous, the anonymous-collection mitigation in Q2 may not be enough and the flow may need reordering.

**Q7.** May we **collect a phone number for verification before the user opts in** to the broader privacy terms?
- *Why it matters:* Phone OTP is our sign-in credential and sits at the consent boundary. *Consequence:* if not, the consent dialog must precede OTP, changing the sign-in sequence.

**Q8.** Is our **consent model** — granular, revocable `consent_records` per type (terms, privacy, age attestation, marketing/notifications), plus versioned `legal_acceptances` tying each user to the exact document version they accepted — sufficient, and is **separate marketing/notification consent** correctly scoped? (CASL specifics are broken out in Q8a.)
- *Why it matters:* Defines what we must build and prove. *Consequence:* gaps here change the schema and the onboarding consent screens.

**Q8a — CASL specifics.** For our commercial electronic messages, please advise on: **express vs implied consent**; the prescribed **unsubscribe mechanism and the 10-business-day processing window**; **sender identification** in every commercial electronic message; and — crucially — whether our **transactional notifications (event reminders, backfill offers) are "commercial" messages within CASL** or fall outside it.
- *Why it matters:* CASL drives both legal exposure and concrete build work. *Consequence:* the answer determines whether we need separate consent flags per message type, unsubscribe plumbing wired into transactional flows, and sender-ID footers — i.e. it directly shapes the notifications schema and the consent screen.

**Q8b — Automated decision-making transparency.** The matcher groups people using their **personal data (reliability + archetype)**. Does **Law 25's automated-decision-making disclosure** (notice + a right to explanation / to make representations) apply to our group formation, and does the fact that **ops reviews the batch before publishing (human-in-the-loop)** change that analysis?
- *Why it matters:* If automated-decision rules apply, we owe users notice and a representation right. *Consequence:* may require disclosure copy in onboarding/the Privacy Policy and a representation pathway; the human-review step may or may not move us out of scope — we need your read.

### Residency & processing

**Q9.** Does **each US sub-processor** (SMS/OTP, push, email, DB/storage host) require its own **DPA**, and is a **public sub-processor list** expected?
- *Why it matters:* Drives contracts we must sign before launch. *Consequence:* determines vendor onboarding lead time and which vendors are viable.

**Q10.** For any tolerated cross-border flow, **we understand Law 25 MAY require a privacy impact assessment (PIA) and/or disclosure for transfers outside Quebec — please confirm whether a PIA is mandatory pre-launch, and what Privacy-Policy disclosure language is needed.**
- *Why it matters:* Law 25 obligations around transfers. *Consequence:* a required PIA adds a pre-launch work item and specific Privacy Policy text. (See also Q15a on whether a PIA is required for the system as a whole, not only cross-border flow.)

### Moderation & IRL liability

**Q11.** What is our **liability exposure in the window between a report and the 24-hour decision**, and does the 24h SLA as a *published commitment* create obligations we should be careful about?
- *Why it matters:* The SLA is brand-central and publicly stated. *Consequence:* may change how we phrase the commitment and how we staff/escalate. (Part B mirrors this caution: publishing a fixed SLA may itself create a commitment we can be held to — it is not a pure staffing checkbox.)

**Q11a — Emergency / duty-to-warn escalation (distinct from the 24h content SLA).** Separate from ordinary content review: what should Perch do when a report alleges **assault or a physical-safety threat at an in-person event**? Is there any **duty to warn**, and any duty or option to **cooperate with or report to police**?
- *Why it matters:* A physical-safety report is a different risk class than offensive content, and the 24h content SLA is the wrong frame for it. *Consequence:* likely requires a separate high-priority escalation path (immediate, not 24h), documented guidance for the moderator, and a law-enforcement cooperation posture — distinct ops and a distinct policy from content moderation.

**Q12.** For **harm at an in-person meetup**, does a **ToS liability waiver suffice**, or do we need **host screening** or other affirmative safety measures?
- *Why it matters:* This is the defining real-world-liability risk of the product. *Consequence:* if a waiver is insufficient, we must add host-screening (a new flow and ops burden) before allowing user-hosted hangs.

**Q12a — Wellbeing-doc liability posture.** Is listing crisis lines plus a **"not a crisis service" disclaimer** sufficient to limit our duty-of-care exposure, and must the listed lines be **official / Quebec-licensed resources**?
- *Why it matters:* The wellbeing document is a duty-of-care touchpoint; getting it wrong could increase rather than limit exposure. *Consequence:* determines the disclaimer wording and constrains which crisis/support lines we may list.

### Compliance / retention / breach

**Q13.** Is our proposed **retention schedule** workable (see Section 6 / BACKEND.md §9 — e.g. anonymous quiz data purged at 30 days if never attached; OTP codes purged within 24h; chat retained while active and purged on deletion; compliance records retained on legal hold)? What **specific retention numbers** should we publish, and — for account deletion — **what MUST we retain vs what MAY we retain, and for how long** (consent / audit / safety records)?
- *Why it matters:* The schedule must be concrete and disclosed, and "retain compliance records" must be grounded in what the law actually requires rather than assumed. *Consequence:* sets exact values we hard-code into retention jobs and the Privacy Policy, and defines the deletion pipeline's retain-vs-purge logic.

**Q14.** What **breach-notification and deletion SLAs** apply, and is a **written incident-response plan** required pre-launch?
- *Why it matters:* Law 25 breach obligations and Apple/Google deletion requirements. *Consequence:* defines SLA numbers we commit to and a document we must author before launch.

**Q15.** Must we **appoint a Privacy Officer** before launch, and what are that role's documented duties?
- *Why it matters:* Law 25 governance. *Consequence:* may require naming a person and publishing contact details in the Privacy Policy.

**Q15a — Privacy-by-default / privacy-by-design and governance.** Beyond the cross-border flow (Q10): do our **default visibility/notification settings and the overall data-processing design** require a documented **Privacy Impact Assessment for the SYSTEM as a whole**? And do we need **published privacy-governance policies** and a **confidentiality-incident register** under Law 25?
- *Why it matters:* Law 25's privacy-by-default / privacy-by-design and governance obligations may reach the whole system, not just transfers. *Consequence:* may require a system-level PIA as a pre-launch work item, published governance policies, and a standing incident register — documents and process we must stand up before launch.

**Q15b — Data-subject-rights operational SLAs and requester authentication.** What is the **statutory deadline to respond** to access / portability / correction requests, **and how must Perch authenticate a rights requester** before honoring an export or deletion?
- *Why it matters:* We owe a timely response, but a naive export/deletion endpoint is an attack vector — an attacker must not be able to export or delete another user's data. *Consequence:* sets the response-time SLA we build to, and requires an identity-verification step (anti-abuse) gating every export/deletion before it runs.

### MVP scope

**Q16.** What is the **minimum viable verification posture to launch day 1** (synthesizing Q1/Q4)?
- *Why it matters:* We need a single, shippable answer to unblock onboarding. *Consequence:* this is the decision the whole launch sequence waits on.

**Q17.** Can we **launch with no card capture (pay-at-venue)** and Perch+ via store IAP, on the working assumption that **no card data is captured so Perch stays out of PCI-DSS scope for tickets** (to be confirmed with you/the processor), until a later phase?
- *Why it matters:* Confirms our no-payments design is a viable launch posture. *Consequence:* if not, we must add a processor (Stripe) and assess GST/QST registration before launch, slipping the timeline.

**Q18.** Are there **Bill 96 specifics** for the **store listing and store metadata** (screenshots, description, keywords) beyond translating the in-app content and legal docs?
- *Why it matters:* French-first requirements may reach the store presence itself. *Consequence:* affects what the store-listing copywriter must produce.

**Q18a — Trademark + bilingual legal-name (counsel work, not just a founder to-do).** Please **advise on and clear the "Perch" name** (trademark) and on the **en / fr legal-name forms** required under Quebec corporate-naming rules.
- *Why it matters:* "Perch" is a working name and the legal entity must carry compliant en/fr name forms; clearing the mark and the names is legal work, not a founder checkbox. *Consequence:* determines the final product name we ship under and the exact `LEGAL.company` values (both languages) we put in the documents — and a failure to clear forces a rename before store submission.

## 5. Placeholders & specifics counsel's answers must let us fill

The demo carries deliberate stand-ins (LEGAL.md §1). We need your answers and drafting to let us replace them with final values:

- **Entity legal name (en + fr forms)** — currently `[Legal Entity Name, Inc.]`; to become the incorporated entity's exact legal name in both languages (e.g. "Perch Technologies Inc." / "Technologies Perch inc."). Appears in the footer of all five legal documents. (See Q18a — we are asking you to clear/advise on the name forms.)
- **Support / privacy contact email** — currently `support@[yourdomain].com`; to become a real monitored address (also used by the in-app "Contact us" flow). (Note: a separate demo stand-in `you@email.com` in Settings must also become real.)
- **Effective date** — currently `[Effective date]`; the published effective date of the finalized Terms / Privacy.
- **Final product name + trademark clearance** — "**Perch**" is a *working name*; we need clearance and a confirmed final name before store submission (Q18a). (The demo invite link `perch.app/...` is a stand-in pending the real domain.)
- **Real Quebec crisis lines** for the Wellbeing document — actual Montreal/Quebec crisis and support lines (Q12a on whether they must be official/licensed), plus the "not a crisis service" disclaimer.
- **Retention-schedule numbers** — the concrete day/hour values to publish, and the MUST-vs-MAY retain rules (per Q13).
- **Deletion and breach SLAs** — the specific timeframes we commit to (per Q14), plus the data-subject-rights response SLA and requester-authentication step (per Q15b).
- **Privacy Officer** — whether one must be appointed, and if so the name/role/contact to publish (per Q15).

We are keeping all current placeholders and the in-app "pending attorney review" flag in place until you finalize the entity and documents.

## 6. Data inventory pointer

You do not need to reverse-engineer what we collect. **`schema.sql` enumerates every personal-data field** we intend to hold (accounts, profiles, quiz responses, interests, settings, memberships, reservations, messages, friendships/blocks, reports, consent and audit records, and the rights-request tables). **BACKEND.md §9** proposes the **consent model** (anonymous quiz → consent captured at attach; granular revocable `consent_records`; versioned `legal_acceptances`) and a **table-by-table retention schedule**, plus the access / deletion / portability endpoints and the audit-log design — all offered for you to validate, not as settled positions. We will walk you through both alongside the running demo.

---

*Source documents in the repository for every fact above: `LEGAL.md` (placeholder map and legally-relevant product facts), `LAUNCH.md` (questions-for-counsel list and the three existential gates — this brief renumbers/expands its 16-question list), `BACKEND.md` (auth/consent/residency/retention design), and `schema.sql` (full data inventory). This brief restates them as questions and decisions; it does not assert the law.*

---

# Part B — Founder Decision Memo

> **Not legal advice.** This memo frames **founder decisions** — operational and product calls the founder can make now — each with a recommendation. Items marked *(pending counsel)* carry an open legal question that a Quebec privacy & tech lawyer must confirm; the recommendation is the founder's working assumption until then, not an assertion of what the law requires. It reconciles the **Founder Decisions** list in `LAUNCH.md` with the **Open decisions** in `BACKEND.md` §12; where both speak, this memo merges them without contradiction.

### How to read this

Every decision below is something the founder can act on this week. Three of them (age verification, quiz-before-consent, data residency) also have a *legal* dimension that counsel must confirm — but the founder still makes the **product call now** and adjusts only if counsel says otherwise. Don't wait on the lawyer to lock the stack, the vendors, or the build plan; those are pure founder calls. (These three map to Part A's three existential questions Q1–Q3; the cross-references below point to Part A by topic, not to `LAUNCH.md`'s original question numbers, which Part A has renumbered.)

---

### Decide-by sequence (at a glance)

| # | Decision | Blocks what until decided | Decide by |
|---|---|---|---|
| 1 | Minimum viable age verification | Onboarding flow finalization; App Store age-rating; quiz placement | **Before Phase 0 exits** (Wk 1–2) — confirm w/ counsel |
| 2 | Quiz-before-consent ordering | Onboarding flow; quiz acquisition loop; consent records design | **Before Phase 0 exits** (Wk 1–2) — confirm w/ counsel |
| 3 | Data residency (Canada-only vs US) | DB/storage/hosting region choices; every vendor + DPA | **Before Phase 0 exits** (Wk 1–2) — confirm w/ counsel |
| 4 | Mobile stack (Capacitor vs native vs PWA) | All mobile build work; team hiring; store submission path | **Before Phase 0 exits** (Wk 1–2) — pure founder call |
| 5 | Who builds mobile / who moderates | Phase 1–2 staffing; the 24h SLA commitment | **Phase 0 (hiring starts Wk 1); moderator by Wk 4** |
| 6 | Incorporation + entity name + "Perch" trademark | Bank, payment/IAP accounts, vendor contracts, legal placeholders | **During Phase 0 (Wk 1–2)** — entity blocks accounts |
| 7 | SMS / OTP vendor | Phone sign-in build (Phase 1); residency confirmation; DPA | **Before Phase 1 starts** (end Wk 1) — create test acct now |
| 8 | Build-vs-buy chat / realtime | Realtime architecture (Phase 1); chat, day-of, backfill | **Before Phase 1 backend starts** (Wk 2) |
| 9 | Payment flow (pay-at-venue vs upfront) | Phase 2 scope; PCI exposure; Terms refund language | **Before Phase 2** (Wk 4) — pay-at-venue confirmed for launch |
| 10 | Group-formation cadence | The matcher build (Phase 1, job #5); ops staffing for batch review | **Before Phase 1 matcher work** (Wk 2–3) |

---

### 1. Minimum viable age verification *(pending counsel)*

**Decision (one line):** How do we satisfy the 18+ requirement at launch — self-attestation, SMS as a soft signal, or hard government-ID proof?

**Options:**
- **Self-attested** age gate (today's demo: stepper floored at 18, disclosed before the quiz), recorded server-side.
- **Self-attested + phone verification** as a weak corroborating signal (the SMS the user already does for sign-in).
- **Hard ID proof** (government-ID verification vendor) — high friction, and storing government ID is itself a Law 25 liability.

**Key trade-off:** ID proof is the strongest defense for an 18+ in-person app but it (a) adds significant onboarding friction, (b) forces the quiz *behind* signup — killing the viral, shareable quiz loop — and (c) creates a new pile of sensitive personal data to secure. Self-attestation is frictionless and preserves the acquisition loop, but its sufficiency is an open legal question and may not survive App Store review for a meetup app.

**RECOMMENDATION: Launch with self-attested 18+, recorded as a `consent_records` age-attestation row (attested age + timestamp, captured at account attach), with phone verification as a soft signal. Do not store government ID.** Add stronger verification only if abuse data or counsel/App Store review demands it. *(This is the #1 open legal question — get written counsel advice in Phase 0 before finalizing the flow; if counsel says ID proof is mandatory, the quiz-placement decision (#2) changes with it. Note also Part A's Q4a–Q4c: a minor-detect-and-remove process, the store age-rating questionnaire's consistency with the in-app gate, and — only if ID/age-estimation is required — biometric/CAI obligations.)*

**Blocks/unblocks:** Unblocks finalizing the onboarding flow, the quiz placement, and the App Store age-rating answers. Until decided, you cannot lock onboarding or be confident of store approval.

**When:** **Before Phase 0 exits.** Bring it to the lawyer in Week 1; it is the single biggest gate in `LAUNCH.md`.

---

### 2. Quiz-before-consent ordering under Law 25 *(pending counsel)*

**Decision (one line):** Does collecting the 7-question quiz (+ a few demographics) *before* sign-in/consent work under Law 25's "consent before collection," or must we reorder?

**Options:**
- **Keep the flow** and collect the quiz under an **anonymous session with zero PII**, attaching it to the account (and capturing consent) at first sign-in.
- **Re-run the quiz post-signup** (consent first, quiz second) — safest on consent, but the user does the quiz twice or the magic moment moves behind a signup wall.
- **Treat quiz collection as implicit-consent via ToS shown up front** — weaker footing, and clutters the pre-quiz screen.

**Key trade-off:** The quiz is deliberately the **shareable acquisition artifact** — moving it behind signup is the single biggest threat to the viral loop. Anonymous collection preserves the magic, and the founder's **working assumption (pending counsel)** is that it is defensible because no identifiable individual exists yet — but that framing needs counsel sign-off and may not hold if anonymized quiz answers are still "personal information" (Part A Q6). If it fails, onboarding must be redesigned in Week 2.

**RECOMMENDATION: Keep the quiz before sign-in, but collect it fully anonymously** — anonymous session token, no PII, answers persisted to `quiz_responses` keyed to that session — **and capture consent (terms, privacy, age attestation, marketing) at the attach moment on first sign-in**, recorded in `consent_records` / `legal_acceptances` against the versioned legal docs. **Have counsel confirm the anonymous-collection framing (Part A Q2/Q6).**

**Blocks/unblocks:** Unblocks the onboarding flow design, the anonymous-quiz-then-attach backend (BACKEND §4), and the consent-records schema. Blocks finalizing onboarding until confirmed.

**When:** **Before Phase 0 exits.** One of the three existential counsel questions; redesign window is Week 2 if the answer is negative.

---

### 3. Data residency — Canada-only vs allow scrubbed US processing *(pending counsel)*

**Decision (one line):** Must stored personal data and primary compute live in a Canadian region, or is encrypted US cloud acceptable?

**Options:**
- **Canada-only** for stored PII and primary compute (`ca-central-1` Montreal/Toronto), tolerating US processing only for low-sensitivity, content-light flows.
- **Encrypted US cloud** with disclosure — faster/cheaper and widens vendor choice, but the weaker Law 25 posture.

**Key trade-off:** Canada-only is the safest Law 25 posture and the simplest story for users and counsel, but it narrows vendor choice (some SMS/push/error tools are US-centric) and can cost more. Allowing US processing widens options but adds cross-border-disclosure obligations (and possibly a privacy impact assessment — Part A Q10) and weakens the launch narrative.

**RECOMMENDATION: Canada-only for all stored personal data and primary compute** (pin DB, object storage, API, workers, and backups to `ca-central-1`). **Tolerate US processing only for low-sensitivity, content-light flows** (push-token relay via APNs/FCM, error traces with PII scrubbed), each covered by a DPA and disclosed in the privacy policy. **Confirm with counsel whether a privacy impact assessment is required before any cross-border flow (Part A Q10).**

**Blocks/unblocks:** Unblocks every infrastructure decision — DB host, storage, hosting region, and which vendors are even eligible. This is the constraint that filters the vendor shortlist, so it must precede vendor commitments.

**When:** **Before Phase 0 exits.** One of the three existential counsel questions; it gates Phase 1 backend setup.

---

### 4. Mobile stack — Capacitor vs native vs PWA-only

**Decision (one line):** What do we wrap/build the mobile apps as?

**Options:**
- **Capacitor** — wrap the existing single-file PWA into real iOS/Android shells, one codebase to web + both stores.
- **Native rebuild** (Swift / Kotlin) — most fluid, but a full rebuild, two more codebases, and a duplicated i18n surface.
- **PWA-only** — no native app; fails store distribution and can't host Apple/Google IAP for Perch+.

**Key trade-off:** Native is marginally smoother for animation-heavy screens but is a from-scratch rebuild that breaks the small-team, single-codebase, single-i18n-surface ethos. PWA-only can't ship the IAP subscription or get store distribution. Capacitor preserves the no-build spirit, gives the native plugins Perch actually needs (push, IAP, photo picker, secure token storage), and is the fastest credible path to both stores.

**RECOMMENDATION: Capacitor.** Wrap the existing demo; ship web + iOS + Android from one codebase. Revisit a native rebuild only if store performance review or a richer realtime UI demands it (the app already honours `reduceMotion`, so the webview gap is manageable).

**Blocks/unblocks:** Unblocks all mobile build work, the right hiring profile (web vs native engineers), and the store-submission path. Until chosen, you can't staff or schedule mobile.

**When:** **Before Phase 0 exits.** Build a Capacitor prototype by Week 2 to de-risk the timeline (a top `LAUNCH.md` risk is mobile slipping past Week 8).

---

### 5. Who builds mobile / who moderates (the 24h SLA)

**Decision (one line):** Who builds the mobile apps, and who staffs moderation — given the 24h review SLA is a real commitment, not just copy?

**Options:**
- **Build:** solo founder (unrealistic alongside backend), **2 contractors**, or a technical co-founder.
- **Moderate:** founder for the first weeks, then a **part-time bilingual contractor**; or hire the moderator up front.

**Key trade-off:** Solo build is not realistic on the 8-week path — backend is already the critical path. The 24h moderation SLA is more than a staffing line: it is a **brand promise we publish** ("report → human review within 24h"), and publishing a fixed SLA may itself create a commitment Perch can be held to (Part A Q11 flags this) — so it must be staffed *and* phrased deliberately, not treated as a pure staffing checkbox. It also must be bilingual (en/fr-CA) to serve Quebec users, and it needs a separate, faster escalation path for physical-safety reports (Part A Q11a) that the 24h content window does not cover.

**RECOMMENDATION: Don't build mobile solo — commit to 2 contractors (iOS + Android, parallel Weeks 2–8) or a technical co-founder. Founder moderates Weeks 1–4, then hire a part-time bilingual moderator by Week 4**, trained on the Community Guidelines + admin panel, with a dry-run before invites open. Treat the 24h SLA as a real ops commitment (it belongs in `OPS_RUNBOOK.md` with escalation paths), and have counsel confirm how to phrase the published commitment (Part A Q11) and how to handle emergency/assault reports distinctly from routine content (Part A Q11a).

**Blocks/unblocks:** Unblocks Phase 1–2 staffing and the moderation-SLA risk mitigation. A broken SLA at launch is a flagged medium/reputational risk.

**When:** **Phase 0** — start hiring Week 1; moderator onboarded **by Week 4** (before soft-launch invites).

---

### 6. Incorporation, entity name, and "Perch" trademark

**Decision (one line):** Incorporate the entity, fix its exact legal name (en + fr), and clear/confirm the "Perch" product name before store submission.

**Options:**
- **Quebec Inc.** vs **federal incorporation** (~$500–2k either way).
- **Keep "Perch"** (a working name) pending trademark clearance, or pick a final product name now.

**Key trade-off:** Incorporation is a prerequisite for a bank account, payment/IAP accounts, and vendor contracts, so it gates almost everything operational. "Perch" is only a working name — shipping to the stores under an uncleared mark risks a forced rename after launch. The legal placeholders (`LEGAL.company`, `LEGAL.email`, `LEGAL.effective` in `index.html` ~L1103) can't be replaced until the entity exists. Note that trademark clearance and the bilingual legal-name forms are **counsel work**, not just a founder to-do (Part A Q18a).

**RECOMMENDATION: Incorporate in Phase 0 (Quebec or federal — confirm with counsel/accountant), open the bank + store accounts, and run trademark clearance on "Perch" immediately (with counsel — Part A Q18a).** Keep the `LEGAL` placeholders in the demo until counsel finalizes the entity name (provide both en and fr legal forms, e.g. "Perch Technologies Inc." / "Technologies Perch inc."). Lock the final product name before store submission; if "Perch" doesn't clear, rename before Phase 3.

**Blocks/unblocks:** Unblocks bank account, Apple/Google developer accounts, IAP/payment setup, vendor DPAs, and replacing every legal placeholder. Blocks store submission under a final name.

**When:** **During Phase 0 (Weeks 1–2).** Trademark clearance must resolve **before Phase 3 store submission**.

---

### 7. SMS / OTP vendor

**Decision (one line):** Which vendor sends phone-verification codes for sign-in?

**Options:**
- **Twilio Verify** — mature OTP product, built-in fraud controls, strong Canada coverage and local numbers.
- **Telnyx** — cheaper per-SMS, less turnkey OTP/fraud tooling.
- **AWS (SNS/Pinpoint)** — fits if standardizing on AWS, more wiring.

**Key trade-off:** Twilio Verify is turnkey (handles OTP lifecycle, rate-limiting, and SMS-pumping fraud controls out of the box) at a modestly higher cost; Telnyx is cheaper but you own more of the fraud/abuse logic. SMS-pumping fraud is a real exposure on any open OTP endpoint.

**RECOMMENDATION: Twilio Verify at launch** — with strict server-side rate limiting and lockout/backoff to prevent SMS-pumping. Confirm message routing/residency with the vendor and sign a DPA. Re-evaluate Telnyx/AWS for cost at scale.

**Blocks/unblocks:** Unblocks the phone sign-in build (Phase 1, BACKEND §4) and feeds the residency confirmation and DPA list.

**When:** **Before Phase 1 starts** (end of Week 1) — create the test account now so the auth flow isn't blocked in Phase 1.

---

### 8. Build-vs-buy chat / realtime

**Decision (one line):** Do we build a socket server for chat / day-of / backfill, or buy managed realtime?

**Options:**
- **Buy — Supabase Realtime** (Postgres change feeds over WebSocket): chat, day-of statuses, and backfill offers ride the database we already run, no custom socket server.
- **Build — WebSocket + Redis** (~$40/mo): full control, but you own the socket infra, pooling, and scaling.

**Key trade-off:** Building a socket server is real, ongoing work against a deliberately lightweight ethos and a poor use of a two-person pre-PMF team. Buying collapses three realtime needs onto one datastore. The ceiling on managed realtime (typing indicators, presence at scale) is far above launch volume.

**RECOMMENDATION: Buy — Supabase Realtime.** Let `group_messages` / `day_of_statuses` / `backfill_offers` inserts fan out to subscribers via Postgres change feeds, scoped to channels the account is authorized for (active `group_memberships`). Reconsider building only if message volume or realtime features outgrow it. *(Note: `LAUNCH.md` lists Firestore as the MVP chat pick; both are "buy managed realtime." Standardize on Supabase Realtime to keep a single Postgres datastore consistent with BACKEND §2 — don't run two data backends.)*

**Blocks/unblocks:** Unblocks the realtime architecture for Phase 1 (chat, day-of, backfill) and keeps the stack to one primary datastore.

**When:** **Before Phase 1 backend starts** (Week 2).

---

### 9. Payment flow — pay-at-venue now vs upfront charge later

**Decision (one line):** Do we capture any card at launch, or stay pay-at-venue?

**Options:**
- **Pay-at-venue** (current invariant): no card captured; reservation stores only `{code, ticket, price}` and the member pays the venue on arrival showing the `PCH-XXXX` code.
- **Upfront charge** (anti-flake): capture a card via Stripe — reduces flaking but pulls Perch into PCI scope, adds processor onboarding, and triggers GST/QST + Quebec-compliant receipts.

**Key trade-off:** Upfront charging is a credible anti-flake lever but adds PCI scope, a payment processor, sales-tax registration, and refund/receipt machinery — a large surface for launch. Pay-at-venue keeps Perch out of PCI scope for tickets (we believe no card data is captured, so Perch stays out of PCI-DSS scope for tickets — to confirm with counsel/processor, Part A Q17) and honours the no-payments constraint, at the cost of relying on reliability scoring (not money) to fight flaking.

**RECOMMENDATION: Pay-at-venue at launch — no card captured for activity tickets.** Keep Perch out of PCI scope for tickets (we believe no card data is captured; confirm with counsel/processor); the `price` is a display string only. (Perch+ subscription is separate and goes through **Apple IAP / Google Play Billing** as merchant of record — mandatory for in-app digital subs. We **assume** the store collects/remits GST/QST on the subscription; confirm with counsel whether Perch has any residual Quebec sales-tax obligation — Part A §3.) Defer any upfront ticket charging to post-MVP (~Week 8–10+), and only with Stripe + GST/QST registration.

**Blocks/unblocks:** Unblocks Phase 2 scope (no card vault, no processor onboarding on the critical path) and the Terms refund language. Confirms the no-PCI-for-tickets launch posture (pending counsel/processor confirmation).

**When:** **Before Phase 2** (Week 4). Confirmed for launch; revisit upfront charging only post-MVP.

---

### 10. Group-formation cadence

**Decision (one line):** How do groups get formed at launch — fully automated matcher, or ops-assisted batch?

**Options:**
- **Ops-assisted batch matcher**: a scheduled greedy matcher (filter by neighbourhood → sort by reliability → form balanced 4–8 groups → assign to Perch Thursdays) whose output a human reviews before publishing. *(Group size 4–8 per BACKEND.md/CLAUDE.md; the demo and `LAUNCH.md` use 4–6 — final launch group size is an open product decision.)*
- **Fully automated** from day one — premature; the matcher is unproven at low density.
- **ML matching** — explicitly post-MVP.

**Key trade-off:** The matcher is the product's beating heart and the demo entirely fakes its `compat`/`mix` promise. At launch density (50–200 users) a clever automated matcher has too little data to tune and too much room to produce bad groups; a human reviewing each batch is cheap insurance against a broken first impression. ML matching is out of scope for weeks. Note also Part A Q8b: because the matcher groups people using their personal data (reliability + archetype), counsel should confirm whether Law 25's automated-decision-making disclosure applies and whether the human-in-the-loop batch review changes that.

**RECOMMENDATION: Start with a simple, scheduled batch matcher that mixes archetypes toward 4–8 per `activity_occurrence` (treat 4–6 vs 4–8 as an open product call), with a human reviewing the batch (e.g. Friday AM) before groups publish.** Instrument fill rate and show-up rate before investing in anything cleverer; the demo's `compat`/`mix` framing is a UI promise the matcher must earn over time.

**Blocks/unblocks:** Unblocks the matcher build (Phase 1, BACKEND §6 job #5) and the ops staffing for batch review (overlaps the moderator/ops hire in #5).

**When:** **Before Phase 1 matcher work** (Weeks 2–3); the first ops-assisted batch runs in Phase 4 (first Perch Thursdays).

---

*End of Part B. The three counsel-pending decisions (#1 age verification, #2 quiz-before-consent, #3 data residency) are the existential gate from `LAUNCH.md`'s TL;DR and map to Part A's Q1–Q3 — the founder makes the working call now, but onboarding cannot be finalized or shipped until counsel confirms. All other decisions are the founder's to lock in Phase 0. Keep the "not legal advice / templates pending attorney review" posture and the `LEGAL` placeholders until counsel finalizes the entity.*
