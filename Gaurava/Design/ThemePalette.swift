import SwiftUI
import UIKit

// MARK: - Color primitives

/// One concrete color value (a single appearance face). Stored as raw sRGB
/// components so a palette is pure, `Sendable` data with no `UIColor` identity —
/// the `UIColor` is built on demand in `ColorSpec.color`. Integer literals are
/// read as `0xRRGGBB` hex, so most tokens read as `0x176D5D`.
struct ColorVariant: Sendable, Hashable, ExpressibleByIntegerLiteral {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0,
            alpha: alpha
        )
    }

    init(integerLiteral value: UInt) { self.init(hex: value) }

    init(shared face: SharedColorFace) {
        self.init(red: face.red, green: face.green, blue: face.blue, alpha: face.alpha)
    }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }

    /// Linear blend toward `other` by `t` (0 = self, 1 = other). Alpha blends too.
    func mix(_ other: ColorVariant, _ t: Double) -> ColorVariant {
        ColorVariant(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    func lighten(_ amount: Double) -> ColorVariant { mix(ColorVariant(red: 1, green: 1, blue: 1), amount) }
    func darken(_ amount: Double) -> ColorVariant { mix(ColorVariant(red: 0, green: 0, blue: 0), amount) }
    func opacity(_ a: Double) -> ColorVariant { ColorVariant(red: red, green: green, blue: blue, alpha: a) }
}

/// A semantic token's full appearance set: light + dark, each with an optional
/// high-contrast variant. `color` resolves the right face per render trait —
/// exactly the behaviour the app shipped before themes existed, now sourced from
/// the active palette instead of inline constants. Fields are `var` so a theme
/// can be derived from a base by overriding only the faces that differ.
struct ColorSpec: Sendable, Hashable {
    var light: ColorVariant
    var lightHighContrast: ColorVariant?
    var dark: ColorVariant
    var darkHighContrast: ColorVariant?

    init(
        light: ColorVariant,
        lightHighContrast: ColorVariant? = nil,
        dark: ColorVariant,
        darkHighContrast: ColorVariant? = nil
    ) {
        self.light = light
        self.lightHighContrast = lightHighContrast
        self.dark = dark
        self.darkHighContrast = darkHighContrast
    }

    init(shared token: SharedColorToken) {
        self.init(
            light: ColorVariant(shared: token.light),
            lightHighContrast: token.lightHighContrast.map(ColorVariant.init(shared:)),
            dark: ColorVariant(shared: token.dark),
            darkHighContrast: token.darkHighContrast.map(ColorVariant.init(shared:))
        )
    }

    /// A dynamic `Color` that picks light/dark (and high-contrast) per the render
    /// trait collection — the light/dark dimension stays a system trait; only
    /// *which palette* feeds it changes when the user switches theme.
    var color: Color {
        let light = self.light
        let lightHighContrast = self.lightHighContrast
        let dark = self.dark
        let darkHighContrast = self.darkHighContrast
        return Color(UIColor { traits in
            let prefersHighContrast = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return (prefersHighContrast ? (darkHighContrast ?? dark) : dark).uiColor
            }
            return (prefersHighContrast ? (lightHighContrast ?? light) : light).uiColor
        })
    }
}

/// Per-theme backdrop character. Editorial Ink carries a soft hero-zone wash;
/// Midnight Focus disables it for a flat OLED-black field.
struct Ambience: Sendable, Hashable {
    /// 0 = no wash. Multiplies the mesh opacities in `AmbientMeshWash`.
    var lightWash: Double
    var darkWash: Double
}

// MARK: - Structural knobs

/// The small structural vocabulary shared by the two approved themes. Feature
/// layouts remain fixed while the surface and backdrop recipes change.

/// The recipe `HealthCard` / `MetricTile` use for a quiet content surface.
enum CardStyle: Sendable, Hashable {
    case soft          // opaque fill + hairline border + two soft shadows (Editorial Ink)
    case voidElevated  // fill (elevated dark) + NO border + NO shadow — floats on a black void (Midnight)
}

