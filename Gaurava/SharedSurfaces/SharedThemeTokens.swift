struct SharedColorFace: Sendable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ hex: UInt, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xff) / 255
        green = Double((hex >> 8) & 0xff) / 255
        blue = Double(hex & 0xff) / 255
        self.alpha = alpha
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

struct SharedColorToken: Sendable, Hashable {
    let light: SharedColorFace
    let lightHighContrast: SharedColorFace?
    let dark: SharedColorFace
    let darkHighContrast: SharedColorFace?

    init(
        light: SharedColorFace,
        lightHighContrast: SharedColorFace? = nil,
        dark: SharedColorFace,
        darkHighContrast: SharedColorFace? = nil
    ) {
        self.light = light
        self.lightHighContrast = lightHighContrast
        self.dark = dark
        self.darkHighContrast = darkHighContrast
    }
}

struct SharedThemeTokenSet: Sendable, Hashable {
    let pageBackgroundTop: SharedColorToken
    let pageBackgroundBottom: SharedColorToken
    let healthSurface: SharedColorToken
    let elevatedHealthSurface: SharedColorToken
    let inputSurface: SharedColorToken
    let glassSurface: SharedColorToken
    let separator: SharedColorToken
    let textPrimary: SharedColorToken
    let textSecondary: SharedColorToken
    let textTertiary: SharedColorToken
    let healthPrimary: SharedColorToken
    let success: SharedColorToken
    let weight: SharedColorToken
    let medication: SharedColorToken
    let attention: SharedColorToken
    let danger: SharedColorToken
    let profile: SharedColorToken
    let doseStarter: SharedColorToken
    let doseFive: SharedColorToken
    let doseSevenFive: SharedColorToken
    let doseTen: SharedColorToken
    let doseTwelveFive: SharedColorToken
    let doseFifteen: SharedColorToken
    let shadow: SharedColorToken
    let cardHighlight: SharedColorToken
    let actionSurface: SharedColorToken
    let chartPlotSurface: SharedColorToken
    let chartGrid: SharedColorToken
    let accentForeground: SharedColorToken
    let moodRough: SharedColorToken
    let moodLow: SharedColorToken
    let moodOkay: SharedColorToken
    let moodGood: SharedColorToken
    let moodGreat: SharedColorToken
}

