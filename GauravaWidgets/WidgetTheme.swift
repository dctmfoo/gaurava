import SwiftUI
import UIKit

// Thin SwiftUI adapter over the import-clean brand tokens shared with the app and
// watch. Widgets intentionally render the default brand rather than the in-app
// per-device theme selection.

enum WidgetTheme {
    private static let tokens = SharedThemeTokens.brand

    static let pageBackgroundTop = Color(shared: tokens.pageBackgroundTop)
    static let pageBackgroundBottom = Color(shared: tokens.pageBackgroundBottom)
    static let healthSurface = Color(shared: tokens.healthSurface)
    static let glassSurface = Color(shared: tokens.glassSurface)

    static let textPrimary = Color(shared: tokens.textPrimary)
    static let textSecondary = Color(shared: tokens.textSecondary)
    static let textTertiary = Color(shared: tokens.textTertiary)

    static let healthPrimary = Color(shared: tokens.healthPrimary)
    static let success = Color(shared: tokens.success)
    static let weight = Color(shared: tokens.weight)
    static let medication = Color(shared: tokens.medication)
    static let attention = Color(shared: tokens.attention)

    // The band index is precomputed by the producer; both app and widget consume
    // the same ordered shared-token ramp.
    static let doseRamp: [Color] = [
        Color(shared: tokens.doseStarter),
        Color(shared: tokens.doseFive),
        Color(shared: tokens.doseSevenFive),
        Color(shared: tokens.doseTen),
        Color(shared: tokens.doseTwelveFive),
        Color(shared: tokens.doseFifteen)
    ]

    /// Dose-band color for a precomputed band index, mirroring the app's
    /// `doseColor(_:)`. Falls back to the brand primary when no band is known
    /// (matches the app, where a missing dose resolves to `AppTheme.primary`).
    static func doseColor(bandIndex: Int?) -> Color {
        guard let index = bandIndex, doseRamp.indices.contains(index) else { return healthPrimary }
        return doseRamp[index]
    }

    static let stroke = Color(shared: tokens.separator)
    static let chartPlotSurface = Color(shared: tokens.chartPlotSurface)
    static let chartGrid = Color(shared: tokens.chartGrid)
}

enum WidgetFont {
    /// Small-family "Gaurava" header.
    static let header = Font.caption.weight(.semibold)
    /// Large-family "Gaurava" header.
    static let headerLarge = Font.footnote.weight(.semibold)
    static let cardTitle = Font.system(.headline, weight: .semibold)
    static let metricValue = Font.system(.headline, design: .serif, weight: .semibold).monospacedDigit()
    /// Color-coded metric rows (dose / site / weight).
    static let metric = Font.system(.subheadline, weight: .semibold)

    /// Hero day-count number; size varies by family.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
}

enum WidgetSymbol {
    static let injection = "syringe.fill"
    static let dose = "pills.fill"
    static let site = "mappin.and.ellipse"
    static let weight = "scalemass.fill"
    static let goal = "flag.fill"
    static let symptom = "heart.text.square.fill"
}

/// Brand progress ring mirroring the app's `ProgressRing`, replacing the generic
/// system `Gauge` on Home Screen families.
struct WidgetProgressRing: View {
    let progress: Double
    let percentText: String
    var lineWidth: CGFloat = 5

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        ZStack {
            Circle()
                .stroke(WidgetTheme.healthPrimary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(WidgetTheme.healthPrimary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percentText)
                .font(WidgetFont.metricValue)
                .foregroundStyle(WidgetTheme.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}

/// The calm Gaurava surface for Home Screen families: a soft vertical wash from
/// the page tone into the health surface, plus one faint top glow. Mirrors the
/// flattened `AppBackground` (AppStyle.swift) — no `healthSurface` wash, no
/// tri-color tint overlay, no glossy highlight, so the widget never reads muddy
/// and stays consistent with the calmed in-app surfaces.
struct GlanceSurfaceBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [WidgetTheme.pageBackgroundTop, WidgetTheme.healthSurface],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [WidgetTheme.healthPrimary.opacity(0.10), .clear],
                    center: .top,
                    startRadius: 0,
                    // Scale the glow to the family so it stays a faint top accent
                    // on small widgets and on the large/extra-large canvases alike.
                    endRadius: max(geo.size.width, geo.size.height) * 1.1
                )
            }
        }
    }
}

// MARK: - Color token helpers (copied from AppStyle.swift so tokens resolve per appearance)

private extension Color {
    init(shared token: SharedColorToken) {
        let light = Color.uiColor(from: token.light)
        let lightHighContrast = token.lightHighContrast.map(Color.uiColor(from:))
        let dark = Color.uiColor(from: token.dark)
        let darkHighContrast = token.darkHighContrast.map(Color.uiColor(from:))
        self = Color(UIColor { traits in
            let highContrast = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return highContrast ? (darkHighContrast ?? dark) : dark
            }
            return highContrast ? (lightHighContrast ?? light) : light
        })
    }

    static func uiColor(from face: SharedColorFace) -> UIColor {
        UIColor(
            red: face.red,
            green: face.green,
            blue: face.blue,
            alpha: face.alpha
        )
    }

}
