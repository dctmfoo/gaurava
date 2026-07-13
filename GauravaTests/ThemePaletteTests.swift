import XCTest
@testable import Gaurava

/// Guardrails for the theme registry. The headline test (`testStructuresAreUnique`)
/// encodes the codebase's explicit design philosophy — a theme must move STRUCTURE
/// (card/hero/backdrop), not just hue, or it "reads as one app under a coloured
/// gel" (see ThemePalette.swift). Adding a hue-only duplicate now fails the suite.
final class ThemePaletteTests: XCTestCase {
    private let defaultsSuiteName = "ThemePaletteTests.isolated"

    // MARK: Registry integrity

    func testRegistryIsNonEmptyAndIncludesDefault() {
        XCTAssertFalse(ThemePalette.all.isEmpty)
        XCTAssertNotNil(ThemePalette.byID[ThemePalette.defaultID],
                        "defaultID must resolve to a shipped palette")
    }

    func testIDsAreUnique() {
        let ids = ThemePalette.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Theme ids must be unique")
    }

    func testByIDMapsEveryTheme() {
        XCTAssertEqual(ThemePalette.byID.count, ThemePalette.all.count)
        for palette in ThemePalette.all {
            XCTAssertEqual(ThemePalette.byID[palette.id]?.id, palette.id)
        }
    }

    func testNameKeysAreNonEmpty() {
        for palette in ThemePalette.all {
            XCTAssertFalse(palette.nameKey.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(palette.id) has an empty nameKey")
        }
    }

    func testDefaultPaletteUsesEverySharedSurfaceToken() {
        let palette = ThemePalette.editorialInk
        let shared = SharedThemeTokens.brand
        let pairs: [(String, KeyPath<ThemePalette, ColorSpec>, KeyPath<SharedThemeTokenSet, SharedColorToken>)] = [
            ("pageBackgroundTop", \.pageBackgroundTop, \.pageBackgroundTop),
            ("pageBackgroundBottom", \.pageBackgroundBottom, \.pageBackgroundBottom),
            ("healthSurface", \.healthSurface, \.healthSurface),
            ("elevatedHealthSurface", \.elevatedHealthSurface, \.elevatedHealthSurface),
            ("inputSurface", \.inputSurface, \.inputSurface),
            ("glassSurface", \.glassSurface, \.glassSurface),
            ("separator", \.separator, \.separator),
            ("textPrimary", \.textPrimary, \.textPrimary),
            ("textSecondary", \.textSecondary, \.textSecondary),
            ("textTertiary", \.textTertiary, \.textTertiary),
            ("healthPrimary", \.healthPrimary, \.healthPrimary),
            ("success", \.success, \.success),
            ("weight", \.weight, \.weight),
            ("medication", \.medication, \.medication),
            ("attention", \.attention, \.attention),
            ("danger", \.danger, \.danger),
            ("profile", \.profile, \.profile),
            ("doseStarter", \.doseStarter, \.doseStarter),
            ("doseFive", \.doseFive, \.doseFive),
            ("doseSevenFive", \.doseSevenFive, \.doseSevenFive),
            ("doseTen", \.doseTen, \.doseTen),
            ("doseTwelveFive", \.doseTwelveFive, \.doseTwelveFive),
            ("doseFifteen", \.doseFifteen, \.doseFifteen),
            ("shadow", \.shadow, \.shadow),
            ("cardHighlight", \.cardHighlight, \.cardHighlight),
            ("actionSurface", \.actionSurface, \.actionSurface),
            ("chartPlotSurface", \.chartPlotSurface, \.chartPlotSurface),
            ("chartGrid", \.chartGrid, \.chartGrid),
            ("accentForeground", \.accentForeground, \.accentForeground),
            ("moodRough", \.moodRough, \.moodRough),
            ("moodLow", \.moodLow, \.moodLow),
            ("moodOkay", \.moodOkay, \.moodOkay),
            ("moodGood", \.moodGood, \.moodGood),
            ("moodGreat", \.moodGreat, \.moodGreat)
        ]

        for (name, paletteKeyPath, sharedKeyPath) in pairs {
            XCTAssertEqual(
                palette[keyPath: paletteKeyPath],
                ColorSpec(shared: shared[keyPath: sharedKeyPath]),
                "Default palette drifted from shared token \(name)"
            )
        }
    }

    func testRegistryIsExactlyTheTwoApprovedThemes() {
        XCTAssertEqual(ThemePalette.all.map(\.id), ["editorial-ink", "midnight-focus"])
        XCTAssertEqual(ThemePalette.defaultID, "editorial-ink")
    }

    // MARK: The anti-"gel" guardrail

    /// No two themes may share the same retained structure recipe. Distinct hue alone is
    /// not a distinct theme — the look has to move value structure / surface
    /// material / colour role. `ThemeStructure` is `Hashable`, so a `Set` proves it.
    func testStructuresAreUnique() {
        let structures = ThemePalette.all.map(\.structure)
        XCTAssertEqual(structures.count, Set(structures).count,
                       "Two themes share an identical card/hero/backdrop structure — "
                       + "give the new theme a distinct structure, not just a new hue.")
    }

    // MARK: Selection / fallback

    func testEffectiveIDFallsBackForEmptyAndUnknown() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        defaults.removeObject(forKey: AppThemeSelection.storageKey)
        XCTAssertEqual(AppThemeSelection.effectiveID(in: defaults), ThemePalette.defaultID,
                       "Empty selection must fall back to the default")

        defaults.set("not-a-real-theme", forKey: AppThemeSelection.storageKey)
        XCTAssertEqual(AppThemeSelection.effectiveID(in: defaults), ThemePalette.defaultID,
                       "Unknown selection must fall back to the default")

        let valid = "midnight-focus"
        defaults.set(valid, forKey: AppThemeSelection.storageKey)
        XCTAssertEqual(AppThemeSelection.effectiveID(in: defaults), valid,
                       "A valid stored id must be honoured")
        XCTAssertEqual(AppThemeSelection.currentPalette(in: defaults).id, valid)
    }

