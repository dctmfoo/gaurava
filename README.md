# Gaurava

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20watchOS-blue.svg)](https://apps.apple.com/app/id6775155354)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%7C%20SwiftData%20%7C%20CloudKit-orange.svg)](https://developer.apple.com/xcode/swiftui/)

A shipped, App Store health-and-medication tracking app for GLP-1 treatment
journeys — built **end to end by AI coding agents** (OpenAI Codex and Claude
Code) working under an explicit, governed engineering contract.

**On the App Store:** https://apps.apple.com/app/id6775155354

Gaurava ("dignity, respect, weight") is a calm, private care journal: log your
weight, injections, doses, side-effects and mood; see your schedule and trend;
and keep it all on-device with iCloud sync. It ships an iPhone app, an Apple
Watch companion with complications, home-screen and watch widgets, App Intents,
Apple Health (HealthKit) weight import, and full Hindi / Tamil / Telugu
localization alongside English.

> This repository is a history-free public snapshot of the private product
> repo. All sample, preview, and test data is **fictional** — see
> [Synthetic data](#synthetic-data).

---

## Why this repo exists

Gaurava was designed, implemented, tested, localized, and shipped to the App
Store by coding agents operating as governed contributors, not by hand. The
repository is published as a real-world reference for **agent-built software at
product scale**: how a non-trivial multi-target Apple app (app + watch +
widgets + App Intents + CloudKit) can be produced by Codex and Claude Code when
they are held to a written operating contract, a TDD gate, and repeatable
verification commands.

The agent contract lives in [`AGENTS.md`](AGENTS.md) and
[`CLAUDE.md`](CLAUDE.md).

## Features

- **Treatment tracking** — weight history, injections/doses, titration, and a
  schedule engine that computes due / overdue / paused states from a single
  source of truth.
- **Log & mood** — per-day side-effect capture, mood, all-clear, and freeform
  notes.
- **Apple Watch app** — schedule + latest weight at a glance, plus watch
  complications and watch widgets that respect a privacy floor (never surface a
  value the owner chose to hide).
- **Home-screen widgets & App Intents** — quick glance and quick-add surfaces.
- **HealthKit import** — pull weight readings from Apple Health with provenance.
- **Local-first + CloudKit** — data lives on device and syncs privately via the
  user's own iCloud; no third-party backend.
- **Localization** — English, Hindi (hi), Tamil (ta), Telugu (te), with every
  in-app label switching through the app's own language picker.
- **Clinician export** — a shareable, structured summary for a care provider.

## Architecture

- **SwiftUI** app UI across iOS and watchOS targets.
- **SwiftData** persistence with a single `ModelWriteService` save choke point.
- **CloudKit** private-database sync (container `iCloud.com.nags.gaurava`).
- **TreatmentMath / TreatmentScheduleEngine** — pure, testable derivations
  shared by the app, widgets, and watch glance so every surface agrees.
- **WatchConnectivity** — a compact, privacy-aware snapshot transport to the
  watch.
- Targets: `Gaurava` (app), `GauravaWatch`, `GauravaWidgets`,
  `GauravaWatchWidgets`, `GauravaOnboarding`, plus `GauravaTests`,
  `GauravaUITests`, and `GauravaSurfaceSnapshots`.

The Xcode project is generated from [`project.yml`](project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen), so the source of truth is text.

## Building

Prerequisites: Xcode (with an iOS Simulator), `make`, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
# build and run the unit-test suite on a simulator (no signing / Apple account needed)
make test-unit
```

The repo ships a generated `Gaurava.xcodeproj`. If you change `project.yml`,
regenerate it with `xcodegen generate`.

Simulator builds require no code signing. **Signing is intentionally unset** in
the tracked files — to run on a physical device or archive, put your values in
an untracked `Makefile.local` at the repo root (picked up automatically,
gitignored — never committed):

```make
APPLE_TEAM_ID := XXXXXXXXXX      # your Apple Developer Team ID
```

One-off env vars work too (`APPLE_TEAM_ID=YOURTEAMID make ...`), or set
`DEVELOPMENT_TEAM` in `project.yml` and regenerate. The TestFlight/App Store
lanes additionally expect the maintainer's provisioning-profile UUIDs and App
Store Connect IDs in `Makefile.local` — forks distributing their own build
supply their own. Run `make` with no target to print the full list of commands.

## Agent governance

This project treats coding agents as contributors that must earn trust through
a repeatable gate rather than ad-hoc prompting:

- **A written operating contract** ([`AGENTS.md`](AGENTS.md) /
  [`CLAUDE.md`](CLAUDE.md)) — build/test commands, conventions, and guardrails
  the agent must follow.
- **Test-first correctness gate** — `make test-unit` for the fast loop; the full
  `make agent-verify` gate builds every target, runs unit + UI suites, and lints
  localization and screenshot policy before any handoff.
- **Dual-runtime parity** — the same contract drives both OpenAI Codex (incl.
  the Build iOS Apps plugin: simulator, SwiftUI previews, hot reload) and Claude
  Code, via mirrored hooks under [`.codex/`](.codex) and [`.claude/`](.claude).
- **Session-journal discipline** — a lightweight per-session log convention
  (published standalone at
  [dctmfoo/session-journal](https://github.com/dctmfoo/session-journal)) keeps a
  resumable trail of intent and decisions.

## Synthetic data

Every sample, preview, screenshot, and test fixture in this repository uses
**fictional** data — round placeholder weights, `verification@example.com`, and
generic device fixtures. No real personal health data is present. The medication
names the app tracks (e.g. tirzepatide, semaglutide) are the public GLP-1 drug
classes the product supports, not anyone's treatment record.

## Related work

Other agent-built projects by the same author:

- **[withful](https://github.com/dctmfoo/withful)** — shipped App Store app
  (family moments).
- **[intelli-expense](https://github.com/dctmfoo/intelli-expense)** — receipt /
  expense app with an agent write bridge.
- **[stepback](https://github.com/dctmfoo/stepback)** — coaching app with an
  agent write bridge.
- **[workspace-bootstrap](https://github.com/dctmfoo/workspace-bootstrap)** —
  the agent-governance pattern (running Codex and Claude Code in parity).

## License

[MIT](LICENSE) © 2026 dctmfoo
