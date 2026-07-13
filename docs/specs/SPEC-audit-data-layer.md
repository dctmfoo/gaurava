# SPEC — Data Layer Remediation (audit 2026-07-12)

**Status:** Ready
**Owner screens/logic:** `Gaurava/Persistence/`, `Gaurava/Import/`, `Gaurava/Models/` (DosePhaseMath, LogCapture, SampleData), `Gaurava/HealthKit/HealthKitWeightImporter.swift`
**Docs this spec amends:** none (adds persistence/import tests; records the schema-evolution procedure in PRD.md §data model when PRD lands)
**Branch:** `codex/audit-data-layer`
**Issue:** file on this repo before starting (see `docs/specs/README.md`, Milestone 3)
**Source:** Opus module audit, 2026-07-12.

Positive confirmations from the audit (no action): all 10 `@Model` classes are CloudKit-clean (every field optional/defaulted, zero unique constraints, zero relationships — deliberately flat with string source-IDs); container config correctly drops CloudKit for in-memory/sandbox; HealthKit dedup via `sourceHealthKitUUID` is the one cross-device-safe pattern.

---

## 1. Problem

The data layer is architecturally sound but carries three High-severity latent risks for a live CloudKit app — an unrecoverable launch `fatalError`, no schema-versioning/migration story, and a silent seed-idempotency hole — plus timezone/DST math defects and missing robustness tests.

## 2. Goals

- G1. Store-open failure never boot-loops the app.
- G2. An explicit, encoded schema-evolution procedure (versioned schema + append-only rule).
- G3. Seed import is idempotent for every record type regardless of which optional keys the payload carries.
- G4. Date/day math is calendar-correct across timezones and DST.
- G5. Dev-only fixtures do not ship in Release.

## 3. Non-goals

- No relationship-based remodel of the flat schema (the flat + source-ID design is deliberate and CloudKit-correct).
- No change to the HealthKit read-only import policy (deletion-ignoring is a documented tradeoff).
- Performance work on the O(n) upsert scans beyond adopting the existing single-fetch `Set` pattern where touched (owner-scale data; not a current bottleneck).

## 4. Design decisions

### D1 — Recoverable container creation (High, H1)

**Contract grounding:** PRD G5 and G6 plus §§5-6 and the relevant §8 engine contract.
`ModelContainerFactory.swift:15` `fatalError`s on any store-open failure — failed migration, CloudKit schema mismatch, corrupt store, disk pressure — a permanent boot loop with cloud-propagating stakes. **Decision:** catch, retry once with `cloudKitDatabase: .none` (local-only degraded mode), and if that fails surface a recoverable error state; never `fatalError` in Release.

### D2 — Versioned schema + migration plan (High, H2)

**Contract grounding:** PRD G5 and G6 plus §§5-6 and the relevant §8 engine contract.
No `VersionedSchema`/`SchemaMigrationPlan` exists; combined with D1 any non-additive model change is a latent boot loop, and CloudKit already forbids renames/deletes post-deploy. **Decision:** wrap `gauravaModelTypes` in a v1 `VersionedSchema` with a `SchemaMigrationPlan`, and record the binding rule (schema growth is append-only: new fields optional/defaulted; never rename/retype/delete a synced field) in PRD.md's data-model section once PRD exists.

### D3 — Close the nil-`clientMutationId` idempotency hole (High, H3)

**Contract grounding:** PRD G5 and G6 plus §§5-6 and the relevant §8 engine contract.
`SeedImporter.swift:152-179,226-234`: `SideEffectEntry`/`DailyCheckIn` dedup returns nil when `clientMutationId` is nil (both optional in the payload, no `legacyServerId` fallback) — such rows duplicate on every re-import. Current fixtures all populate the key, which is why tests pass. **Decision:** synthesize a deterministic fallback key (`logDate`+`symptom` / `logDate`, reusing `LogCapture.mutationId`) when the payload omits it.

### D4 — Import robustness policy (Medium, M3)

**Contract grounding:** PRD G5 and G6 plus §§5-6 and the relevant §8 engine contract.
One malformed record (missing `id`, absent `meta`, numeric-vs-string field) aborts the whole envelope decode, and the launch handler only `NSLog`s it — silent total loss. **Decision:** keep whole-envelope validation for `meta`, but decode records leniently (skip + count bad rows in the receipt/summary) and surface the outcome beyond NSLog. Add the malformed-JSON test matrix either way.

### D5 — Date-only seed parsing lands on the wrong local day (Medium, M2)