/// The recipe the one hero surface per screen uses (`HeroCard`).
enum HeroStyle: Sendable, Hashable {
    case tintWash   // surface + soft identity wash + highlight border + shadow (Editorial Ink)
    case voidGlow   // dark borderless surface, faint accent glow, no shadow (Midnight)
}

/// The app backdrop treatment (`AppBackground`). The base page gradient still
/// comes from the mode-aware `pageBackground*` specs; this only picks the overlay.
enum BackdropStyle: Sendable, Hashable {
    case washMesh  // soft tinted mesh in the hero zone (Editorial Ink)
    case flat      // just the page gradient/solid (Midnight Focus)
}

/// A theme's complete structural identity. Bundled so `ThemePalette` carries one
/// `structure` field instead of four loose knobs, and so the default (= today)
/// lives in one place.
struct ThemeStructure: Sendable, Hashable {
    var card: CardStyle = .soft
    var hero: HeroStyle = .tintWash
    var backdrop: BackdropStyle = .washMesh

    static let standard = ThemeStructure()
}

// MARK: - Theme palette

/// A complete color theme: every semantic token's light + dark faces, plus the
/// backdrop ambience. A theme is a *full* design across both modes (the
/// System/Light/Dark *appearance* toggle just picks which face renders), so
/// switching theme restyles the whole app — surfaces, text, accents, and wash.
/// `AppTheme.<token>` resolves against the active palette, so adding/selecting a
/// theme touches no call site.
struct ThemePalette: Identifiable, Sendable, Hashable {
    var id: String
    var nameKey: String
    var ambience: Ambience
    /// Beyond-colour identity (surface/value/tile recipes). Defaults to today's
    /// look, so existing palette literals that omit it are unchanged.
    var structure: ThemeStructure = .standard

    // Surfaces & scaffolding
    var pageBackgroundTop: ColorSpec
    var pageBackgroundBottom: ColorSpec
    var healthSurface: ColorSpec
    var elevatedHealthSurface: ColorSpec
    var inputSurface: ColorSpec
    var glassSurface: ColorSpec
    var separator: ColorSpec
    // Text
    var textPrimary: ColorSpec
    var textSecondary: ColorSpec
    var textTertiary: ColorSpec
    // Semantic accents
    var healthPrimary: ColorSpec
    var success: ColorSpec
    var weight: ColorSpec
    var medication: ColorSpec
    var attention: ColorSpec
    var danger: ColorSpec
    var profile: ColorSpec
    // Dose ramp
    var doseStarter: ColorSpec
    var doseFive: ColorSpec
    var doseSevenFive: ColorSpec
    var doseTen: ColorSpec
    var doseTwelveFive: ColorSpec
    var doseFifteen: ColorSpec
    // Effects & chart
    var shadow: ColorSpec
    var cardHighlight: ColorSpec
    var actionSurface: ColorSpec
    var chartPlotSurface: ColorSpec
    var chartGrid: ColorSpec
    var accentForeground: ColorSpec
    // Mood valence ramp
    var moodRough: ColorSpec
    var moodLow: ColorSpec
    var moodOkay: ColorSpec
    var moodGood: ColorSpec
    var moodGreat: ColorSpec
}

// MARK: - Palette builder

/// The compact identity of a built theme. The builder (`ThemePalette.make`)
/// derives the full ~34-token palette from these anchors so each theme stays a
/// short, legible spec while remaining internally consistent. Hand-author a
/// palette directly (like `calmClinical`) when a theme needs bespoke tuning
/// (e.g. high-contrast variants).
struct PaletteSeed {
    // Light neutrals (page bg, card surface, elevated card, primary text)
    var lBg: UInt; var lSurface: UInt; var lElevated: UInt; var lText: UInt
    // Dark neutrals
    var dBg: UInt; var dSurface: UInt; var dElevated: UInt; var dText: UInt
    // Accents — light, dark
    var primaryL: UInt; var primaryD: UInt
    var successL: UInt; var successD: UInt
    var weightL: UInt; var weightD: UInt
    var medicationL: UInt; var medicationD: UInt
    var attentionL: UInt; var attentionD: UInt
    var dangerL: UInt; var dangerD: UInt
    // Backdrop wash intensity (0 = off)
    var lightWash: Double; var darkWash: Double
}

