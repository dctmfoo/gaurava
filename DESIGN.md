---
# ============================================================
# DESIGN.md — Gaurava (iOS/iPadOS/watchOS 26, SwiftUI)
# Binding machine-readable tokens plus design rules.
# Source of truth: shipped code and verified runtime behavior.
# ============================================================
name: Gaurava
platform: iOS + iPadOS + watchOS + WidgetKit + ActivityKit
minimum_os: "26.0"
ui_framework: SwiftUI
design_language: "Editorial Ink & Bronze — dignified private care rendered as warm paper, assured ink, and restrained bronze"

implementation_state:
  registry:
    count: 2
    source: Gaurava/Design/ThemePalette.swift
    ids: [editorial-ink, midnight-focus]
  default_theme: editorial-ink
  external_surfaces_theme: editorial-ink
  shared_token_source: Gaurava/SharedSurfaces/SharedThemeTokens.swift

colors:
  encoding: "Opaque colors are #RRGGBB sRGB. rgba(r,g,b,a) uses 0...255 sRGB channels; fractional channels in generated Midnight Focus values are binding."
  themes:
    editorial-ink:
      role: "Default brand palette across app, widgets, watch, share cards, and clinician exports."
      ambience: { light_wash: 1.0, dark_wash: 0.7 }
      structure: { card: soft, hero: tintWash, backdrop: washMesh }
      tokens:
        page_background_top:       { light: "#FAF6EE", light_high_contrast: "#F4EBDD", dark: "#161311", dark_high_contrast: "#0E0C0A" }
        page_background_bottom:    { light: "#F1E9DA", light_high_contrast: "#E8DDCB", dark: "#1D1915", dark_high_contrast: "#251F1A" }
        health_surface:            { light: "#FFFDF8", dark: "#241F1A" }
        elevated_health_surface:   { light: "#F5EFE3", light_high_contrast: "#EEE5D6", dark: "#2E2822", dark_high_contrast: "#393129" }
        input_surface:             { light: "#F6F1E6", light_high_contrast: "#EFE7D8", dark: "#2C2621", dark_high_contrast: "#373029" }
        glass_surface:             { light: "#FBF8F1", light_high_contrast: "#F4EDE1", dark: "#2B2620", dark_high_contrast: "#373029" }
        separator:                 { light: "rgba(28,24,19,0.22)", light_high_contrast: "rgba(28,24,19,0.34)", dark: "rgba(242,235,223,0.16)", dark_high_contrast: "rgba(242,235,223,0.28)" }
        text_primary:              { light: "#1C1814", dark: "#F2EBDF" }
        text_secondary:            { light: "#635B4E", light_high_contrast: "#4F473C", dark: "#B8AE9E", dark_high_contrast: "#D0C6B6" }
        text_tertiary:             { light: "#786F5F", light_high_contrast: "#635B4E", dark: "#93897A", dark_high_contrast: "#AEA392" }
        health_primary:            { light: "#7A5217", light_high_contrast: "#65420F", dark: "#D8A95E", dark_high_contrast: "#E7BD79" }
        success:                   { light: "#3E6B33", light_high_contrast: "#315A29", dark: "#9BC784", dark_high_contrast: "#B0D69B" }
        weight:                    { light: "#44608C", light_high_contrast: "#354E79", dark: "#9AB2D8", dark_high_contrast: "#B3C8E9" }
        medication:                { light: "#74406B", light_high_contrast: "#63345A", dark: "#CD93C3", dark_high_contrast: "#DEA9D5" }
        attention:                 { light: "#A64E1B", light_high_contrast: "#8D3E13", dark: "#E09A6C", dark_high_contrast: "#F0B18C" }
        danger:                    { light: "#9C3532", light_high_contrast: "#842825", dark: "#E08079", dark_high_contrast: "#F09B95" }
        profile:                   { light: "#635B4E", light_high_contrast: "#4F473C", dark: "#ABA192", dark_high_contrast: "#C2B7A6" }
        dose_starter:              { light: "#66604F", dark: "#ACA593" }
        dose_five:                 { light: "#9B4A28", dark: "#E09A76" }
        dose_seven_five:           { light: "#206455", dark: "#7CC9B2" }
        dose_ten:                  { light: "#2F5C9E", dark: "#97BBEA" }
        dose_twelve_five:          { light: "#806409", dark: "#DBB55E" }
        dose_fifteen:              { light: "#A03050", dark: "#E58BA4" }
        shadow:                    { light: "rgba(51,41,26,0.18)", dark: "rgba(0,0,0,0.34)" }
        card_highlight:            { light: "rgba(255,252,244,0.85)", dark: "rgba(242,235,223,0.14)" }
        action_surface:            { light: "#F5EFE3", light_high_contrast: "#EEE5D6", dark: "#2E2822", dark_high_contrast: "#393129" }
        chart_plot_surface:        { light: "#FFFDF8", light_high_contrast: "#FAF6EE", dark: "#2C2621", dark_high_contrast: "#373029" }
        chart_grid:                { light: "rgba(99,91,78,0.24)", light_high_contrast: "rgba(79,71,60,0.34)", dark: "rgba(184,174,158,0.20)", dark_high_contrast: "rgba(208,198,182,0.30)" }
        accent_foreground:         { light: "#FFFBF0", dark: "#1C1814" }
        mood_rough:                { light: "#99937F", dark: "#A29B88" }
        mood_low:                  { light: "#7F8A5E", dark: "#A9B285" }
        mood_okay:                 { light: "#5F7E4A", dark: "#8FBC77" }
        mood_good:                 { light: "#4A7139", dark: "#84C46E" }
        mood_great:                { light: "#3E6B33", dark: "#9BC784" }

    midnight-focus:
      role: "Approved alternate palette; pure-black OLED void, near-monochrome structure, and electric mint reserved for the live element."
      generated_by: ThemePalette.make
      ambience: { light_wash: 0.0, dark_wash: 0.0 }
      structure: { card: voidElevated, hero: voidGlow, backdrop: flat }
      seed:
        light: { background: "#FFFFFF", surface: "#FFFFFF", elevated: "#F1F2F4", text: "#0B0B0D" }
        dark: { background: "#000000", surface: "#0D0D0F", elevated: "#161618", text: "#F4F4F7" }
        accents:
          health_primary: { light: "#0A7D5C", dark: "#34E2B0" }
          success: { light: "#18895A", dark: "#40DDA0" }
          weight: { light: "#2F6FBF", dark: "#5BB0F0" }
          medication: { light: "#B5642E", dark: "#E09A5E" }
          attention: { light: "#9A7A1E", dark: "#E0C05E" }
          danger: { light: "#C04A40", dark: "#F0867A" }
      tokens:
        page_background_top:       { light: "#FFFFFF", dark: "#000000" }
        page_background_bottom:    { light: "rgba(244.8,244.8,244.8,1)", dark: "rgba(7.65,7.65,7.65,1)" }
        health_surface:            { light: "#FFFFFF", dark: "#0D0D0F" }
        elevated_health_surface:   { light: "#F1F2F4", dark: "#161618" }
        input_surface:             { light: "rgba(247.35,247.35,247.35,1)", dark: "rgba(25.1,25.1,27,1)" }
        glass_surface:             { light: "#FFFFFF", dark: "rgba(22.68,22.68,24.6,1)" }
        separator:                 { light: "rgba(11,11,13,0.20)", dark: "rgba(244,244,247,0.16)" }
        text_primary:              { light: "#0B0B0D", dark: "#F4F4F7" }
        text_secondary:            { light: "rgba(93.96,93.96,95.28,1)", dark: "rgba(174.7,174.7,177.4,1)" }
        text_tertiary:             { light: "rgba(137.88,137.88,138.84,1)", dark: "rgba(133.12,133.12,135.64,1)" }
        health_primary:            { light: "#0A7D5C", dark: "#34E2B0" }
        success:                   { light: "#18895A", dark: "#40DDA0" }
        weight:                    { light: "#2F6FBF", dark: "#5BB0F0" }
        medication:                { light: "#B5642E", dark: "#E09A5E" }
        attention:                 { light: "#9A7A1E", dark: "#E0C05E" }
        danger:                    { light: "#C04A40", dark: "#F0867A" }
        profile:                   { light: "rgba(98.84,98.84,100.12,1)", dark: "rgba(165.46,165.46,168.12,1)" }
        dose_starter:              { light: "rgba(98.84,98.84,100.12,1)", dark: "rgba(165.46,165.46,168.12,1)" }
        dose_five:                 { light: "#B5642E", dark: "#E09A5E" }
        dose_seven_five:           { light: "#0A7D5C", dark: "#34E2B0" }
        dose_ten:                  { light: "#2F6FBF", dark: "#5BB0F0" }
        dose_twelve_five:          { light: "#9A7A1E", dark: "#E0C05E" }
        dose_fifteen:              { light: "#C04A40", dark: "#F0867A" }
        shadow:                    { light: "rgba(25.5,25.5,25.5,0.16)", dark: "rgba(0,0,0,0.36)" }
        card_highlight:            { light: "rgba(255,255,255,0.80)", dark: "rgba(244,244,247,0.12)" }
        action_surface:            { light: "#F1F2F4", dark: "#161618" }
        chart_plot_surface:        { light: "#FFFFFF", dark: "#0D0D0F" }
        chart_grid:                { light: "rgba(11,11,13,0.22)", dark: "rgba(244,244,247,0.18)" }
        accent_foreground:         { light: "#FFFFFF", dark: "#000000" }
        mood_rough:                { light: "rgba(85.344,122.144,112.332,1)", dark: "rgba(111.874,167.554,153.288,1)" }
        mood_low:                  { light: "rgba(65.4,122.9,106.95,1)", dark: "rgba(96.025,183.025,159.3,1)" }
        mood_okay:                 { light: "rgba(45.456,123.656,101.568,1)", dark: "rgba(80.176,198.496,165.312,1)" }
        mood_good:                 { light: "rgba(26.62,124.37,96.485,1)", dark: "rgba(65.207,213.107,170.99,1)" }
        mood_great:                { light: "#0A7D5C", dark: "#34E2B0" }