    func testLaunchOverrideAcceptsValidThemeID() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        defaults.removeObject(forKey: AppThemeSelection.storageKey)
        let accepted = AppThemeSelection.applyLaunchOverrideIfPresent(
            arguments: ["Gaurava", AppThemeSelection.launchOverrideArgument, "editorial-ink"],
            defaults: defaults
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(AppThemeSelection.effectiveID(in: defaults), "editorial-ink")
    }

    func testLaunchOverrideIgnoresUnknownThemeID() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        defaults.set("midnight-focus", forKey: AppThemeSelection.storageKey)
        let accepted = AppThemeSelection.applyLaunchOverrideIfPresent(
            arguments: ["Gaurava", AppThemeSelection.launchOverrideArgument, "not-a-real-theme"],
            defaults: defaults
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(AppThemeSelection.effectiveID(in: defaults), "midnight-focus")
    }

    // MARK: Editorial anchors and contrast

    func testEditorialInkBindingAnchors() {
        let palette = ThemePalette.editorialInk
        let expected: [(String, KeyPath<ThemePalette, ColorSpec>, UInt, UInt)] = [
            ("pageBackgroundTop", \.pageBackgroundTop, 0xFAF6EE, 0x161311),
            ("pageBackgroundBottom", \.pageBackgroundBottom, 0xF1E9DA, 0x1D1915),
            ("healthSurface", \.healthSurface, 0xFFFDF8, 0x241F1A),
            ("elevatedHealthSurface", \.elevatedHealthSurface, 0xF5EFE3, 0x2E2822),
            ("inputSurface", \.inputSurface, 0xF6F1E6, 0x2C2621),
            ("glassSurface", \.glassSurface, 0xFBF8F1, 0x2B2620),
            ("textPrimary", \.textPrimary, 0x1C1814, 0xF2EBDF),
            ("textSecondary", \.textSecondary, 0x635B4E, 0xB8AE9E),
            ("textTertiary", \.textTertiary, 0x786F5F, 0x93897A),
            ("healthPrimary", \.healthPrimary, 0x7A5217, 0xD8A95E),
            ("success", \.success, 0x3E6B33, 0x9BC784),
            ("weight", \.weight, 0x44608C, 0x9AB2D8),
            ("medication", \.medication, 0x74406B, 0xCD93C3),
            ("attention", \.attention, 0xA64E1B, 0xE09A6C),
            ("danger", \.danger, 0x9C3532, 0xE08079),
            ("profile", \.profile, 0x635B4E, 0xABA192),
            ("doseStarter", \.doseStarter, 0x66604F, 0xACA593),
            ("doseFive", \.doseFive, 0x9B4A28, 0xE09A76),
            ("doseSevenFive", \.doseSevenFive, 0x206455, 0x7CC9B2),
            ("doseTen", \.doseTen, 0x2F5C9E, 0x97BBEA),
            ("doseTwelveFive", \.doseTwelveFive, 0x806409, 0xDBB55E),
            ("doseFifteen", \.doseFifteen, 0xA03050, 0xE58BA4),
            ("accentForeground", \.accentForeground, 0xFFFBF0, 0x1C1814),
            ("moodGreat", \.moodGreat, 0x3E6B33, 0x9BC784)
        ]

        for (name, keyPath, light, dark) in expected {
            let token = palette[keyPath: keyPath]
            XCTAssertEqual(token.light, ColorVariant(hex: light), "Light anchor drifted: \(name)")
            XCTAssertEqual(token.dark, ColorVariant(hex: dark), "Dark anchor drifted: \(name)")
        }
    }

