---
name: gaurava-store-screenshots
description: >
  Produce Gaurava's App Store screenshots in the Retro Rubberhose Mascot style
  (cream/mustard/pink/mint, Cooper-Black headlines with a coral squiggle word,
  white-gloved can mascot, paper grain, REAL iPhone frame). Seeds a believable
  5-month GLP-1 journey into the simulator, captures the real app AND the
  ecosystem surfaces (widgets, Lock Screen, Control Center, Live Activity, Watch),
  then renders 1320x2868 review decks. Use when asked for App Store / marketing
  screenshots, store listing art, or a marketing deck for Gaurava. Wraps the
  base `app-store-screenshots` skill.
---

# Gaurava App Store screenshots (Retro Rubberhose)

This skill encodes a process that was figured out the hard way so you don't have
to rediscover it. Read this file, then the three `reference/` docs and the
`assets/` scaffold. **Surface options to the user with `AskUserQuestion` at the
decision points below — don't silently pick.**

## Surfaces & non-negotiables (these were the misses last time)

1. **Render a REAL iPhone, never a hand-drawn bezel.** A black rounded rectangle
   with a pill reads as an *Android* phone — a hard fail for an iOS listing. Use
   `assets/iphone-mockup.png` with the measured screen inset (already wired in
   `assets/build_retro.py`). Details + composition: `reference/iphone-frame.md`.

2. **Show the ecosystem, not just the 5 app tabs.** Gaurava has Home-Screen
   widgets, Lock Screen accessories, Control Center controls, a Live Activity, and
   an Apple Watch app. At least **one** ecosystem slide per deck is mandatory.
   Inventory + how to capture each: `reference/ecosystem-surfaces.md`.

3. **Localization is a surface, plan it — don't ignore it.** Gaurava ships
   **en / hi / ta / te** and the App Store keeps a screenshot set per locale. A
   localized shot has two layers: the in-phone UI (already localized — capture per
   locale) and the marketing overlay (headline/sub must be **transcreated** and
   rendered with a **script-capable display font** — Lilita One is Latin-only). This
   needs a packaging decision, not a default. Brief + options: `reference/localization.md`.

## Prerequisites (already installed in this repo)
- Base skill: `.agents/skills/app-store-screenshots/` — read its `SKILL.md` for
  the advertising-copy rules (one idea per slide, 3–5 words, narrative arc) and
  its `style-prompts/_QUALITY_BAR.md` + `style-prompts/01-retro-rubberhose-mascot.md`
  for the full visual spec. **Follow the quality bar's auto-reject checklist.**
- Fonts: download once into `assets/fonts/` — Lilita One (headline ≈ Cooper
  Black), Fredoka + Nunito (UI/body). Sources in `reference/seeding-and-capture.md`
  are not needed for fonts; fetch from the Google Fonts repo:
  `lilitaone/LilitaOne-Regular.ttf`, `fredoka/Fredoka[wdth,wght].ttf`,
  `nunito/Nunito[wght].ttf`.
- Tooling present: `xcodegen`, an `iPhone 17 Pro Max` simulator, headless Chrome
  (`/Applications/Google Chrome.app`), Python 3 + Pillow.

## Process

