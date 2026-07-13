# AGENTS.md — Gaurava operating contract

This file is the operating contract for coding agents (OpenAI Codex, Claude
Code, or any other) working in this repository. It is deliberately short: build
and test commands, conventions, and guardrails. Keep it that way.

`CLAUDE.md` mirrors this file — edit both together.

## What this is

Gaurava is a SwiftUI / SwiftData / CloudKit health-and-medication tracking app
with iOS + watchOS targets, widgets, App Intents, HealthKit import, and
en/hi/ta/te localization. The Xcode project is generated from `project.yml`
via [XcodeGen](https://github.com/yonaskolb/XcodeGen). Do not hand-edit
`Gaurava.xcodeproj`; change `project.yml` and run `xcodegen generate`.

## Build & test commands

```sh
make               # print all available targets
make test-unit     # fast loop: build + unit tests (GauravaTests) on a simulator, no signing
make agent-verify  # full pre-handoff gate: build all targets + unit/UI tests + lint
xcodegen generate  # regenerate Gaurava.xcodeproj after editing project.yml
```

- Simulator builds need **no code signing**. Signing/team is intentionally
  unset in this repo — set `APPLE_TEAM_ID=YOURTEAMID` (or `DEVELOPMENT_TEAM` in
  `project.yml`) only when building for a device or archiving.
- `make agent-verify` is the correctness gate. Run it before declaring work
  done. It builds every target, runs unit + functional UI suites, and lints
  localization and screenshot policy.

## Conventions

- **Test-first.** Add or update tests with behavior changes; `make test-unit`
  must stay green. Warnings are errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`,
  strict concurrency).
- **Shared derivations.** Clinically meaningful math lives in `TreatmentMath`
  and `TreatmentScheduleEngine` so the app, widgets, and watch glance agree.
  Do not re-inline that logic per surface.
- **One save path.** All SwiftData writes go through `ModelWriteService`.
- **Localization.** Every user-facing string lives in an `.xcstrings` catalog
  and switches via the in-app language picker. Do not hardcode
  `String(localized:)` / `NSLocalizedString` in app UI (the localization lint
  enforces this). Languages: en, hi, ta, te.
- **Privacy floor on watch/widgets.** Never surface a value the owner chose to
  hide, even on a public watch face.
- **Synthetic data only.** All sample/preview/test fixtures must be fictional
  (round placeholder weights, `verification@example.com`). Never commit real
  personal health data.

## Dual-runtime parity & hooks

The same contract drives both Codex and Claude Code. Advisory hooks are mirrored
under `.codex/` and `.claude/` (session-start pointer, stop-time nudges, a
secrets guard). They are convenience only — nothing here depends on them to
build or test.

## Session-journal discipline

Non-trivial sessions keep a short journal of intent and decisions so work is
resumable. The standalone pattern is published at
[dctmfoo/session-journal](https://github.com/dctmfoo/session-journal).