**Contract grounding:** PRD G5 and G6 plus §§5-6 and the relevant §8 engine contract.
`SeedImporter.swift:269-274` parses `yyyy-MM-dd` at UTC midnight; any negative-offset timezone reads it back as the previous local day via `isDate(_:inSameDayAs:)`. **Decision:** parse date-only values at the current calendar's `startOfDay` (documented), with round-trip tests in `America/*` and `Asia/Kolkata`.

### D6 — Calendar-based day math in DosePhaseMath (Medium, M4)

**Contract grounding:** PRD G5 and G6 plus §§5-6 and the relevant §8 engine contract.
`DosePhaseMath.swift:95,128-133` divides by 86,400s while the rest of the layer (TreatmentMath, schedule engine, reminder plan) uses `Calendar` arithmetic — DST drift and ±1-day truncation at margins, inherited by "N weeks on X mg" and `weeklyRateKg`. **Decision:** switch to `Calendar.dateComponents([.day])`; add a DST-spanning test.

### D7 — Gate dev fixtures out of Release (Medium, M5)

**Contract grounding:** PRD G5 and G6 plus §§5-6 and the relevant §8 engine contract.
`SampleData.swift:396-517`: `.preview`, `medicationVerificationSeed`, `verificationDoses` have no app-target release callers but compile into the shipping binary. The rest of the file (`DashboardSnapshot`) is production code and stays. **Decision:** `#if DEBUG` the three factories.

### D8 — CloudKit duplicate reconciliation (Medium, M1 — scheduled last)

**Contract grounding:** PRD G5 and G6 plus §§5-6 and the relevant §8 engine contract.
All dedup is local fetch-at-write; two devices creating the same logical row offline both survive the CloudKit merge, and `LogCapture.toggleSideEffect` deletes only `.first`, orphaning the twin. **Decision:** add a reconciliation pass on store load / remote-import that collapses rows sharing a stable key (`clientMutationId`, `legacyServerId`, `sourceHealthKitUUID`), keeping the earliest `createdAt`. This is the largest item; it lands after D1–D7 with its own two-context merge test.

### D9 — Hardening (Low)

**Contract grounding:** PRD G5 and G6 plus §§5-6 and the relevant §8 engine contract.
`@MainActor`-annotate (or thread-assert) `LogCapture`/`SeedImporter`/`ModelWriteService`; add `sideEffects`/`checkIns` to `SeedImportSummary`/receipt counts; prefer computed `sha256Hex(sourceData)` over caller-declared `meta.sha256`.

## 5. Edge cases

- Degraded local-only mode (D1 fallback) must not half-initialize surface producers; publish still works from local data.
- D3's synthesized keys must not collide with genuine `clientMutationId`s (namespace the fallback).
- D5 change must not shift days for already-imported historical records (parser change affects new imports only; receipts prevent re-import).
- D8 reconciliation must never delete rows with distinct stable keys, and must be idempotent itself.

## 6. Accessibility & localization

Only D4's surfaced import-failure state adds user-facing copy; route through `appLocalized(...)` + catalog.

## 7. Test impact

New: `PersistenceTests` (container CloudKit-off fallback; `ModelWriteService` save-failure returns false; `afterSave` fires once; `saveOrThrow` no-ops without changes). New import tests: 5 malformed-JSON cases; nil-`clientMutationId` double-import ⇒ exactly one row; `SeedDateParser` ISO8601 fractional/non-fractional/date-only/garbage/timezone matrix; checksum declared-vs-computed. Extend existing math suites: DST-spanning phase; zero-length phase; schedule-engine `-14/-15` boundary; reminder-plan spring-forward; `projectedNextInjectionDate` across a DST week; `progress` when goal > starting. D8: two-context concurrent-write merge test.

## 8. Acceptance criteria

1. A deliberately incompatible on-disk store launches into degraded local-only mode, not a crash (asserted by test).
2. Container builds through a v1 `VersionedSchema` + migration plan; append-only rule documented.
3. The nil-key double-import fixture yields exactly one `SideEffectEntry` and one `DailyCheckIn`.
4. Each malformed-input case has a deterministic asserted outcome and a user-visible (non-NSLog-only) failure signal.
5. Date-only seed values round-trip to the same calendar day in US and IST test zones.
6. DST-spanning `DosePhaseMathTests` pass; existing tests stay green.
7. Release binary contains no `.preview`/verification fixtures (`#if DEBUG` verified by release build).
8. (D8) The merge fixture ends with one logical row per stable key after reconciliation.
9. `make agent-verify` green throughout; one atomic commit per decision.

## 9. Suggested implementation order

D1 → D2 → D3 → D5 → D6 → D7 → D4 → D9 → D8 (reconciliation last; it depends on the stable-key guarantees of D3).