/// One import-clean brand-token source compiled into the app, widgets, and watch.
/// Separate-process surfaces intentionally use this default brand rather than the
/// app's per-device theme selection.
private enum EditorialPrimitive {
    static let paperTop = SharedColorToken(light: .init(0xFAF6EE), lightHighContrast: .init(0xF4EBDD), dark: .init(0x161311), darkHighContrast: .init(0x0E0C0A))
    static let paperBottom = SharedColorToken(light: .init(0xF1E9DA), lightHighContrast: .init(0xE8DDCB), dark: .init(0x1D1915), darkHighContrast: .init(0x251F1A))
    static let paper = SharedColorToken(light: .init(0xFFFDF8), dark: .init(0x241F1A))
    static let paperElevated = SharedColorToken(light: .init(0xF5EFE3), lightHighContrast: .init(0xEEE5D6), dark: .init(0x2E2822), darkHighContrast: .init(0x393129))
    static let paperInput = SharedColorToken(light: .init(0xF6F1E6), lightHighContrast: .init(0xEFE7D8), dark: .init(0x2C2621), darkHighContrast: .init(0x373029))
    static let paperGlass = SharedColorToken(light: .init(0xFBF8F1), lightHighContrast: .init(0xF4EDE1), dark: .init(0x2B2620), darkHighContrast: .init(0x373029))
    static let inkSeparator = SharedColorToken(light: .init(0x1C1813, alpha: 0.22), lightHighContrast: .init(0x1C1813, alpha: 0.34), dark: .init(0xF2EBDF, alpha: 0.16), darkHighContrast: .init(0xF2EBDF, alpha: 0.28))
    static let ink = SharedColorToken(light: .init(0x1C1814), dark: .init(0xF2EBDF))
    static let inkSecondary = SharedColorToken(light: .init(0x635B4E), lightHighContrast: .init(0x4F473C), dark: .init(0xB8AE9E), darkHighContrast: .init(0xD0C6B6))
    static let inkTertiary = SharedColorToken(light: .init(0x786F5F), lightHighContrast: .init(0x635B4E), dark: .init(0x93897A), darkHighContrast: .init(0xAEA392))
    static let bronze = SharedColorToken(light: .init(0x7A5217), lightHighContrast: .init(0x65420F), dark: .init(0xD8A95E), darkHighContrast: .init(0xE7BD79))
    static let moss = SharedColorToken(light: .init(0x3E6B33), lightHighContrast: .init(0x315A29), dark: .init(0x9BC784), darkHighContrast: .init(0xB0D69B))
    static let slate = SharedColorToken(light: .init(0x44608C), lightHighContrast: .init(0x354E79), dark: .init(0x9AB2D8), darkHighContrast: .init(0xB3C8E9))
    static let plum = SharedColorToken(light: .init(0x74406B), lightHighContrast: .init(0x63345A), dark: .init(0xCD93C3), darkHighContrast: .init(0xDEA9D5))
    static let orange = SharedColorToken(light: .init(0xA64E1B), lightHighContrast: .init(0x8D3E13), dark: .init(0xE09A6C), darkHighContrast: .init(0xF0B18C))
    static let red = SharedColorToken(light: .init(0x9C3532), lightHighContrast: .init(0x842825), dark: .init(0xE08079), darkHighContrast: .init(0xF09B95))
    static let profile = SharedColorToken(light: .init(0x635B4E), lightHighContrast: .init(0x4F473C), dark: .init(0xABA192), darkHighContrast: .init(0xC2B7A6))
    static let doseStarter = SharedColorToken(light: .init(0x66604F), dark: .init(0xACA593))
    static let doseFive = SharedColorToken(light: .init(0x9B4A28), dark: .init(0xE09A76))
    static let doseSevenFive = SharedColorToken(light: .init(0x206455), dark: .init(0x7CC9B2))
    static let doseTen = SharedColorToken(light: .init(0x2F5C9E), dark: .init(0x97BBEA))
    static let doseTwelveFive = SharedColorToken(light: .init(0x806409), dark: .init(0xDBB55E))
    static let doseFifteen = SharedColorToken(light: .init(0xA03050), dark: .init(0xE58BA4))
    static let shadow = SharedColorToken(light: .init(0x33291A, alpha: 0.18), dark: .init(0x000000, alpha: 0.34))
    static let highlight = SharedColorToken(light: .init(0xFFFCF4, alpha: 0.85), dark: .init(0xF2EBDF, alpha: 0.14))
    static let chartPlot = SharedColorToken(light: .init(0xFFFDF8), lightHighContrast: .init(0xFAF6EE), dark: .init(0x2C2621), darkHighContrast: .init(0x373029))
    static let chartGrid = SharedColorToken(light: .init(0x635B4E, alpha: 0.24), lightHighContrast: .init(0x4F473C, alpha: 0.34), dark: .init(0xB8AE9E, alpha: 0.20), darkHighContrast: .init(0xD0C6B6, alpha: 0.30))
    static let accentForeground = SharedColorToken(light: .init(0xFFFBF0), dark: .init(0x1C1814))
    static let moodRough = SharedColorToken(light: .init(0x99937F), dark: .init(0xA29B88))
    static let moodLow = SharedColorToken(light: .init(0x7F8A5E), dark: .init(0xA9B285))
    static let moodOkay = SharedColorToken(light: .init(0x5F7E4A), dark: .init(0x8FBC77))
    static let moodGood = SharedColorToken(light: .init(0x4A7139), dark: .init(0x84C46E))
}

enum SharedThemeTokens {
    static let brand = SharedThemeTokenSet(
        pageBackgroundTop: EditorialPrimitive.paperTop,
        pageBackgroundBottom: EditorialPrimitive.paperBottom,
        healthSurface: EditorialPrimitive.paper,
        elevatedHealthSurface: EditorialPrimitive.paperElevated,
        inputSurface: EditorialPrimitive.paperInput,
        glassSurface: EditorialPrimitive.paperGlass,
        separator: EditorialPrimitive.inkSeparator,
        textPrimary: EditorialPrimitive.ink,
        textSecondary: EditorialPrimitive.inkSecondary,
        textTertiary: EditorialPrimitive.inkTertiary,
        healthPrimary: EditorialPrimitive.bronze,
        success: EditorialPrimitive.moss,
        weight: EditorialPrimitive.slate,
        medication: EditorialPrimitive.plum,
        attention: EditorialPrimitive.orange,
        danger: EditorialPrimitive.red,
        profile: EditorialPrimitive.profile,
        doseStarter: EditorialPrimitive.doseStarter,
        doseFive: EditorialPrimitive.doseFive,
        doseSevenFive: EditorialPrimitive.doseSevenFive,
        doseTen: EditorialPrimitive.doseTen,
        doseTwelveFive: EditorialPrimitive.doseTwelveFive,
        doseFifteen: EditorialPrimitive.doseFifteen,
        shadow: EditorialPrimitive.shadow,
        cardHighlight: EditorialPrimitive.highlight,
        actionSurface: EditorialPrimitive.paperElevated,
        chartPlotSurface: EditorialPrimitive.chartPlot,
        chartGrid: EditorialPrimitive.chartGrid,
        accentForeground: EditorialPrimitive.accentForeground,
        moodRough: EditorialPrimitive.moodRough,
        moodLow: EditorialPrimitive.moodLow,
        moodOkay: EditorialPrimitive.moodOkay,
        moodGood: EditorialPrimitive.moodGood,
        moodGreat: EditorialPrimitive.moss
    )
}