### Step 0 — Ask the user (use AskUserQuestion)
- **Style/direction:** confirm Retro Rubberhose, and whether to produce **2 review
  decks** (recommended: "A — playful, full-colour" vs "B — calm/brand-led,
  cream-dominant") or one.
- **Ecosystem coverage:** which surfaces to feature (widgets / Lock Screen / Live
  Activity / Watch / Control Center) and whether to capture them live or via
  SwiftUI snapshot rendering.
- **Devices:** iPhone 6.9" only or also iPad 13".
- **Localization (brainstorm — see `reference/localization.md`):** which of
  en/hi/ta/te to ship; the packaging option (A full localized decks · B UI-only ·
  C hero+key slides · D English-for-all-now); the headline display font per script
  (Lilita One can't render Indic — Baloo super-family is the candidate); and who
  does the native-speaker transcreation pass. Don't assume — these are real
  trade-offs the user should weigh.
Note that this is a big tonal shift for a *medical* app — offer the calmer Set B
so the user can compare.

### Step 1 — Seed + capture the app tabs
Follow `reference/seeding-and-capture.md`. Seed a ~5-month journey
(98 → ~84 kg, 22 jabs titrating 2.5→12.5 mg, dose-coloured trend, side-effect/mood
history) via `GAURAVA_OWNER_SEED_JSON_B64`, run `MarketingScreenshotTests`
(already in `GauravaUITests/`) on iPhone 17 Pro Max with a 9:41 status bar, and
extract the 1320×2868 PNGs into `assets/captures/`. **Verify** the importer seeds
`sideEffects` + `checkIns` or the Log slide will be empty. **For localized decks,**
re-run the same capture per locale by adding `-AppleLanguages "(hi)"` /
`-AppleLocale "hi_IN"` (etc.) to the test's launch args, saving to
`assets/captures/<locale>/` (`reference/localization.md`).

### Step 2 — Capture the ecosystem surfaces
Follow `reference/ecosystem-surfaces.md`. Render widgets / Lock Screen accessories
/ Live Activity / Watch (SwiftUI `ImageRenderer` snapshot tests are the most
reliable; live `simctl` capture is the alternative). Save to `assets/surfaces/`.

### Step 3 — Render the deck(s)
Use `assets/build_retro.py` (+ `assets/mascot.py`). Edit the palette, copy, slide
order, and the `kind:"ecosystem"` slide's `surfaces=[...]`. Narrative arc:
**Hero → Differentiator → Ecosystem → Core feature(s) → Trust/privacy closer.**
For localized decks, set each slide's `locale` + transcreated `lines`; the
generator picks the per-script headline font (`HEADLINE_FONT_BY_LOCALE`) and
writes to `out/<locale>/` — add the Baloo TTFs to `assets/fonts/` first.
Then render each emitted slide:
```bash
cd assets
python3 build_retro.py
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for f in out/*.html; do b=$(basename "$f" .html); \
  "$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1320,2868 --default-background-color=00000000 \
  --screenshot="out/$b.png" "file://$PWD/$f"; done
```
Build a downscaled contact sheet per deck (Pillow) for review.

### Step 4 — QA against the quality bar, then deliver
Run the base skill's `_QUALITY_BAR.md` auto-reject checklist. Then send the
contact sheets + a couple of full-res slides with `SendUserFile` and ask which
direction to refine. Iterate on copy/colour/mascot/layout. Final PNGs are the
1320×2868 files in `out/`.

## Copy that worked (starting points, edit freely)
Set A (playful): "Every week, a little **lighter**." · "Your trend, in living
**color**." (pair with the dose-coloured chart) · "On **every** screen you own."
(ecosystem) · "How you feel, in one **tap**." · "Yours. Only **yours**."
Set B (calm): "Track it with **dignity**." · "Five months. **Real** change." ·
"Glance, don't **open**." (ecosystem) · "Note it. Then let it **go**." ·
"Private by **design**."

## Pitfalls (all hit on the first run)
- **Android-looking phone** → use the iPhone mockup PNG (Req 1).
- **No ecosystem** → mandatory ecosystem slide (Req 2).
- **Invisible mascot** → hug the phone to one edge, stand the mascot in the
  opposite gutter overlapping the phone (`masc_left`/`masc_right`).
- **Question marks in headlines** → the quality bar forbids them; rephrase.
- **`rm -rf` of the xcresult is blocked** → use a fresh timestamped
  `-resultBundlePath`; never delete.
- **`xcresulttool export attachments` errors with "Info.plist does not exist"** →
  the bundle wasn't finalized; wait and retry.
- **Coral on mustard/pink** is ~4:1 (spec-approved) but verify; the rest of the
  headline stays dark brown `#2A2118`.
- **Don't fake an "App Store Featured" award** badge — it's a false claim. Use a
  neutral Gaurava brand chip.
- **Reset the sim status bar** (`simctl status_bar … clear`) when done.

## Artifacts from the first run (reference implementations)
- `GauravaUITests/MarketingScreenshotTests.swift` — seed builder + capture test.
- `Gaurava/Import/SeedImporter.swift` + `SeedImportPayload.swift` — Log-capture
  seed support (sideEffects / checkIns).
- The first decks (gitignored) lived in `scratch/marketing-retro/`.
