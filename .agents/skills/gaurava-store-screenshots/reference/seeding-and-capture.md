# Seed a realistic journey, then capture from the real running app

Screenshots must come from the **real app** seeded with believable data — never
hand-mocked UI. Gaurava seeds through its hidden owner-import launch path.

## 1. The seed launch path (already in the app)
`Gaurava/Import/OwnerSeedImportLaunchHandler.swift` reads, on launch:
- arg `--gaurava-reset-local-data-for-testing` → wipe every model in
  `gauravaModelTypes`, set the first-run flag so onboarding is skipped.
- arg `--gaurava-owner-seed-import` → import a seed envelope. The envelope is read
  from the base64 env var **`GAURAVA_OWNER_SEED_JSON_B64`** (preferred) or a file
  path after the arg.
- arg `--gaurava-open-url gaurava://<tab>` → deep-link to a tab on launch
  (`summary` | `jabs` | `results` | `log` | `care`).

The import runs in `.task` AFTER first render, so the UI updates reactively —
wait for seeded content (e.g. the hero weight string) before screenshotting.

## 2. Seed envelope shape
`SeedImportEnvelope` = `{ meta, account, data }`. `data` arrays (all decode-if-
present, numbers are **strings**, dates are ISO-8601):
`profiles, userPreferences, weightEntries, injections, treatmentPauses,
dailyLogs, dailyLogEntries, sideEffects, checkIns`.

- profile: `starting_weight_kg`, `goal_weight_kg`, `height_cm` (needed for BMI),
  `planned_dose_mg`, `treatment_start_date`, `preferred_injection_day`.
- injection: `dose_mg` ∈ {2.5,5,7.5,10,12.5,15}; `injection_site` ∈
  Abdomen/Thigh/Upper Arm × Left/Right (see `InjectionSiteRotation.allSites`).
- sideEffect: `symptom` ∈ {nausea,vomiting,constipation,diarrhea}; `severity` ∈
  {mild,moderate,severe}; dedupe key `client_mutation_id`.
- checkIn: `mood_valence` ∈ {rough,low,okay,good,great}; `all_clear` bool; `note`.

### Importer support for Log capture (verify it exists)
The Log "Recent" timeline reads `SideEffectEntry` + `DailyCheckIn`. The base
importer originally skipped these. The first run **added** import support
(`SeedSideEffect` / `SeedCheckIn` in `SeedImportPayload.swift`, upserts in
`SeedImporter.swift`, dedupe by `clientMutationId`). If you start from a branch
that lacks this, re-apply it (additive, backward-compatible) or the Log deck slide
will be empty.

## 3. A good 5-month journey (what reads as real)
- 98.0 → ~84.3 kg over ~22 weeks (−13.7 kg, ~76% to an 80 kg goal): a smooth,
  **decelerating** weekly curve, not linear.
- 22 weekly injections titrating 2.5→5→7.5→10→12.5 mg (every ~4 weeks), rotating
  through the 6 sites; dose-step notes ("Stepped up to 7.5 mg").
- Last jab 3 days ago → next due in 4 days ("On track").
- Side-effect/mood arc: nausea common early + after each step-up, mostly
  "all clear / good" later, with a few honest notes.
- Date everything relative to `Date()` so "today" / countdowns stay fresh.

`GauravaUITests/MarketingScreenshotTests.swift` (added in the first run) contains
a `MarketingSeed` builder that emits exactly this as base64 — reuse/extend it.

## 4. Capture (UI test → device-resolution PNGs)
The robust, repo-idiomatic path (mirrors `AdaptiveStatesScreenshotTests`):

```bash
UDID=$(xcrun simctl list devices available | grep "iPhone 17 Pro Max" | head -1 | grep -oE "[0-9A-F-]{36}")
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b
# clean status bar for marketing
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi

xcodegen generate   # if you added a new test file
RESULT="build/marketing-out/marketing-$(date +%H%M%S).xcresult"   # unique path; do NOT rm -rf
xcodebuild test -project Gaurava.xcodeproj -scheme Gaurava -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build/DerivedData/MARKETING \
  -only-testing:GauravaUITests/MarketingScreenshotTests \
  -resultBundlePath "$RESULT" -parallel-testing-enabled NO test

# extract attachments (let the bundle finalize first; retry if "Info.plist" error)
xcrun xcresulttool export attachments --path "$RESULT" --output-path captures/
xcrun simctl status_bar "$UDID" clear   # leave the sim clean
```

The test attaches `XCTAttachment(screenshot: app.screenshot())` (1320×2868,
`.keepAlways`) for each tab. `xcresulttool export attachments` writes friendly
names (rename from the `manifest.json`).

### Gotchas seen
- `rm -rf` of the result bundle is blocked by the sandbox — use a fresh
  timestamped `-resultBundlePath` instead of deleting.
- The xcresult must finish writing before `export attachments` works (an
  immediate call errors with "Info.plist does not exist"); retry once.
- `app.screenshot()` includes the status bar → the simctl override gives a clean
  9:41 / full battery.
- Capture extras (e.g. Results with the chart scrolled into view, the Log "Recent"
  timeline) so you have layout options per slide.