typography:
  family: "New York system serif for display/editorial roles; SF Pro system sans for functional roles. Theme selection never changes type."
  rule: "Serif is reserved for display numerals, hero titles, and metric values. Never use serif below headline scale or for controls, labels, forms, settings rows, navigation, tab chrome, or body copy."
  roles:
    display:      { style: fixed_42, weight: semibold, design: serif, numerals: monospacedDigit }
    hero_title:   { style: title2, weight: bold, design: serif }
    card_title:   { style: headline, weight: semibold, design: default }
    metric_value: { style: title3, weight: semibold, design: serif, numerals: monospacedDigit }
    body:         { style: subheadline, weight: regular, design: default }
    body_strong:  { style: subheadline, weight: semibold, design: default }
    label:        { style: footnote, weight: semibold, design: default }
    micro:        { style: caption, weight: semibold, design: default }
  shrink_floors: { standard: 0.75, tight_numeric: 0.70 }

spacing:
  grid: "4/8-based"
  scale: { xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 24 }
  screen: { horizontal_inset: 16, top_inset: 12, bottom_clearance: 104, default_stack_gap: 16 }

shape:
  radius_scale: { control: 16, card: 22, hero: 28 }
  rule: "Exactly three custom rounded-rectangle radii with continuous corners. Capsules and circles are semantic shapes; compact chips may retain the 8pt exception."

