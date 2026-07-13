# Show the whole ecosystem — not just the app tabs

> The first run shipped only the 5 in-app tabs. Gaurava is a system-integrated
> app with widgets, Lock Screen accessories, Control Center controls, a Live
> Activity, and an Apple Watch app. **Leaving these out undersells the product.**
> At least one slide per deck MUST feature the ecosystem (the `kind:"ecosystem"`
> slide in `build_retro.py`). Consider two: one "works everywhere" overview and one
> Watch/Live-Activity hero.

## What exists in this repo (source of truth)
| Surface | Source | Families / presentations |
|---|---|---|
| **Home Screen widget** | `GauravaWidgets/CareGlanceWidget.swift` | systemSmall / systemMedium / systemLarge (+ systemExtraLarge on iPad) — read-only "next dose / weight" glance |
| **Lock Screen accessories** | `GauravaWidgets/CareGlanceWidget.swift` | accessoryInline / accessoryCircular / accessoryRectangular |
| **Interactive widget** | `GauravaWidgets/CareActionsWidget.swift` | systemMedium — Weight / Jab / Note quick actions (deep links) |
| **Control Center / Lock Screen / Action button** | `GauravaWidgets/GauravaControls.swift` | `ControlWidget`s (Open Log, etc.) |
| **Live Activity** | `GauravaWidgets/InjectionLiveActivity.swift` | Lock Screen card + Dynamic Island (compact / minimal / expanded) for injection day |
| **Apple Watch** | `GauravaWatch/WatchRootView.swift`, `GauravaWatchWidgets/` | watch glance screen + complications |

All read from the App-Group **glance snapshot** (`GauravaGlanceSnapshot` /
`GlanceDisplayModel`), so a seeded phone publishes data every surface can show.

Design references (concept boards, not real captures) live in
`docs/assets/widget-concepts/`: `home-ipad-board.png`, `home-family-board.png`,
`live-activity-board.png`, `lockscreen-accessory-board.png`,
`controls-interactive-board.png`. Use for layout ideas; prefer real captures.

## How to capture each (pick per surface; ask the user if unsure)

**A. Home Screen / Lock Screen widgets — recommended: SwiftUI snapshot test.**
The widget views are plain SwiftUI reading `GlanceDisplayModel`. Add a snapshot
test (or a tiny host) that builds a seeded `GauravaGlanceSnapshot`, renders the
widget body at the WidgetKit point size (systemSmall ≈ 158×158 @3x, systemMedium
≈ 338×158, accessoryRectangular ≈ 172×76, accessoryCircular ≈ 76×76) via
`ImageRenderer`, and writes a PNG. Deterministic and fast. *Live alternative:*
add the widget on a simulator Home/Lock Screen and `simctl io screenshot`, then
crop — slower and fiddlier to automate.

**B. Live Activity — render the presentation.** Snapshot `LockScreenView(state:)`
and the Dynamic Island expanded view from `InjectionLiveActivity.swift` with a
seeded `GauravaInjectionActivityAttributes.ContentState` via `ImageRenderer`.
*Live alternative:* start the activity from the seeded app (ActivityKit) and
screenshot the Lock Screen / long-press the Dynamic Island.

**C. Control Center control — snapshot** the `ControlWidgetButton` label, or mock
it as a retro sticker (a labelled rounded square) since controls are tiny.

**D. Apple Watch — run it.** `make watch-run` builds + launches `WatchRootView`
on a watchOS simulator; publish a seeded glance snapshot, then
`xcrun simctl io <watch-udid> screenshot`. Round the corners for the `watch()`
sticker. *Snapshot alternative:* render `WatchRootView(store:)` with a seeded
`WatchGlanceStore` via `ImageRenderer`.

## Composing the ecosystem slide
Drop the captures into `./surfaces/` and wire them into the `kind:"ecosystem"`
slide's `surfaces=[(image_b64, label, x, y, width, tilt), ...]`. Each renders as a
retro **sticker** (3px black border, hard `0 4px 0` offset shadow, a Fredoka
label). Good compositions:
- **"On every screen you own."** — a small Home-Screen widget, a Lock Screen with
  the accessory + Live Activity, and a Watch sticker, scattered with the mascot.
- **"Glance, don't open."** — the Live Activity / Dynamic Island hero + watch.
Keep each sticker legible at thumbnail size; 2–3 surfaces per slide max, one
allowed to bleed off-canvas.
