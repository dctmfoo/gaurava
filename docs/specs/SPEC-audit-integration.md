# SPEC — Integration & Tooling Remediation (audit 2026-07-12)

**Status:** Ready
**Owner screens/logic:** `Gaurava/App/`, `Gaurava/Import/OwnerSeedImportLaunchHandler.swift`, `Gaurava/Design/AppLanguage.swift`, `project.yml`, `Makefile`, `scripts/check_localization.py`, `scripts/device_install.sh`, `Gaurava/Info.plist`
**Docs this spec amends:** CLAUDE.md/AGENTS.md Localization section (linter scope note), once implemented
**Branch:** `codex/audit-integration`
**Issue:** file on this repo before starting (see `docs/specs/README.md`, Milestone 4)
**Source:** Opus module audit, 2026-07-12. Verified sound (no action): 64-notification cap avoided by single fixed identifier; provisional/denied permission handling; fingerprint dedup; deep-link validation; sandbox isolation; HealthKit usage strings; Debug/Release entitlement split; reminder reconcile fan-out.

---

## 1. Problem

The lifecycle layer is well-built, but the audit found one High defense-in-depth gap — the destructive data-reset launch path compiles into Release — plus four Medium issues: strict concurrency enforced only in `agent-verify` (not the archive path), two localization-gate holes, no way back to "follow system language," and deep links that can present a capture sheet over incomplete onboarding.

## 2. Goals

- G1. No destructive or test-only launch path exists in a Release binary.
- G2. Every build path (including archive) enforces the same strict-concurrency contract.
- G3. The localization gate catches missing catalog keys and bare `Text("literal")`.
- G4. Users can return to system-language following.
- G5. Deep links behave correctly during onboarding.

## 3. Non-goals