icons:
  source: "SF Symbols through AppSymbol; raw symbol names in feature code are drift."
  size_scale: { chip: 10, small: 14, medium: 16, large: 18, seal: 34 }
  namespaces: [Tab, Health, Status, Action, Legal, Field, Insight]

elevation:
  editorial_ink:
    card: [{ color: "shadow@0.22", radius: 1.5, x: 0, y: 1 }, { color: "shadow@0.34", radius: 14, x: 0, y: 8 }]
    hero: [{ color: "shadow@0.25", radius: 2, x: 0, y: 1 }, { color: "identity_tint@0.16", radius: 22, x: 0, y: 12 }]
  midnight_focus:
    card: "No border or shadow; elevatedHealthSurface carries depth on the black void."
    hero: [{ color: "identity_tint@0.20", radius: 18, x: 0, y: 0 }]
  glass_budget:
    allowed: [QuickActionButton, SheetActionButton, system navigation chrome]
    content_cards: "Opaque; never glass."

motion:
  press: { scale: 0.97, opacity: 0.92, spring_response: 0.3, spring_damping: 0.9 }
  scroll_edge: { scale: 0.97, opacity: 0.72, interactive: true }
  numeric: "Use contentTransition(.numericText()) for changing measurements and counts."
  reduced_motion: "Settle immediately or use opacity-only behavior; never remove state information."

rules:
  accent_discipline: "Bronze is brand/care, green is success, blue is weight, plum is medication, orange is attention, and red is danger. Color reinforces meaning; it never replaces labels or symbols."
  editorial_posture: "Warm, assured, private, literate, and dignified. One hero per screen; supporting surfaces recede."
  weight_direction: "Never use danger/red to judge weight direction. Use the weight token and neutral language."
  dark_mode: "A token problem, not a layout problem. Appearance changes faces, never information architecture."
  theme_growth: "Exactly two themes ship. A new theme requires a Ready spec with a product trigger and a DESIGN.md amendment."
  anti_drift: "Any token, component-vocabulary, surface-parity, typography, or registry change amends DESIGN.md in the same change."
  localization: "Every in-app user-facing string uses the app localization helpers. Shared surfaces follow their separate-process localization contract."
---

# Gaurava — Editorial Ink & Bronze Design System

**Status:** Binding design contract for the shipped app and all companion surfaces.

**Audience:** Engineers and agents creating or reviewing Gaurava UI. `PRD.md` owns product behavior; this file owns visual, interaction, and voice coherence. Current source and verified runtime behavior remain first authority when implementation state is disputed.

## 1. Visual identity

Gaurava means dignity, respect, honor, importance, and weight. Editorial Ink & Bronze expresses that posture with warm paper, assured ink, restrained bronze, and an editorial serif used only where hierarchy can carry it. The app should feel like a private care journal shaped by a calm clinician: warm rather than sterile, literate rather than ornamental, and confident without becoming loud.

