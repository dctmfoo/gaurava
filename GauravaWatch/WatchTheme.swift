import SwiftUI

// Thin SwiftUI-only adapter over the shared brand tokens. watchOS uses the dark
// face because third-party app content renders on the wrist's black context.
enum WatchTheme {
    private static let tokens = SharedThemeTokens.brand

    static let pageBackgroundTop = Color(shared: tokens.pageBackgroundTop.dark)
    static let pageBackgroundBottom = Color(shared: tokens.pageBackgroundBottom.dark)
    static let healthSurface = Color(shared: tokens.healthSurface.dark)
    static let glassSurface = Color(shared: tokens.glassSurface.dark)

    static let textPrimary = Color(shared: tokens.textPrimary.dark)
    static let textSecondary = Color(shared: tokens.textSecondary.dark)
    static let textTertiary = Color(shared: tokens.textTertiary.dark)

    static let healthPrimary = Color(shared: tokens.healthPrimary.dark)
    static let success = Color(shared: tokens.success.dark)
    static let weight = Color(shared: tokens.weight.dark)
    static let medication = Color(shared: tokens.medication.dark)
    static let attention = Color(shared: tokens.attention.dark)
    static let danger = Color(shared: tokens.danger.dark)
}

enum WatchFont {
    /// Small "Gaurava" wordmark.
    static let wordmark = Font.system(.footnote, weight: .semibold)
    static let cardTitle = Font.system(.headline, weight: .semibold)
    static let metricValue = Font.system(.title3, design: .serif, weight: .semibold).monospacedDigit()
    static let metric = Font.system(.subheadline, weight: .semibold)
    static let caption = Font.system(.caption, weight: .medium)

    /// Hero day-count number; size varies by surface.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
}

enum WatchSymbol {
    static let injection = "syringe.fill"
    static let dose = "pills.fill"
    static let site = "mappin.and.ellipse"
    static let weight = "scalemass.fill"
    static let goal = "flag.fill"
    static let symptom = "heart.text.square.fill"
}

/// The calm Gaurava surface for the wrist: a quiet vertical wash over the watch's
/// black background, mirroring `AppBackground` in spirit while staying legible on
/// a small OLED display (solid surface + subtle brand tint, not heavy glass).
struct WatchSurfaceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WatchTheme.pageBackgroundTop, WatchTheme.pageBackgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            WatchTheme.healthSurface.opacity(0.45)
            LinearGradient(
                colors: [WatchTheme.healthPrimary.opacity(0.14), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Color token helper (SwiftUI-only; no UIKit on the watch)

private extension Color {
    /// Build an opaque sRGB color from a 0xRRGGBB literal without UIKit, so the
    /// token file compiles on watchOS (which lacks the trait-based `UIColor`).
    init(shared face: SharedColorFace) {
        self.init(
            .sRGB,
            red: face.red,
            green: face.green,
            blue: face.blue,
            opacity: face.alpha
        )
    }
}