    func testTextAndStatusContrastAcrossApprovedThemesAndAppearances() {
        for palette in ThemePalette.all {
            for appearance in Appearance.allCases {
                let surfaces = [
                    palette.pageBackgroundTop,
                    palette.pageBackgroundBottom,
                    palette.healthSurface,
                    palette.elevatedHealthSurface,
                    palette.inputSurface
                ].map { appearance.face(of: $0) }

                for text in [palette.textPrimary, palette.textSecondary] {
                    for surface in surfaces {
                        assertContrast(
                            appearance.face(of: text),
                            surface,
                            minimum: 4.5,
                            context: "\(palette.id) \(appearance) text"
                        )
                    }
                }

                let baseSurface = appearance.face(of: palette.healthSurface)
                for status in [palette.success, palette.weight, palette.medication, palette.attention, palette.danger, palette.profile] {
                    let foreground = appearance.face(of: status)
                    let pillSurface = foreground.withAlpha(AppSurfaceRecipe.statusPillBackgroundOpacity).composited(over: baseSurface)
                    assertContrast(
                        foreground,
                        pillSurface,
                        minimum: 3,
                        context: "\(palette.id) \(appearance) status pill"
                    )
                }
            }
        }
    }

    func testBrandTextContrastAcrossApprovedThemesAndAppearances() {
        for palette in ThemePalette.all {
            for appearance in Appearance.allCases {
                let primary = appearance.face(of: palette.healthPrimary)
                let foreground = appearance.face(of: palette.accentForeground)
                assertContrast(foreground, primary, minimum: 4.5, context: "\(palette.id) action label")

                for surface in [palette.healthSurface, palette.elevatedHealthSurface, palette.inputSurface] {
                    assertContrast(
                        primary,
                        appearance.face(of: surface),
                        minimum: 4.5,
                        context: "\(palette.id) primary content"
                    )
                }
            }
        }
    }

    func testIntentionalEditorialSemanticAliasesShareOnePrimitive() {
        let tokens = SharedThemeTokens.brand
        XCTAssertEqual(tokens.elevatedHealthSurface, tokens.actionSurface)
        XCTAssertEqual(tokens.success, tokens.moodGreat)
    }

    private enum Appearance: CaseIterable, CustomStringConvertible {
        case light
        case lightHighContrast
        case dark
        case darkHighContrast

        var description: String {
            switch self {
            case .light: "light"
            case .lightHighContrast: "light high contrast"
            case .dark: "dark"
            case .darkHighContrast: "dark high contrast"
            }
        }

        func face(of spec: ColorSpec) -> ColorVariant {
            switch self {
            case .light: spec.light
            case .lightHighContrast: spec.lightHighContrast ?? spec.light
            case .dark: spec.dark
            case .darkHighContrast: spec.darkHighContrast ?? spec.dark
            }
        }
    }

    private func assertContrast(
        _ foreground: ColorVariant,
        _ background: ColorVariant,
        minimum: Double,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = foreground.contrastRatio(against: background)
        XCTAssertGreaterThanOrEqual(ratio, minimum, "\(context): \(ratio):1", file: file, line: line)
    }

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}

private extension ColorVariant {
    func withAlpha(_ alpha: Double) -> ColorVariant {
        ColorVariant(red: red, green: green, blue: blue, alpha: alpha)
    }

    func composited(over background: ColorVariant) -> ColorVariant {
        let outputAlpha = alpha + background.alpha * (1 - alpha)
        guard outputAlpha > 0 else { return self }
        return ColorVariant(
            red: (red * alpha + background.red * background.alpha * (1 - alpha)) / outputAlpha,
            green: (green * alpha + background.green * background.alpha * (1 - alpha)) / outputAlpha,
            blue: (blue * alpha + background.blue * background.alpha * (1 - alpha)) / outputAlpha,
            alpha: outputAlpha
        )
    }

    func contrastRatio(against other: ColorVariant) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    var relativeLuminance: Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(red)
            + 0.7152 * linearize(green)
            + 0.0722 * linearize(blue)
    }
}
