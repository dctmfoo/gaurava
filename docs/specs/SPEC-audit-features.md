# SPEC — Features Module Remediation (audit 2026-07-12)

**Status:** Ready
**Owner screens/logic:** `Gaurava/Features/` (all 11 files, ~10,467 lines), `Gaurava/Design/AppStyle.swift` (`weightText`), `Gaurava/Models/` (receives extracted logic)
**Docs this spec amends:** none (adds Models-level tests; onboarding work cites the behavior-preserving-refactor basis below)
**Branch:** `codex/audit-features`
**Issue:** file on this repo before starting (see `docs/specs/README.md`, Milestone 1)
**Source:** Opus module audit, 2026-07-12.

---

## 1. Problem

`Features/` holds ~50% of app source with zero unit tests, three god files (SettingsView 2,777 — which actually declares `CareView`; FirstRunSetupView 2,395; ResultsView 1,637), four copies of `ensureProfile()`, three weight-parsing paths, and one **Critical live defect**: the weight-unit preference does not convert anything.

## 2. Goals

- G1. Weight values are never displayed under a unit label they are not in.
- G2. One write service owns profile/preference resolution and all mutations, with surfaced errors.
- G3. Pure business logic moves to `Models/` and gains unit tests.
- G4. No Features file exceeds ~800 lines; filenames match their primary type.
- G5. Onboarding internals become testable with byte-identical behavior (DoD-ratchet safe).

## 3. Non-goals

