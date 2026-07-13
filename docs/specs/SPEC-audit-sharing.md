# SPEC — Sharing Module Remediation (audit 2026-07-12)

**Status:** Ready
**Owner screens/logic:** `Gaurava/Sharing/` (all 10 files); helper `Gaurava/Design/AppLanguage.swift`
**Docs this spec amends:** none (adds `GauravaTests/SharingExportTests.swift`)
**Branch:** `codex/audit-sharing`
**Issue:** file on this repo before starting (see `docs/specs/README.md`, Milestone 2)
**Source:** Opus module audit, 2026-07-12. Findings verified against code with file:line refs.

---

## 1. Problem

An audit of `Gaurava/Sharing/` (share cards + clinician export, ~2,605 lines) found three High-severity defects — a privacy-mode leak, a misleading clinician-document statement, and locale-inconsistent numerals in exports — plus duplicated rendering/dose logic and accounting gaps. Existing coverage (~12 tests inside `GauravaTests.swift`) misses all of them.

## 2. Goals

- G1. The "% only" privacy mode hides every absolute body metric on every template.
- G2. The clinician export never states a dose change that did not happen.
- G3. Exported dates AND numbers follow the in-app language consistently.
- G4. One rendering pipeline, one dose-timeline algorithm.
- G5. A dedicated `SharingExportTests` suite pinning all of the above.

## 3. Non-goals

- No visual redesign of card templates or the clinician document layout.
- No new share destinations or formats.
- PDF pagination (L1) is logged, not fixed here (single-page export is acceptable for v1.x; revisit if clinician feedback demands it).

## 4. Design decisions

### D1 — Close the privacy leak (High, H1)

**Contract grounding:** PRD G1 and G6 plus §8.5; DESIGN §§8-10 for voice, privacy, and export surfaces.
`ShareJourneyCardView.swift:148,167-170` renders exact BMI and `:155` exact dose regardless of `privacyMode`; the Story/Milestone templates always print the exact dose path (`ShareDosePathView`, `:340-345`). BMI back-solves to absolute weight; the "% only" control therefore does not do what it claims. **Decision:** in `.percentOnly`, suppress BMI entirely (no tile / "—") and hide exact mg doses across all three templates (dose path shows step count or relative progression only). Privacy shaping is applied at the snapshot/formatter layer (`ShareCardSnapshot`), not per-view, so a future template cannot re-leak.

### D2 — Fix the clinician dose-change window (High, H2)

**Contract grounding:** PRD G1 and G6 plus §8.5; DESIGN §§8-10 for voice, privacy, and export surfaces.
`ClinicianExport.swift:142-151` seeds `previousDose = nil` over period-filtered injections, so the first in-window injection always emits a "change" — a patient on 5 mg for months reads as titrated on the window's first injection date. **Decision:** seed from the most recent injection strictly before the period start; emit only true in-period deltas; render "N mg throughout this period" when there are none.

### D3 — Locale-pin export numerals (High, H3)

**Contract grounding:** PRD G1 and G6 plus §8.5; DESIGN §§8-10 for voice, privacy, and export surfaces.
Dates in exports go through `appFormatted(...)` pinned to `AppLocalization.effectiveLocale` (`AppLanguage.swift:147-149`), but 12 `.formatted(.number…)` sites (`ShareCardSnapshot.swift:177-250`, `ShareWeightTrendChart.swift:157,159`, `ShareJourneyCardView.swift:169`) use the system locale — mixed-locale documents when the in-app language differs from the system. **Decision:** add a locale-pinned number helper alongside the existing date helper and route all export numerics (weights, percents, BMI, chart axis) through it.

### D4 — Shared rendering layer (Medium, M1)

**Contract grounding:** PRD G1 and G6 plus §8.5; DESIGN §§8-10 for voice, privacy, and export surfaces.
`ShareCardRenderer.render` (`ShareCardRenderer.swift:12-54`) and `ClinicianExport.makeImage` (`ClinicianExport.swift:202-241`) duplicate the whole `ImageRenderer` pipeline and carry parallel error enums. **Decision:** extract `ShareImageRenderer.render(content:canvas:baseName:) -> ShareCardRenderedAsset` with one `ShareRenderError`; both call sites become thin.

### D5 — One dose timeline (Medium, M2 + Low L2)

