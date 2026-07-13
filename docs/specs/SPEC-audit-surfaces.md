# SPEC — Surfaces Layer Remediation (audit 2026-07-12)

**Status:** Ready
**Owner screens/logic:** `Gaurava/SharedSurfaces/`, `Gaurava/Glance/`, `Gaurava/Watch/`, `Gaurava/LiveActivity/`, `GauravaWidgets/`, `GauravaWatch/`, `GauravaWatchWidgets/`
**Docs this spec amends:** `docs/widget-build-runbook.md` (complication-timeliness decision, if present; else record in this spec)
**Branch:** `codex/audit-surfaces`
**Issue:** file on this repo before starting (see `docs/specs/README.md`, Milestone 5)
**Related:** `SPEC-design-system-reboot.md` D6 (shared-token dependency completed there; this spec's D5 preserves the evidence)
**Source:** Opus module audit, 2026-07-12. No path was found where health data renders privacy-unshaped — the privacy architecture is sound.

---

## 1. Problem

The widget/watch/Live-Activity layer is well-architected (Foundation-only contract, producer-side privacy shaping, atomic writes) but has two High-severity robustness gaps: the schedule widget's countdown is frozen at publish time (wrong after midnight, and the 6h TTL collapses the widget to "Open to refresh" for most of the day), and the snapshot contract's promised "wrong-version decodes to nil" invariant is false — there is no schema-version gate.

## 2. Goals

- G1. The injection countdown is computed on-device and stays correct across midnight without the app running.
- G2. A real schema-version gate, with forward- and backward-compat fixture tests.
- G3. Live Activity start/update is race-free.
- G4. Surface theme tokens cannot drift from the app palette.

## 3. Non-goals

- No new widget families or complications.
- No change to the privacy-shaping model (`SurfacePrivacyMode` verified correct; `.full`-at-rest file protection is a documented tradeoff, restated in §5).
- Push-based Live Activity termination (app-driven end is acceptable for v1.x; L1 logged).

## 4. Design decisions

### D1 — Schema-version gate first (High, H2)

**Contract grounding:** PRD G1, G3, and G7 plus §§5.2 and 8.3; DESIGN §10 for cross-surface parity.
`GlanceSnapshotCodec.decode` (`SurfaceSnapshotStore.swift:28-34`) never inspects `schemaVersion`, though comments in four files promise wrong-version → nil. Forward-compat currently works only because all slices are optional; the first breaking bump would make an old widget process silently misrender clinical data (staged-rollout hazard: new app + old extension share the App Group file). **Decision:** after decoding, return nil when `schemaVersion` is outside `[minSupported...current]`; the producer never writes a payload it cannot decode back; correct the false comments. Do this before D2 — it de-risks every future contract change.

### D2 — Forward-compat fixture (Medium, M4/T1)

**Contract grounding:** PRD G1, G3, and G7 plus §§5.2 and 8.3; DESIGN §10 for cross-surface parity.
Add `Fixtures/glance-snapshot-vNext-extra-keys.json` (current shape + unknown keys + higher `schemaVersion`) asserting the D1 behavior; removing the version floor must fail the test. The existing v1 backward-compat fixture stays green.

### D3 — Live countdown (High, H1)

**Contract grounding:** PRD G1, G3, and G7 plus §§5.2 and 8.3; DESIGN §10 for cross-surface parity.
The snapshot bakes `daysUntilNextInjection`; the timeline emits one frozen entry (`CareGlanceWidget.swift:34-44`), so "Tomorrow" survives midnight, and past the 6h TTL (`GauravaSurface.swift:38`) every family shows the refresh placeholder — most of the day for a user who doesn't reopen the app. The absolute `nextInjectionDate` is already in the snapshot for `.full`/`.minimal` (`GlanceProjectionBuilder.swift:69,89`). **Decision:** providers emit one timeline entry per upcoming day boundary; `GlanceDisplayModel.make` computes `daysUntil` from `nextInjectionDate` relative to `entry.date` (falling back to the baked count only for `.redacted`, which correctly nils the date and keeps TTL expiry). TTL continues to guard clinical values (weight/dose), not the countdown. Same change in the watch widget provider (`GauravaWatchWidgetsBundle.swift:46-57`).

### D4 — Race-free Live Activity controller (Medium, M1)

**Contract grounding:** PRD G1, G3, and G7 plus §§5.2 and 8.3; DESIGN §10 for cross-surface parity.
`apply(_:)` is an unserialized free async function; concurrent publishes (rapid save + foreground) can both observe zero running activities and double-start (`InjectionActivityController.swift:34-40`). **Decision:** make the controller an actor (or a single serial `@MainActor` entry point) and extract the running-set decision into a pure testable function.

### D5 — Shared-token dependency satisfied by the design reboot (Medium, M3 complete)

**Contract grounding:** PRD G1, G3, and G7 plus §§5.2 and 8.3; DESIGN §10 for cross-surface parity.
The audit found four stale widget/watch dark tokens, a third hand-copied dose ramp, and no high-contrast parity. `SPEC-design-system-reboot.md` D6 subsequently resolved the complete dependency: `SharedThemeTokens.brand` is now the sole source for app, widget, watch, snapshots, and exports; the adapters consume it and parity/high-contrast tests guard it. **Decision:** no token implementation remains in this spec. Preserve and rerun the existing parity proof while changing Surfaces code; do not recreate mirrors or resync literals manually.

### D6 — Complication timeliness decision (Medium, M2)

**Contract grounding:** PRD G1, G3, and G7 plus §§5.2 and 8.3; DESIGN §10 for cross-surface parity.
The watch complication is fed by `updateApplicationContext` (opportunistic delivery), so dose-time refresh is best-effort. **Decision:** evaluate `transferCurrentComplicationUserInfo` for the injection-boundary push (daily-budget aware), keeping applicationContext as the latest-state baseline; record the decision either way so timeliness is a documented property, not an accident.

### D7 — Decomposition and polish (Low, L3/L4/L1)

**Contract grounding:** PRD G1, G3, and G7 plus §§5.2 and 8.3; DESIGN §10 for cross-surface parity.
Split `CareGlanceWidget.swift` (638 lines) into config/provider + home families + accessory families + `TrendChart.swift`; deduplicate `combinedWeightText` (`:265-268`,`:439-442`); log WCSession activation failures (`WatchConnectivityCoordinator.swift:47`); cache the App Group container URL (`SurfaceSnapshotStore.swift:89-94`); add launch/foreground reconciliation ending orphaned Live Activities past `windowEnd`.

## 5. Edge cases

- `.redacted` mode has no absolute date by design — countdown falls back to baked count + TTL expiry (existing behavior preserved).
- Day-boundary entries must respect the user's current calendar/timezone at render, incl. DST nights.
- Timeline entry count stays small (≤ a handful of day boundaries) to respect WidgetKit reload budgets.
- Restated tradeoff (L2): under owner-opt-in `.full` mode the App Group snapshot file holds absolute weight/dose at rest with first-unlock file protection — required for Lock Screen widgets; acceptable and now documented.

## 6. Accessibility & localization

No new user-facing strings expected (day-count phrasing already exists in the display model); any new phrase goes through the shared-surfaces snapshot vocabulary (SharedSurfaces is exempt from app-bundle localization by design — it follows system locale).

## 7. Test impact

- Version-floor decode test + vNext fixture (D1/D2).
- Display-model countdown matrix: fixed `nextInjectionDate`, varying `asOf` across midnight/DST ⇒ Today/Tomorrow/N with no republish (D3); timeline `reloadAt`/entry-generation test.
- Actor-based controller test: N concurrent `.active` applies against a fake store ⇒ exactly one start; end-on-`.inactive`; `.completed` dismissal (D4).
- Snapshot tests (`GauravaSurfaceSnapshots`) unchanged except where D7's split moves types (no rendering change).

## 8. Acceptance criteria

1. A payload with `schemaVersion` above the ceiling decodes to nil; the v1 fixture still decodes; the false comments are corrected.
2. The vNext fixture test fails if the version floor is removed.
3. Widget and watch complication show a correct countdown for ≥3 days without the app opening, flipping Today/Tomorrow at local midnight (display-model test + manual device check).
4. Concurrent-publish test yields exactly one Live Activity.
5. Existing shared-token parity and high-contrast tests remain green; no widget/watch token mirror is reintroduced.
6. Complication-timeliness decision recorded; if implemented, dose-time update verified on watch.
7. No file in `GauravaWidgets/` over ~250 lines after D7; snapshot tests green; `make agent-verify` green.

## 9. Suggested implementation order

D1 → D2 → D3 → D4 → D6 → D7, with the already-complete D5 parity proof rerun at checkpoints.