extension ThemePalette {
    static func sharedBrand(
        id: String,
        nameKey: String,
        ambience: Ambience,
        structure: ThemeStructure = .standard,
        tokens t: SharedThemeTokenSet = SharedThemeTokens.brand
    ) -> ThemePalette {
        ThemePalette(
            id: id,
            nameKey: nameKey,
            ambience: ambience,
            structure: structure,
            pageBackgroundTop: ColorSpec(shared: t.pageBackgroundTop),
            pageBackgroundBottom: ColorSpec(shared: t.pageBackgroundBottom),
            healthSurface: ColorSpec(shared: t.healthSurface),
            elevatedHealthSurface: ColorSpec(shared: t.elevatedHealthSurface),
            inputSurface: ColorSpec(shared: t.inputSurface),
            glassSurface: ColorSpec(shared: t.glassSurface),
            separator: ColorSpec(shared: t.separator),
            textPrimary: ColorSpec(shared: t.textPrimary),
            textSecondary: ColorSpec(shared: t.textSecondary),
            textTertiary: ColorSpec(shared: t.textTertiary),
            healthPrimary: ColorSpec(shared: t.healthPrimary),
            success: ColorSpec(shared: t.success),
            weight: ColorSpec(shared: t.weight),
            medication: ColorSpec(shared: t.medication),
            attention: ColorSpec(shared: t.attention),
            danger: ColorSpec(shared: t.danger),
            profile: ColorSpec(shared: t.profile),
            doseStarter: ColorSpec(shared: t.doseStarter),
            doseFive: ColorSpec(shared: t.doseFive),
            doseSevenFive: ColorSpec(shared: t.doseSevenFive),
            doseTen: ColorSpec(shared: t.doseTen),
            doseTwelveFive: ColorSpec(shared: t.doseTwelveFive),
            doseFifteen: ColorSpec(shared: t.doseFifteen),
            shadow: ColorSpec(shared: t.shadow),
            cardHighlight: ColorSpec(shared: t.cardHighlight),
            actionSurface: ColorSpec(shared: t.actionSurface),
            chartPlotSurface: ColorSpec(shared: t.chartPlotSurface),
            chartGrid: ColorSpec(shared: t.chartGrid),
            accentForeground: ColorSpec(shared: t.accentForeground),
            moodRough: ColorSpec(shared: t.moodRough),
            moodLow: ColorSpec(shared: t.moodLow),
            moodOkay: ColorSpec(shared: t.moodOkay),
            moodGood: ColorSpec(shared: t.moodGood),
            moodGreat: ColorSpec(shared: t.moodGreat)
        )
    }

