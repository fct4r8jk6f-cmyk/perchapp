---
name: check-i18n
description: Verify full en / fr-CA string parity in index.html after UI or copy changes. Use after adding, removing, or renaming any user-visible string.
---

Perch requires every user-visible string to ship in both English and Québec French. Verify parity in `index.html`:

1. **Key parity in `I18N`.** Extract the key sets of `I18N.en` and `I18N.fr` (each is one object literal inside `const I18N={...}`) and diff them. Every key must exist in both. Report keys present in one but not the other.

2. **`data-i18n` references resolve.** Collect every `data-i18n`, `data-i18n-attr`, and `t("key")` / `t('key')` usage and confirm each key exists in `I18N.en`. A missing key silently falls back to displaying the raw key name.

3. **Parallel data tables.** Data-driven content has separate fr tables — check that:
   - every key of `ARCH` has an entry in `ARFR`
   - every category in `CATS` has an entry in `CAT_FR`
   - `QFR` has the same length and option counts as `QUESTIONS`

4. **No hardcoded visible English** in render functions: scan recently changed template literals for user-facing English text not wrapped in `t()` or sourced from a translated table. (Ignore emoji, names, CSS classes, and aria-hidden content.)

Report findings as a short list: ✅ for clean checks, and for each problem the key/string and its line number. Fix only if the user asked for fixes; otherwise report.
