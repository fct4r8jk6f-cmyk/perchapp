# Perch — Legal Inventory

*A map of the legal text and placeholders in the demo, and what a Quebec privacy/tech lawyer needs to turn them into the real thing. See [LAUNCH.md](LAUNCH.md) for the full questions-for-counsel list.*

> ⚠️ **Not legal advice.** This is an engineering inventory to hand to counsel — it does not assert what the law requires. The in-app documents are **templates pending attorney review** (and say so in-app).

## 1. Placeholder constants

All live in one object in `index.html` (`const LEGAL = {...}`, ~line 1102) and are interpolated into the footer of every legal document (`openDoc`).

| Constant | Current placeholder | Replace with | Appears in |
|---|---|---|---|
| `LEGAL.company` | `[Legal Entity Name, Inc.]` | The incorporated entity's exact legal name (e.g. `Perch Technologies Inc.` / `Technologies Perch inc.`) | Footer of all 5 legal docs |
| `LEGAL.email` | `support@[yourdomain].com` | Real support/privacy contact address | Doc footers; also the Settings → Contact us flow |
| `LEGAL.effective` | `[Effective date]` | The effective date of the published Terms/Privacy (set at launch) | Doc footers |
| `LEGAL.appName` | `Perch` | — (not a placeholder; "Perch" is a working name — confirm the final product name before store submission) | Everywhere |

There are no other `[...]`-style placeholders in the codebase. The Settings → Email row shows a hardcoded demo `you@email.com` and the invite link uses `perch.app/...` — both are demo stand-ins, not legal placeholders, but should become real before launch.

## 2. The in-app legal documents

Five documents exist in full, in **both en and fr-CA** (`DOCS` / `DOCS_FR` in `index.html`). All are **template prose written for the demo** and must be replaced with attorney-reviewed versions.

| Doc key | Title (en) | Shown from | Needs counsel for |
|---|---|---|---|
| `terms` | Terms of Service (EULA) | Sign-in footer, Terms gate, Settings | IRL-meetup liability framing, age gate, refunds, dispute resolution, Apple/Google EULA requirements |
| `privacy` | Privacy Policy | Sign-in footer, Terms gate, Settings | **Quebec Law 25 + PIPEDA**: consent (incl. the pre-signin quiz), retention, access/deletion/portability rights, data residency, vendor DPAs |
| `guidelines` | Community Guidelines | Terms gate, Settings, chat safety sheet | Moderation rules, the 24-hour review SLA, appeals, no-show/safety policy |
| `moderation` | How moderation works | Settings | Accuracy of the human-first / no-public-voting / 24h claims as policy commitments |
| `wellbeing` | Wellbeing resources | Settings, chat safety sheet | Real local crisis/support lines for Montreal/Quebec; "not a crisis service" disclaimer |

## 3. Product facts that are legally relevant

- **18+ only.** Age stepper floors at 18; 18+ disclosed before the quiz. Age is **self-attested** — whether that's sufficient is the #1 question for counsel (see LAUNCH.md).
- **Quiz runs before sign-in / consent** (by design — it's the shareable acquisition artifact). The "consent before collection" question under Law 25 is open and may force a flow change.
- **No payments captured.** Reservations are **pay-at-venue**; the demo captures no card. Perch+ billing is simulated. Real payments (Stripe for ticketing, Apple/Google IAP for Perch+) bring PCI, tax (QST/GST), and refund obligations.
- **Identity verification is simulated** — the phone-code flow accepts any code; no real SMS/identity provider yet.
- **Safety posture** (first names + emoji before friendship, friends-only photos, private blocking, take-a-break, report → 24h review) is the brand. The 24h SLA is a **staffing commitment**, not just copy.
- **Account deletion** exists in-app (Settings → Delete account, framed as permanent) — Apple and Google both *require* in-app deletion; confirm the real backend honours a deletion SLA.
- **Bilingual obligation.** Quebec (Bill 96 / French-language requirements) — the app is fully en/fr-CA; confirm the legal docs and store listing meet French-first requirements with counsel.

## 4. Before launch — legal checklist

- [ ] Incorporate; set `LEGAL.company` to the exact legal name (en + fr forms).
- [ ] Stand up the real support/privacy email; set `LEGAL.email`.
- [ ] Attorney-drafted **Terms / Privacy / Community Guidelines** (replace the template prose in `DOCS`/`DOCS_FR`, both languages); set `LEGAL.effective`.
- [ ] Vendor **DPAs** (Twilio, Stripe, Firebase, email provider) per counsel.
- [ ] Resolve the **age-verification** and **quiz-before-consent** questions — they may change onboarding.
- [ ] Resolve **data residency** (Canada vs. US cloud).
- [ ] Real **wellbeing resources** (Quebec crisis lines) in the wellbeing doc.
- [ ] Apple **Privacy Nutrition Label** + Google **Data Safety** form, consistent with the Privacy Policy.
- [ ] Decide final product name (confirm "Perch" is clear of trademark conflicts).
- [ ] Document the deletion / breach / report SLAs and an incident-response plan.

*Keep the in-app "templates pending attorney review" flag until counsel signs off.*