    /// Build a full palette from a compact seed. Derivations:
    /// - text tiers dim toward the surface; surfaces step around the card tone;
    /// - hairlines/shadows are alpha overlays of text/black;
    /// - the mood ramp is a single-hue valence ramp from the primary;
    /// - the dose ramp maps to the theme's own accents (so it stays in-palette).
    static func make(id: String, nameKey: String, structure: ThemeStructure = .standard, _ s: PaletteSeed) -> ThemePalette {
        func pair(_ l: ColorVariant, _ d: ColorVariant) -> ColorSpec { ColorSpec(light: l, dark: d) }

        let lBg = ColorVariant(hex: s.lBg), lSurf = ColorVariant(hex: s.lSurface)
        let lElev = ColorVariant(hex: s.lElevated), lText = ColorVariant(hex: s.lText)
        let dBg = ColorVariant(hex: s.dBg), dSurf = ColorVariant(hex: s.dSurface)
        let dElev = ColorVariant(hex: s.dElevated), dText = ColorVariant(hex: s.dText)

        let primary = pair(ColorVariant(hex: s.primaryL), ColorVariant(hex: s.primaryD))
        let success = pair(ColorVariant(hex: s.successL), ColorVariant(hex: s.successD))
        let weight = pair(ColorVariant(hex: s.weightL), ColorVariant(hex: s.weightD))
        let medication = pair(ColorVariant(hex: s.medicationL), ColorVariant(hex: s.medicationD))
        let attention = pair(ColorVariant(hex: s.attentionL), ColorVariant(hex: s.attentionD))
        let danger = pair(ColorVariant(hex: s.dangerL), ColorVariant(hex: s.dangerD))
        let profile = pair(lText.mix(lSurf, 0.36), dText.mix(dSurf, 0.34))

        // Single-hue valence ramp from the theme primary down to a near-neutral.
        let neutralL = lText.mix(lSurf, 0.45), neutralD = dText.mix(dSurf, 0.45)
        let pL = ColorVariant(hex: s.primaryL), pD = ColorVariant(hex: s.primaryD)
        func mood(_ t: Double) -> ColorSpec { pair(pL.mix(neutralL, t), pD.mix(neutralD, t)) }

        return ThemePalette(
            id: id,
            nameKey: nameKey,
            ambience: Ambience(lightWash: s.lightWash, darkWash: s.darkWash),
            structure: structure,
            pageBackgroundTop: pair(lBg, dBg),
            pageBackgroundBottom: pair(lBg.darken(0.04), dBg.lighten(0.03)),
            healthSurface: pair(lSurf, dSurf),
            elevatedHealthSurface: pair(lElev, dElev),
            inputSurface: pair(lSurf.darken(0.03), dSurf.lighten(0.05)),
            glassSurface: pair(lSurf.lighten(0.01), dSurf.lighten(0.04)),
            separator: pair(lText.opacity(0.20), dText.opacity(0.16)),
            textPrimary: pair(lText, dText),
            textSecondary: pair(lText.mix(lSurf, 0.34), dText.mix(dSurf, 0.30)),
            textTertiary: pair(lText.mix(lSurf, 0.52), dText.mix(dSurf, 0.48)),
            healthPrimary: primary,
            success: success,
            weight: weight,
            medication: medication,
            attention: attention,
            danger: danger,
            profile: profile,
            // Dose ramp mapped to the theme's own accents — categorical but in-palette.
            doseStarter: profile,
            doseFive: medication,
            doseSevenFive: primary,
            doseTen: weight,
            doseTwelveFive: attention,
            doseFifteen: danger,
            shadow: pair(ColorVariant(red: 0.10, green: 0.10, blue: 0.10, alpha: 0.16),
                         ColorVariant(red: 0, green: 0, blue: 0, alpha: 0.36)),
            cardHighlight: pair(ColorVariant(red: 1, green: 1, blue: 1, alpha: 0.80), dText.opacity(0.12)),
            actionSurface: pair(lElev, dElev),
            chartPlotSurface: pair(lSurf, dSurf),
            chartGrid: pair(lText.opacity(0.22), dText.opacity(0.18)),
            accentForeground: pair(ColorVariant(red: 1, green: 1, blue: 1).mix(lSurf, 0.04), dBg),
            moodRough: mood(0.68),
            moodLow: mood(0.50),
            moodOkay: mood(0.32),
            moodGood: mood(0.15),
            moodGreat: pair(pL, pD)
        )
    }
}

// MARK: - Shipped palettes

extension ThemePalette {
    /// Editorial Ink & Bronze is the default shared brand across every surface.
    static let editorialInk = sharedBrand(
        id: "editorial-ink",
        nameKey: "Editorial Ink",
        ambience: Ambience(lightWash: 1.0, darkWash: 0.7)
    )

