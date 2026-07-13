# Localization — a localized screenshot is TWO layers

> Gaurava ships **en, hi (Hindi), ta (Tamil), te (Telugu)** — store locales
> `en-US, hi, ta-IN, te-IN`. The App Store keeps a **separate screenshot set per
> locale**, so localization is a real screenshot surface, not an afterthought.
> This doc is a brainstorming brief, not a fixed recipe — surface the options and
> open questions to the user.

A localized marketing screenshot has two independently-localized layers:

1. **In-phone UI** (the app itself) — already fully localized (`Localizable.xcstrings`
   = 384 strings across en/hi/ta/te, `InfoPlist.xcstrings`). Just capture per
   locale.
2. **Marketing overlay** (headline + sub-line + brand chip) — these live in the
   *deck generator*, NOT the app. They must be **transcreated** and rendered with
   a **script-capable display font**. This is where the real work is.

## Layer 1 — capture the app in each locale
The repo already forces a locale via launch arguments (see
`GauravaUITests/LocalizedScreenshotAuditUITests.swift`):

```swift
app.launchArguments += ["-AppleLanguages", "(hi)", "-AppleLocale", "hi_IN"]
// hi/hi_IN · ta/ta_IN · te/te_IN · en/en_US
```

Parameterize `MarketingScreenshotTests` by locale (loop the four codes), keeping
the **same seed** so every locale shows the identical journey. Save captures to
`assets/captures/<locale>/…`. Things to verify per locale:
- Number/date formatting (weight `84.3`, `DD/MM/YYYY`, dose `12.5 mg`) — the app
  formats these; just confirm they look right.
- Text expansion: Hindi/Tamil/Telugu strings are often **taller** and sometimes
  longer — check the cards don't clip (the localization audit test already emits
  visible labels for this).
- The dose-coloured chart, mascot-free UI, etc. are language-neutral.

## Layer 2 — the marketing overlay (the hard part)

### The font problem (decide this first)
**Lilita One (the Cooper-Black headline font) and Fredoka/Nunito are Latin-only —
they cannot render Devanagari, Tamil, or Telugu.** Picking the display font per
script is the central decision. Recommended candidate to test:

- **Baloo superfamily** (Google Fonts, OFL) — a chunky, rounded display family
  built script-by-script with a consistent personality, which keeps the retro
  rubberhose feel across languages:
  - Latin → `Baloo 2` (or keep Lilita One for en)
  - Devanagari (hi) → `Baloo 2`
  - Tamil (ta) → `Baloo Thambi 2`
  - Telugu (te) → `Baloo Tammudu 2`
- Alternatives: `Mukta` / `Hind` (Indian super-families, less "display"),
  `Noto Sans <script>` (safe but plain — last resort).

Download the per-script TTFs into `assets/fonts/` and map them per locale (the
generator now supports `HEADLINE_FONT_BY_LOCALE`, see `build_retro.py`). **Render
a one-word test in each script before committing** — chunky display fonts vary a
lot in how the squiggle underline and tracking sit on tall glyphs.

### Transcreate, don't translate
The headlines ("a little **lighter**", "in living **color**") are idioms — they
won't translate literally. Transcreate to keep **one idea, short, sentence-case,
one emphasis word**. Inputs:
- Approved glossary: `docs/localization-glossary.html`.
- Final listing copy (tone reference): `docs/app-store-listing-copy.html`
  (hi/ta/te drafts already exist but are **flagged "native review pending"** — a
  native speaker must sign off the headlines too).
- The emphasis word + squiggle still apply, but per-script line breaks and
  `line-height`/`letter-spacing` need re-tuning (Indic glyphs are taller; loosen
  leading, ease the negative tracking).

## Packaging options (brainstorm these with the user)
| Option | Per-locale work | Notes |
|---|---|---|
| **A. Full localized decks** | All slides × 4 locales | Best ASO; most transcreation + font work |
| **B. UI localized, English overlay** | Capture only | Cheap, but mixed-language reads as unfinished — avoid |
| **C. Hero + key slides localized, rest English** | 2–3 slides × 4 | Pragmatic middle ground |
| **D. English screenshots for all locales now** | none | Apple allows it; localize in a later pass |

The base `app-store-screenshots` editor supports this packaging natively:
`{locale}` in screenshot paths, **per-locale headline fields**, a `locales` array,
and an Export bundle that loops every locale × size. If you stay in the
standalone generator, emit one PNG set per locale into `out/<locale>/`.

## Open questions to raise
- **Style fit per market** — does the rubberhose mascot land in the Indian market,
  or does the calmer Set B (or a different accent) suit hi/ta/te better? Offer a
  per-locale style choice.
- **Font** — Baloo vs alternatives; needs a visual test render in each script.
- **Copy review** — who does the native-speaker pass on transcreated headlines?
- **Scope** — which option (A–D) and which slices (slides × locales).
- **RTL** — none of en/hi/ta/te are RTL, so no mirroring is needed (note it so a
  future Arabic/Urdu locale gets flagged for direction handling).
```