- No visual/UX redesign of any screen; every refactor is behavior-preserving.
- No onboarding flow/copy/step-count change of any kind (gated by `docs/onboarding-definition-of-done.md`; this spec's onboarding work is an internal refactor, not a redesign — no DoD trigger required or claimed).
- No MVVM-ification for its own sake — extraction only where logic is currently untestable or duplicated.

## 4. Design decisions

### D1 — Fix the weight-unit defect (CRITICAL, C1)

**Contract grounding:** PRD G2, G4, and G8 plus §§7-8; DESIGN §§3-5, 8-9 where UI or copy is affected.
The Units picker persists `kg`/`lbs`/`stone` (`SettingsView.swift:2027-2030,601-608`) but every Features render goes through `weightText(_:)` (`AppStyle.swift:1333`) which hardcodes kg; `SummaryView.swift:386-395` even stamps the chosen unit label next to an unconverted kg number. Only `Sharing/` converts. **Decision:** introduce one `WeightUnit`/`WeightFormatter` model in `Models/` (kg↔lb↔stone; display, entry parsing, unit label, chart-axis values) and route ALL Features weight display and entry through it. Falling back to hiding the picker is rejected — conversion already exists in Sharing; unify it. Entry fields accept and store canonical kg internally regardless of display unit.

### D2 — Expand `ModelWriteService` (High, C2+C3)

**Contract grounding:** PRD G2, G4, and G8 plus §§7-8; DESIGN §§3-5, 8-9 where UI or copy is affected.
Four copies of `ensureProfile()` (`SummaryView.swift:288`, `JabsView.swift:255`, `SettingsView.swift:405`, inline in `ResultsView.swift:191-198`) and four `try? fetch(all).first(where: id)` edit/delete sites that swallow errors (`JabsView.swift:282,295`, `ResultsView.swift:169,180`). **Decision:** expand the existing `ModelWriteService` persistence choke point named by PRD §5.1; do not introduce a parallel `TrackerWriteService`. The expanded service owns profile/preference resolution and every mutation, uses predicate fetches for targeted updates/deletes, and returns results the views can surface. This preserves one write boundary for both feature behavior and the data-layer hardening in `SPEC-audit-data-layer.md`.

### D3 — Extract pure logic to `Models/` (Medium, C4+C5)

**Contract grounding:** PRD G2, G4, and G8 plus §§7-8; DESIGN §§3-5, 8-9 where UI or copy is affected.
Move and unit-test: Results stats engine (`resultStats`, `weeklyAverages`, `doseInfo`, `buildInsights`, BMI — currently duplicated twice), `ResultsChartScale` (already pure/static — the template), Jabs helpers (`weeksOnCurrentDose`, `weekNumber`, `isDoseChange`, `daysAgo`, `countdownDisplayText`), Summary metrics/trend selection, and consolidate: one `signedWeightText`, one weight parser (currently three), one set of day/week-delta helpers beside `TreatmentMath`.

### D4 — Split the god files (High/Medium)

**Contract grounding:** PRD G2, G4, and G8 plus §§7-8; DESIGN §§3-5, 8-9 where UI or copy is affected.
- `SettingsView.swift` → rename `CareView.swift` + extract `CareDataExport.swift` (exporter + 9 Codable records → `Models/` or `Import/`, gains a round-trip test), `CareSheets.swift` (~15 editor sheets), `CarePolicyViews.swift`, `CareModels.swift`.
- `ResultsView.swift` → `ResultsView` + `ResultsChart.swift` (~450 lines of Swift Charts) + `ResultsStatsModel` in `Models/`.
- `JabsView.swift` → `JabsView` + `InjectionSheets.swift`; shared `InjectionFormModel` for the identical add/edit forms.
- The schedule-anchor state machine duplicated between `TreatmentStatusSheet`/`saveTreatmentStatus` (`SettingsView.swift:841-968,536-576`) and `FirstRunSetupView.applyStatusContract` (`:1369`) collapses into one shared `ScheduleAnchorContract` in `Models/`.

### D5 — Onboarding internal refactor (High, gated-safe)

**Contract grounding:** PRD G2, G4, and G8 plus §§7-8; DESIGN §§3-5, 8-9 where UI or copy is affected.
`FirstRunSetupView` is a 1,457-line struct with 27 `@State` fields. **Decision:** extract `@Observable OnboardingFlowState` (fields + history/step/direction) and a pure `OnboardingCommitPlan` (`commit`, `applyStatusContract`, `materializeWeights`, `materializeLatestDose`, `isSatisfied`, `branchScreens`/`visibleScreens` — already near-pure statics); split sub-views into `OnboardingShell.swift`/`OnboardingScreens.swift`. Constraint: **`OnboardingDefinitionOfDoneTests` and the `branchStepCount`/`visibleStepCount` outputs stay byte-identical**; no screen, copy, or step change. This makes onboarding logic unit-testable without touching the gated UI.

### D6 — Localization convention pass (Medium, C6)

**Contract grounding:** PRD G2, G4, and G8 plus §§7-8; DESIGN §§3-5, 8-9 where UI or copy is affected.
No `String(localized:)` violations, but ~60 bare `Text("literal")`/`Button("…")`/string `title:` sites use the `LocalizedStringKey` path instead of `appLocalized(...)` — translated today, but a latent divergence risk and a CLAUDE.md convention violation (sites enumerated in the audit; notably the whole `CloudSyncStatusState` title/detail table, `SettingsView.swift:1033-1064` — verify those keys exist in the catalog). **Decision:** mechanical pass AFTER the structural splits; pair with the linter extension from `SPEC-audit-integration.md` D3 so the convention becomes enforced, not aspirational.

### D7 — Housekeeping (Low)

**Contract grounding:** PRD G2, G4, and G8 plus §§7-8; DESIGN §§3-5, 8-9 where UI or copy is affected.
Replace the two force-unwrapped URLs (`SettingsView.swift:1107-1108`); confirm-and-remove unused `SideEffectActionButton`/`SideEffectSummaryPill` (`SideEffectBoard.swift:165,191`); move `FlowLayout` (`LogView.swift:376-443`) to shared components; key `localizedAppAuthoredWeightNote` (`ResultsView.swift:1312`) off a stable note-token instead of English string-matching.

## 5. Edge cases

- D1: stone display is compound ("13 st 4 lb") — formatter must handle it plus entry parsing; rounding must round-trip (display → edit → save) without drift; chart axes and the goal ruler follow the display unit while storage stays kg.
- D2: not-found on edit/delete (record synced away) surfaces a calm message, not silence.
- D5: the extraction must not change `@State` initialization timing observable via the UI tests (FirstRunUITests, MedicationSelectionUITests must pass unmodified).

## 6. Accessibility & localization

- D1 adds unit-label strings (lb/st variants) → catalog + hi/ta/te translations.
- D6 is the localization pass itself; every touched key verified via `make localization-check`.

## 7. Test impact

New Models-level suites: `WeightUnitTests` (kg↔lb↔stone round-trips, compound stone, parsing), `ResultsStatsModelTests`, `TreatmentMath` additions, `ScheduleAnchorContractTests`, `OnboardingCommitPlanTests` (asserting identical inserts to today's fixtures), `ModelWriteServiceTests` (insert-vs-update, not-found), `CareDataExportTests` (round-trip). UI tests must pass unchanged throughout.

## 8. Acceptance criteria

1. Selecting lbs (or stone) converts every displayed weight, entry field, chart axis, and ruler in Features; `SummaryView` can never show a kg value under a non-kg label; storage remains canonical kg (unit tests + manual simulator pass).
2. Zero copies of `ensureProfile` outside `ModelWriteService`; no parallel write-service abstraction exists; all edits/deletes use predicate fetches and surface failures.
3. The extracted pure logic lives in `Models/` with green tests; duplicated helpers deleted.
4. `SettingsView.swift` no longer exists (renamed/split); no Features file > ~800 lines; build + full UI-test suite green.
5. `OnboardingDefinitionOfDoneTests` pass with unchanged baselines; onboarding renders pixel-identically.
6. Localization pass complete; `make localization-check` green; no bare-literal regressions once the linter extension lands.
7. `make agent-verify` green; one atomic commit per decision step.

## 9. Suggested implementation order

D1 (live defect, first) → D2 → D3 → D4 → D5 → D6 → D7. D1 and D2 are independent of the splits and ship immediately; the splits (D4/D5) land file-by-file, each with its extraction test.