    /// C · Midnight Focus — a pure-black void, borderless surfaces, near-monochrome
    /// greys, and one electric mint reserved for the live element. Fixes the muddy
    /// warm dark directly. (Light face is a clean white-mono fallback.)
    static let midnightFocus = make(
        id: "midnight-focus", nameKey: "Midnight Focus",
        structure: ThemeStructure(card: .voidElevated, hero: .voidGlow, backdrop: .flat),
        PaletteSeed(
            lBg: 0xFFFFFF, lSurface: 0xFFFFFF, lElevated: 0xF1F2F4, lText: 0x0B0B0D,
            dBg: 0x000000, dSurface: 0x0D0D0F, dElevated: 0x161618, dText: 0xF4F4F7,
            // Lightness-only accessibility adjustment from the pre-reboot
            // #0E8F6A seed: #0A7D5C clears 4.5:1 on every light surface.
            primaryL: 0x0A7D5C, primaryD: 0x34E2B0,
            successL: 0x18895A, successD: 0x40DDA0,
            weightL: 0x2F6FBF, weightD: 0x5BB0F0,
            medicationL: 0xB5642E, medicationD: 0xE09A5E,
            attentionL: 0x9A7A1E, attentionD: 0xE0C05E,
            dangerL: 0xC04A40, dangerD: 0xF0867A,
            lightWash: 0.0, darkWash: 0.0))

    static let all: [ThemePalette] = [editorialInk, midnightFocus]
    static let byID: [String: ThemePalette] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static let defaultID = editorialInk.id
}

// MARK: - Selection

/// Process-wide in-app theme selection — a per-device override (like the language
/// switcher), persisted in `@AppStorage`. Reads are synchronous so `AppTheme`'s
/// token accessors can resolve a palette on the spot. Empty/unknown selection →
/// the default palette, so users who never touch the setting see no change.
enum AppThemeSelection {
    /// UserDefaults / `@AppStorage` key holding the chosen palette id, or "" for default.
    static let storageKey = "appThemeID"
    static let launchOverrideArgument = "--gaurava-theme-id"

    /// The explicitly chosen id, or "" when following the default.
    static var storedID: String {
        storedID(in: .standard)
    }

    /// The id actually in effect: the stored choice if it still maps to a shipped
    /// palette, else the default. Drives the picker checkmark and the Care row value.
    static var effectiveID: String {
        effectiveID(in: .standard)
    }

    static func storedID(in defaults: UserDefaults) -> String {
        defaults.string(forKey: storageKey) ?? ""
    }

    static func effectiveID(in defaults: UserDefaults) -> String {
        let stored = storedID(in: defaults)
        if !stored.isEmpty, ThemePalette.byID[stored] != nil { return stored }
        return ThemePalette.defaultID
    }

    /// The palette every `AppTheme.<token>` resolves against right now.
    static var currentPalette: ThemePalette {
        currentPalette(in: .standard)
    }

    static func currentPalette(in defaults: UserDefaults) -> ThemePalette {
        ThemePalette.byID[effectiveID(in: defaults)] ?? .editorialInk
    }

    /// Test/evidence hook for deterministic theme-matrix launches. Unknown ids are
    /// ignored so a typo cannot poison the persisted user selection.
    @discardableResult
    static func applyLaunchOverrideIfPresent(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let flagIndex = arguments.firstIndex(of: launchOverrideArgument),
              flagIndex + 1 < arguments.count else { return false }

        let candidate = arguments[flagIndex + 1]
        guard ThemePalette.byID[candidate] != nil else { return false }
        defaults.set(candidate, forKey: storageKey)
        return true
    }
}

// MARK: - Picker

/// The list of themes shown inside a `Menu`, as an inline checklist. Writing the
/// selection updates `@AppStorage`, which drives the root `.id` rebuild in
/// `AppRootView` so every `AppTheme.<token>` re-resolves against the new palette —
/// instant, no restart, mirroring the language switcher.
struct ThemePicker: View {
    @AppStorage(AppThemeSelection.storageKey) private var id: String = ""

    var body: some View {
        Picker(
            selection: Binding(
                get: { AppThemeSelection.effectiveID },
                set: { id = $0 }
            )
        ) {
            ForEach(ThemePalette.all) { palette in
                Text(appLocalized(palette.nameKey)).tag(palette.id)
            }
        } label: {
            Text(appLocalized("Theme"))
        }
        .pickerStyle(.inline)
    }
}