`editorial-ink` is the default everywhere, including widgets, watch, share cards, and clinician exports. `midnight-focus` is the only alternate: a deliberate OLED-black concentration mode with near-monochrome structure and electric mint for the live element. The registry is closed at these two themes.

## 2. Typography

`AppFont` is the vocabulary. New York system serif is restricted to `display`, `heroTitle`, and `metricValue`. Numeric display and metric roles use monospaced digits. `cardTitle`, body copy, labels, controls, forms, settings, navigation, and tab chrome remain SF Pro system sans.

There is no SF Pro Rounded design in the product. There is no feature-local typography system. A fixed 42pt display numeral is the single tokenized fixed-size role and must retain Dynamic Type scaling at its call site. Serif must never appear below headline scale; long localized copy and functional UI always remain sans for legibility.

## 3. Color and contrast

Use semantic roles, never visual guesses. Bronze (`healthPrimary`) is identity and primary action; green is success; blue is weight; plum is medication; orange is attention; red is destructive or safety-critical danger. Dose and mood ramps are named semantic contracts.

Editorial Ink carries bespoke Increased Contrast faces for scaffolding, text hierarchy, identity, state colors, and charts. Automated tests enforce WCAG 2.1 AA 4.5:1 for required text/action pairs. Dark mode and Increased Contrast change token faces only; feature layout must not branch to compensate for a palette.

Midnight Focus preserves its established structure and dark face. Its light brand seed is the sole pixel-identity exception: `#0E8F6A` moved lightness-only to `#0A7D5C` so brand text clears 4.5:1 on every light surface. The global typography contract still applies to both themes so the app remains one product rather than two unrelated skins.

## 4. Shared surfaces

`SharedThemeTokens.brand` is the sole brand-token source compiled into the app, WidgetKit extensions, watch app, watch widgets, share-card snapshot target, and fixed clinician export styling. App adapters resolve those values dynamically; separate processes intentionally render the Editorial Ink brand rather than the app's per-device alternate-theme selection.

Do not duplicate RGB literals into `WidgetTheme`, `WatchTheme`, snapshot rendering, or exports. Token-parity tests must fail if any shared surface drifts from the app default.

## 5. Components and layout

Preserve the established information architecture and component vocabulary: `AppScreen`, `AppBackground`, `HealthCard`, `MetricTile`, `HeroMetricCard`, `StatusPill`, `QuickActionButton`, `SheetActionButton`, and `AppTextFieldShell`. Build new UI from those roles before inventing a look-alike.

Hierarchy is compositional: one leading hero, balanced peer metrics, receding support cards, then section headers with editorial breathing room. Use the 4/8 spacing scale, leading/trailing layout, adaptive grids and stacks, and the three radius tokens. Shapes, glass, shadows, and accent color must support hierarchy rather than decorate empty space.

## 6. Structural theme contract

The structural vocabulary is intentionally small:

- Cards: `soft` for Editorial Ink, `voidElevated` for Midnight Focus.
- Heroes: `tintWash` for Editorial Ink, `voidGlow` for Midnight Focus.
- Backdrops: `washMesh` for Editorial Ink, `flat` for Midnight Focus.

There is no tile-style switch. Metric tiles use the shared card recipe with semantic content accents. Deleted theme branches, overlays, and palette-specific decorations must not return without a Ready spec.

## 7. Motion, glass, and accessibility

Motion confirms state; it does not entertain or pressure. Changing measurements use numeric transitions. Press feedback is brief and reduced-motion behavior settles immediately or uses opacity only. Haptics acknowledge deliberate actions and never dramatize health states.

Opaque surfaces are the reading layer. Glass is limited to quick actions, sheet actions, and system navigation chrome. Every state has text or symbol identity in addition to color, controls retain 44pt targets, VoiceOver reads complete meaning, and supported localization plus accessibility sizes must not clip or erase required information.

## 8. Voice and change control

Copy is calm, formal, precise, and nonjudgmental. Gaurava does not shame weight change, reward streaks, or imply surveillance. Medical uncertainty is stated plainly.

First-run onboarding remains structurally gated by `docs/onboarding-definition-of-done.md`; this reboot changes inherited tokens and fonts only under the recorded owner exception. Theme growth, typography changes, component-vocabulary changes, and shared-surface changes require a governing Ready spec and same-change updates to this contract.

## Changelog

- 2026-07-13 — Replaced Calm Clinical and the ten-theme audition registry with Editorial Ink & Bronze as the shared default plus Midnight Focus; adopted editorial serif display roles, bespoke high-contrast faces, shared-surface parity, and the collapsed structural vocabulary under `docs/specs/SPEC-design-system-reboot.md`.