- No change to the `.id()` live language/theme switch mechanism itself (M5's state-loss tradeoff is documented, not redesigned).
- No notification-architecture changes (verified correct).
- Onboarding UI untouched (D5 gates routing around it, not the flow).

## 4. Design decisions

### D1 — Fence destructive launch paths out of Release (High, H1)

**Contract grounding:** PRD G1, G5, and G8 plus §§5, 9, and 10; DESIGN §8 where localized copy is affected.
`AppRootView.swift:101` calls `OwnerSeedImportLaunchHandler.runIfRequested` with no `#if DEBUG` (the adjacent `TestStateSeedLaunchHandler` IS gated). Its `--gaurava-reset-local-data-for-testing` branch (`OwnerSeedImportLaunchHandler.swift:16-44,86-103`) wipes every SwiftData model, and deletions propagate via CloudKit to the user's other devices — directly contradicting the CLAUDE.md invariant that the reset flag never touches the real app. Exploitability is low (launch args need debugger/MDM/physical access) but this is destructive, cloud-propagating code with no compile-time fence in a shipping medical-data binary. **Decision:** wrap the reset and appearance-mutation branches in `#if DEBUG`; keep only the non-destructive owner-seed import branch shippable if CloudKit schema bootstrap still needs it (decide at implementation; default: gate everything, since schema is already deployed to Production).

### D2 — Strict concurrency in every build path (Medium, M1)

**Contract grounding:** PRD G1, G5, and G8 plus §§5, 9, and 10; DESIGN §8 where localized copy is affected.
`project.yml:10` pins Swift 5.9 mode; `SWIFT_STRICT_CONCURRENCY=complete` + warnings-as-errors exist only in the Makefile build/test recipes (`Makefile:222-235`) — a plain Xcode build or the archive path (`Makefile:515-524`) verifies none of the layer's `Sendable`/`@MainActor` contract. **Decision:** move both settings into `project.yml` target settings; keep the Makefile flags as belt-and-suspenders.

### D3 — Close the remaining localization gate hole (Medium, M3; M2 satisfied)

**Contract grounding:** PRD G1, G5, and G8 plus §§5, 9, and 10; DESIGN §8 where localized copy is affected.
Process-contract implementation #14 already added strict catalog validation to `agent-verify`, satisfying M2: code keys missing from the catalog and untranslated supported-language values now fail the integrated gate. The remaining hole is M3: the linter's forbidden set does not cover bare `Text("literal")`/`Label("literal", …)`, so CLAUDE.md's ban remains unenforced (the Features audit found ~60 such sites). **Decision:** preserve the existing strict catalog gate and extend the linter with a bare-literal heuristic for app-UI files (SharedSurfaces exempt, `// i18n:allow` honored). Land the enforcement after the Features D6 cleanup so flipping it to fail does not strand the tree.

### D4 — Restore "follow system language" (Medium, M4 + L1)

**Contract grounding:** PRD G1, G5, and G8 plus §§5, 9, and 10; DESIGN §8 where localized copy is affected.
`LanguagePicker` (`AppLanguage.swift:155-176`) offers only concrete codes; once picked, the empty follow-system state (which the `effectiveCode` machinery fully supports) is unreachable, and the `AppleLanguages` mirror is never cleared. **Decision:** prepend a "System default" row that stores `""` and normalizes/clears the `AppleLanguages` mirror; validate codes against `supportedCodes` before writing the mirror.

### D5 — No capture sheet over onboarding (Medium, M6)

**Contract grounding:** PRD G1, G5, and G8 plus §§5, 9, and 10; DESIGN §8 where localized copy is affected.
The `presentLogCapture` sheet attaches to the outer content (`AppRootView.swift:74`), so `gaurava://log-symptom` or the log intent fired pre-setup presents `LogCaptureSheet` over `FirstRunSetupView` (other routes degrade silently). **Decision:** in `handle(_:)`/`routePendingDeepLink()`, defer the pending route (re-queue via `SurfaceNavigation.setPendingDeepLink`) while `showOnboarding` is true; honor it after completion.

### D6 — Hygiene (Low, M5/L2/L3/L4)

**Contract grounding:** PRD G1, G5, and G8 plus §§5, 9, and 10; DESIGN §8 where localized copy is affected.
- Document the `.id()` tree-rebuild state-loss tradeoff at `AppRootView.swift:70` (in-flight sheet state is lost on language/theme switch); optionally guard switching while a data-entry sheet is presented.
- Confirm whether CloudKit push actually requires the `remote-notification` background mode (`Info.plist:48-51`); no silent-push handler exists — remove the declaration if unused (App Review flag).
- Timezone-change reminder drift self-heals on next foreground; document the boundary in the reminder plan doc.
- `device_install.sh:39-40` skips xcodegen silently when absent — emit a stderr warning.

## 5. Edge cases

- D1: verify UI tests and the onboarding-sandbox flow (which legitimately use these flags in Debug) remain functional.
- D4: "System default" when the system language is unsupported falls back to en (existing `effectiveCode` behavior).
- D5: a deferred deep link must survive process death during onboarding (SurfaceNavigation's stored pending link already persists).

## 6. Accessibility & localization

New strings: the "System default" picker row (+ its translations). D3 itself is the enforcement mechanism for everything else.

## 7. Test impact

- D1: assertion that a Release-configuration build ignores the reset flag (unit-level guard test on the handler's gating, plus one manual archive-build check).
- D2: a deliberately-introduced concurrency violation fails the archive path (one-off verification during implementation).
- D3: retain the existing missing-catalog-key negative test from #14; add fixtures proving `agent-verify` fails on a bare `Text("literal")` while SharedSurfaces + `// i18n:allow` exemptions pass.
- D4: language round-trip test — pick a language, pick System default, `effectiveCode` returns to system-derived.
- D5: UI test — deep link before onboarding does not present the sheet; is honored after completion.

## 8. Acceptance criteria

1. A Release build with `--gaurava-reset-local-data-for-testing` performs no deletion; Debug behavior unchanged; UI-test suite green.
2. `xcodebuild archive` fails on a strict-concurrency violation; clean tree archives fine.
3. The existing strict catalog guard remains green and regression-tested; `make agent-verify` additionally fails on a bare `Text`/`Label` literal in app UI and passes on the post-Features-D6 tree.
4. "System default" is selectable and behaves per D4; `AppleLanguages` mirror validated/cleared.
5. Pre-onboarding deep links defer and fire post-onboarding.
6. Hygiene items landed or explicitly decided (background mode kept/removed with rationale).
7. One atomic commit per decision; `make agent-verify` green throughout.

## 9. Suggested implementation order

D1 (safety fence, first) → D2 → D4 → D5 → D6 → D3 enforcement after Features D6 cleanup. The strict catalog portion of D3 is already complete and must not be rebuilt.