**Contract grounding:** PRD G1 and G6 plus §8.5; DESIGN §§8-10 for voice, privacy, and export surfaces.
`ShareCardSnapshot.doseFor` (`:121-126`) and `ClinicianExport.activeDose` (`:163-172`) disagree on pre-first-injection dates (first-dose fallback vs nil); `makeDoseSteps`/`makeDoseChanges` are the same delta algorithm written twice. **Decision:** a single `DoseTimeline` helper with an explicit tested policy: dates before the first injection have **no** dose (no attribution of pre-treatment readings to a dose — L2), and both exports consume it.

### D6 — Accounting and lifecycle cleanups (Medium/Low)

**Contract grounding:** PRD G1 and G6 plus §8.5; DESIGN §§8-10 for voice, privacy, and export surfaces.
- **M4:** mood-only days (mood logged, `allClear == false`, no symptom/note) count in `loggedDayCount` so the clinician summary doesn't understate activity.
- **M3:** generate the clinician PDF lazily on tap; clean up temp export files on share-sheet dismissal (health images should not accumulate unbounded in tmp).
- **M5:** keep the weekly-average denominator (weeks since treatment start) but document the choice in code and DESIGN.md §voice — it is now a decision, not an accident.
- **L4:** zero loss renders "0.0", never "-0.0".
- **L5:** Photos-permission denial distinguishes denied/restricted and offers an open-Settings affordance.
- **L6:** memoize `ClinicianExportSheet.summary` and the composer's snapshot (`@State` + `task(id:)`) instead of recomputing per body evaluation.
- **L3:** make both `unexpectedSize` invariant strings non-localized (matching the documented debug-invariant rationale; removes 3 catalog entries).

## 5. Edge cases

- Privacy mode with zero weight entries: templates must degrade without leaking placeholders derived from absolutes.
- Period boundary: a capture exactly at `start` is included; one second before is excluded (test-pinned).
- `startingWeightKg == 0` falls back to first weight entry (existing behavior; keep + test).
- Duplicate symptoms in one day count once in `symptomTotals`.

## 6. Accessibility & localization

- New user-facing strings ("N mg throughout this period", Settings affordance, suppressed-BMI placeholder) go through `appLocalized(...)`; the implementing agent adds natural hi/ta/te translations in the same change using established glossary and catalog vocabulary.
- Removed: the localized `unexpectedSize` debug string (L3).

## 7. Test impact

New `GauravaTests/SharingExportTests.swift` (pure logic, no rendering); migrate the existing share/clinician tests out of `GauravaTests.swift`. Required cases (19, from the audit): dose-timeline policy incl. the H2 regression fixture; clinical-signal row filtering incl. mood-only days; period boundaries; pluralization; privacy-mode absolute-value suppression incl. BMI/dose (H1 regression); kg↔lb conversion; zero-loss sign; locale-pinned numeral formatting under a forced non-en locale (H3 regression); chart model extraction (`ShareChartModel`) for single-point/empty/percent-with-zero-start/segment-dose-attribution; configuration round-trips.

## 8. Acceptance criteria

1. A `.percentOnly` render of each of the three templates contains no absolute weight, BMI, or exact mg figure (unit-asserted at the snapshot/formatter layer).
2. The H2 fixture (stable pre-window dose, no in-window change) yields empty `doseChanges` plus a "throughout" line; an in-window titration lists exactly the true deltas.
3. With the in-app language forced to a non-system locale, every numeral in the share card and clinician export renders in `AppLocalization.effectiveLocale`.
4. `ImageRenderer` boilerplate exists in exactly one type; both exports use it; render smoke tests pass.
5. Share card and clinician export agree on active dose for identical fixtures; pre-first-injection dates carry no dose.
6. Mood-only days are counted; "-0.0" is impossible; PDF is generated only on demand; temp files are cleaned up after sharing.
7. `SharingExportTests` green; full `make agent-verify` green; localization catalog strict check green.

## 9. Suggested implementation order

1. D5 `DoseTimeline` + tests (pure logic, unblocks D2). 2. D2 clinician window fix. 3. D1 privacy shaping at snapshot layer. 4. D3 numeral helper + 12 call sites. 5. D4 renderer extraction. 6. D6 cleanups. Each step is one atomic commit with its tests.
