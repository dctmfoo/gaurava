import SwiftUI
import UIKit

enum AppTheme {
    // Every color the app renders flows through these accessors, so they are the
    // single hook a runtime theme swap needs: each token resolves against the
    // currently selected `ThemePalette` (see ThemePalette.swift), while light vs
    // dark still resolves per render trait inside `ColorSpec.color`. Call sites
    // (`AppTheme.primary`, …) are unchanged — the former `let`s are now computed
    // `var`s, re-read on the root `.id` rebuild that the theme switch triggers.
    private static var palette: ThemePalette { AppThemeSelection.currentPalette }

    static var pageBackgroundTop: Color { palette.pageBackgroundTop.color }
    static var pageBackgroundBottom: Color { palette.pageBackgroundBottom.color }
    static var healthSurface: Color { palette.healthSurface.color }
    static var elevatedHealthSurface: Color { palette.elevatedHealthSurface.color }
    static var inputSurface: Color { palette.inputSurface.color }
    static var glassSurface: Color { palette.glassSurface.color }
    static var separator: Color { palette.separator.color }
    static var textPrimary: Color { palette.textPrimary.color }
    static var textSecondary: Color { palette.textSecondary.color }
    static var textTertiary: Color { palette.textTertiary.color }
    static var healthPrimary: Color { palette.healthPrimary.color }
    static var success: Color { palette.success.color }
    static var weight: Color { palette.weight.color }
    static var medication: Color { palette.medication.color }
    static var attention: Color { palette.attention.color }
    static var danger: Color { palette.danger.color }
    static var profile: Color { palette.profile.color }
    static var doseStarter: Color { palette.doseStarter.color }
    static var doseFive: Color { palette.doseFive.color }
    static var doseSevenFive: Color { palette.doseSevenFive.color }
    static var doseTen: Color { palette.doseTen.color }
    static var doseTwelveFive: Color { palette.doseTwelveFive.color }
    static var doseFifteen: Color { palette.doseFifteen.color }
    static var shadow: Color { palette.shadow.color }
    static var cardHighlight: Color { palette.cardHighlight.color }
    static var actionSurface: Color { palette.actionSurface.color }
    static var chartPlotSurface: Color { palette.chartPlotSurface.color }
    static var chartGrid: Color { palette.chartGrid.color }
    static var accentForeground: Color { palette.accentForeground.color }
    static var screenIdentity: Color { palette.healthPrimary.color }
    static var moodRough: Color { palette.moodRough.color }
    static var moodLow: Color { palette.moodLow.color }
    static var moodOkay: Color { palette.moodOkay.color }
    static var moodGood: Color { palette.moodGood.color }
    static var moodGreat: Color { palette.moodGreat.color }

    // Structural recipes let Editorial Ink and Midnight Focus keep distinct
    // surface depth without branching feature layouts.
    static var cardStyle: CardStyle { palette.structure.card }
    static var heroStyle: HeroStyle { palette.structure.hero }
    static var backdropStyle: BackdropStyle { palette.structure.backdrop }

    // Semantic aliases — call sites unchanged.
    static var backgroundTop: Color { pageBackgroundTop }
    static var backgroundBottom: Color { pageBackgroundBottom }
    static var paper: Color { healthSurface }
    static var card: Color { healthSurface }
    static var cardElevated: Color { elevatedHealthSurface }
    static var field: Color { inputSurface }
    static var stroke: Color { separator }
    static var ink: Color { textPrimary }
    static var muted: Color { textSecondary }
    static var primary: Color { healthPrimary }
    static var blue: Color { weight }
    static var amber: Color { attention }
    static var rose: Color { danger }
}

enum AppFont {
    /// Display numerals for the one hero figure per screen. Large but semibold —
    /// not bold — so the size carries the weight (calm, not shouty). Pair with
    /// `.monospacedDigit()` + `contentTransition(.numericText())` at call sites.
    static let display = Font.system(size: 42, weight: .semibold, design: .serif)
    static let heroTitle = Font.system(.title2, design: .serif, weight: .bold)
    static let cardTitle = Font.system(.headline, weight: .semibold)
    static let metricValue = Font.system(.title3, design: .serif, weight: .semibold).monospacedDigit()
    static let body = Font.subheadline
    static let bodyStrong = Font.subheadline.weight(.semibold)
    static let label = Font.footnote.weight(.semibold)
    static let micro = Font.caption.weight(.semibold)
}

/// Spacing rhythm. One 4/8-based scale so padding and stack spacing stay on a
/// predictable grid instead of drifting across arbitrary values (8 vs 10 vs 14).
/// Off-grid call sites were snapped to the nearest step in the design-principles
/// token pass; see docs/swiftui-design-principles-audit.html.
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

/// Corner-radius scale. The soft, continuous "calm" surface is intentional, but
/// the app had drifted to 11 distinct radii (8/14/15/16/18/20/22/24/26/28/30).
/// These three named steps keep the softness while collapsing the count: small
/// controls/fields, standard cards, and hero/sheet surfaces. (A compact 8pt chip
/// radius is retained where used.)
enum AppRadius {
    static let control: CGFloat = 16
    static let card: CGFloat = 22
    static let hero: CGFloat = 28
}

/// Glyph point sizes for `Image(systemName:)` chips/icons. Text should use the
/// Dynamic-Type `AppFont` scale instead; these named steps just keep the small
/// number of in-app icon sizes from drifting (10/14/15/16/18/34). Share-card and
/// clinician-export views deliberately keep their own fixed sizes — they render
/// to a fixed-pixel image/PDF and must not scale with Dynamic Type.
enum AppIconSize {
    static let chip: CGFloat = 10    // dense pill icons
    static let small: CGFloat = 14   // metric-tile / inline row icons
    static let medium: CGFloat = 16  // quick-action / settings row icons
    static let large: CGFloat = 18   // emphasis glyphs (mood)
    static let seal: CGFloat = 34    // onboarding success seal
}

/// Shrink floors for `minimumScaleFactor` on single-line, width-constrained
/// labels. The app had drifted to 14 hand-tuned floors (0.52…0.85); these two
/// named steps replace the in-app ones. Floors are deliberately NOT raised: long
/// hi/ta/te strings rely on the shrink to fit a fixed-width tile, so a higher
/// floor would truncate them. Use `minScaleTight` for dense numeric/large-number
/// tiles. (Share-card / clinician-export views render to a fixed-pixel canvas and
/// keep their own aggressive floors — text there genuinely cannot reflow.)
enum AppType {
    static let minScale: CGFloat = 0.75       // general single-line labels
    static let minScaleTight: CGFloat = 0.7   // dense numeric / large-number tiles
}

enum AppSymbol {
    enum Tab {
        static let summary = "square.grid.2x2"
        static let jabs = Health.injection
        static let results = Health.trend
        static let log = Health.note
        static let care = "person.crop.circle"
    }

    enum Health {
        static let start = "leaf.fill"
        static let weight = "scalemass.fill"
        static let weightUnit = "scalemass"
        static let appleHealth = "heart.fill"
        static let currentWeight = "gauge.medium"
        static let bmi = "figure"
        static let percent = "percent"
        static let weeklyAverage = "clock.fill"
        static let trend = "chart.line.uptrend.xyaxis"
        static let goal = "flag.fill"
        static let phase = "number.circle.fill"
        static let routine = "checklist"
        static let injection = "syringe.fill"
        static let dose = "pills.fill"
        static let injectionSite = "mappin.and.ellipse"
        static let schedule = "calendar"
        static let reminder = "clock.fill"
        static let dailyLog = "square.and.pencil"
        static let dailyNote = "text.badge.plus"
        static let note = "note.text"
        static let profile = "person"
        static let height = "arrow.up.and.down"
        static let walking = "figure.walk"
        static let symptomNote = "heart.text.square.fill"
    }

    enum Status {
        static let notScheduled = "circle.dashed"
        static let needsLogging = "exclamationmark.triangle.fill"
        static let readyToLog = Health.injection
        static let comingUp = Health.reminder
        static let onTrack = "checkmark.circle.fill"
        static let verified = "checkmark.seal.fill"
        static let selected = "checkmark"
        static let selectedCircle = "checkmark.circle.fill"
        static let unselectedCircle = "circle"
    }

    enum Action {
        static let add = "plus"
        static let edit = "pencil"
        static let delete = "trash"
        static let save = "checkmark"
        static let saveToPhotos = "photo.badge.plus"
        static let share = "square.and.arrow.up"
        static let send = "arrow.up"
        static let next = "arrow.right"
        static let disclosure = "chevron.right"
        static let importDocument = "doc.badge.plus"
        static let importHistory = "square.and.arrow.down"
        static let doseLabels = "tag"
        static let doseLabelsOn = "tag.fill"
        static let doseChange = "arrow.up.right"
        static let firstJab = Health.goal
    }

    enum Legal {
        static let about = "info.circle.fill"
        static let medicalSafety = "stethoscope"
        static let privacy = "lock.shield.fill"
        static let support = "envelope.fill"
        static let terms = "doc.text.fill"
    }

    enum Field {
        static let number = "number"
        static let note = Health.note
    }

    enum Insight {
        static let downTrend = "arrow.down.right"
        static let doseIncrease = "bolt.fill"
        static let target = "target"
        static let milestone = "medal.fill"
        static let upTrend = "arrow.up.right"
    }
}

struct AppScreen<Content: View>: View {
    let title: String
    let spacing: CGFloat
    /// Per-tab ambient identity: the mesh wash behind the hero zone (light mode
    /// only — dark mode unifies on the brand wash inside `AppBackground`).
    let ambientTint: Color
    @ViewBuilder var content: Content

    init(
        title: String,
        spacing: CGFloat = 16,
        ambientTint: Color = AppTheme.primary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.spacing = spacing
        self.ambientTint = ambientTint
        self.content = content()
    }

    var body: some View {
        ScrollView {
            GlassContentStack(spacing: spacing) {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 104)
            }
        }
        .background(AppBackground(ambientTint: ambientTint))
        .navigationTitle(appLocalized(title))
        .navigationBarTitleDisplayMode(.inline)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Calm app backdrop: the soft vertical wash from the brand-green page tone to a
/// clean warm near-white, with a static ambient mesh in the top hero zone. In
/// light mode the mesh carries each tab's identity color; in dark mode every tab
/// shares one quiet brand wash at lower intensity — dark surfaces stay dominant
/// and color meaning stays consistent across tabs (Material dark theme / NN/g
/// color-consistency guidance). The mesh is deliberately low-chroma (the content
/// layer is where brand color lives per the iOS 26 layering doctrine, but
/// dignity means a wash, not a poster).
struct AppBackground: View {
    var ambientTint: Color = AppTheme.primary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ambience = AppThemeSelection.currentPalette.ambience
        return ZStack {
            LinearGradient(
                colors: [AppTheme.pageBackgroundTop, AppTheme.pageBackgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            switch AppTheme.backdropStyle {
            case .washMesh:
                if colorScheme == .dark {
                    if ambience.darkWash > 0 {
                        AmbientMeshWash(tint: AppTheme.primary, intensity: ambience.darkWash)
                    }
                } else if ambience.lightWash > 0 {
                    AmbientMeshWash(tint: ambientTint, intensity: ambience.lightWash)
                }
            case .flat:
                EmptyView()
            }
        }
        .ignoresSafeArea()
    }
}

/// The hero-zone wash. A static 3x3 `MeshGradient` masked so it fades out by the
/// upper third of the screen. Deliberately not animated: a full-screen mesh
/// redrawn on a `TimelineView` tick competes with scrolling on the main thread
/// and caused visible scroll hitches.
private struct AmbientMeshWash: View {
    let tint: Color
    var intensity: Double = 1

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.42], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                tint.opacity(0.22 * intensity), tint.opacity(0.10 * intensity), tint.opacity(0.18 * intensity),
                tint.opacity(0.06 * intensity), tint.opacity(0.14 * intensity), tint.opacity(0.05 * intensity),
                .clear, .clear, .clear
            ]
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.85), location: 0.16),
                    .init(color: .clear, location: 0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
    }
}

struct GlassContentStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

struct HealthCard<Content: View>: View {
    let tint: Color
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder var content: Content

    init(
        tint: Color = AppTheme.primary,
        cornerRadius: CGFloat = AppRadius.card,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    // A clean, calm content surface: one solid fill, one hairline border, and a
    // two-layer shadow (tight contact + wide diffuse) so the card sits on the
    // page instead of floating as a flat sticker. Content cards stay opaque
    // (Liquid Glass is reserved for the floating controls); the `tint` parameter
    // is kept for API stability (callers still pass their domain color for the
    // content inside) but does not wash the quiet card itself — HeroCard is the
    // tier that carries color.
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(cornerRadius: cornerRadius, style: AppTheme.cardStyle))
    }
}

/// The quiet content-surface recipe shared by Editorial Ink and Midnight Focus.
private struct CardSurface: ViewModifier {
    let cornerRadius: CGFloat
    let style: CardStyle

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch style {
        case .soft:
            content
                .background(AppTheme.healthSurface, in: shape)
                .overlay(shape.stroke(AppTheme.stroke, lineWidth: 1))
                .shadow(color: AppTheme.shadow.opacity(0.22), radius: 1.5, x: 0, y: 1)
                .shadow(color: AppTheme.shadow.opacity(0.34), radius: 14, x: 0, y: 8)
        case .voidElevated:
            content
                .background(AppTheme.elevatedHealthSurface, in: shape)
        }
    }
}

struct ThemedSurfaceColors {
    let foreground: Color
    let secondaryForeground: Color
    let iconForeground: Color
    let iconBackground: Color
    let disclosureForeground: Color

    static func compact(tint: Color) -> ThemedSurfaceColors {
        return ThemedSurfaceColors(
            foreground: AppTheme.ink,
            secondaryForeground: AppTheme.muted,
            iconForeground: tint,
            iconBackground: tint.opacity(0.14),
            disclosureForeground: AppTheme.muted
        )
    }
}

struct ThemedMiniSurface<Content: View>: View {
    let tint: Color
    var cornerRadius: CGFloat = AppRadius.control
    var padding: CGFloat = AppSpacing.md
    var minHeight: CGFloat?
    @ViewBuilder var content: (ThemedSurfaceColors) -> Content

    init(
        tint: Color,
        cornerRadius: CGFloat = AppRadius.control,
        padding: CGFloat = AppSpacing.md,
        minHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping (ThemedSurfaceColors) -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.minHeight = minHeight
        self.content = content
    }

    var body: some View {
        let colors = ThemedSurfaceColors.compact(tint: tint)
        content(colors)
            .padding(padding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .modifier(CardSurface(cornerRadius: cornerRadius, style: AppTheme.cardStyle))
    }
}

struct ThemedActionSurface<Content: View>: View {
    let tint: Color
    var isActive = false
    var cornerRadius: CGFloat = AppRadius.control
    var padding: CGFloat = 13
    var minHeight: CGFloat? = 54
    @ViewBuilder var content: (ThemedSurfaceColors) -> Content

    init(
        tint: Color,
        isActive: Bool = false,
        cornerRadius: CGFloat = AppRadius.control,
        padding: CGFloat = 13,
        minHeight: CGFloat? = 54,
        @ViewBuilder content: @escaping (ThemedSurfaceColors) -> Content
    ) {
        self.tint = tint
        self.isActive = isActive
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.minHeight = minHeight
        self.content = content
    }

    var body: some View {
        let colors = ThemedSurfaceColors.compact(tint: tint)
        content(colors)
            .padding(padding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .modifier(
                ThemedActionSurfaceBackground(
                    tint: tint,
                    isActive: isActive,
                    cornerRadius: cornerRadius,
                    style: AppTheme.cardStyle
                )
            )
    }
}

private struct ThemedActionSurfaceBackground: ViewModifier {
    let tint: Color
    let isActive: Bool
    let cornerRadius: CGFloat
    let style: CardStyle

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let stroke = isActive ? tint.opacity(0.34) : AppTheme.stroke

        switch style {
        case .soft:
            content
                .background(AppTheme.actionSurface, in: shape)
                .overlay(shape.strokeBorder(stroke, lineWidth: 1))
                .shadow(color: AppTheme.shadow.opacity(0.18), radius: 10, x: 0, y: 6)
        case .voidElevated:
            content
                .background(AppTheme.elevatedHealthSurface, in: shape)
                .overlay(shape.strokeBorder(isActive ? tint.opacity(0.30) : .clear, lineWidth: 1))
        }
    }
}

/// The hero surface tier: one per screen. Carries the screen's identity color as
/// a soft two-stop wash over the card surface, a top-edge highlight that catches
/// the ambient light, and a deeper two-layer shadow than the quiet cards. The
/// hierarchy IS the design — everything else stays calm so this surface reads.
struct HeroCard<Content: View>: View {
    let tint: Color
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder var content: Content

    init(
        tint: Color = AppTheme.primary,
        cornerRadius: CGFloat = AppRadius.hero,
        padding: CGFloat = AppSpacing.xl,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(HeroSurface(cornerRadius: cornerRadius, tint: tint, style: AppTheme.heroStyle))
    }
}

/// The hero-surface recipes retained by the two approved themes.
private struct HeroSurface: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let style: HeroStyle

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch style {
        case .tintWash:
            content
                .background {
                    shape.fill(AppTheme.healthSurface)
                    shape.fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.03)], startPoint: .topLeading, endPoint: .bottom))
                }
                .overlay(shape.strokeBorder(LinearGradient(colors: [AppTheme.cardHighlight, AppTheme.stroke.opacity(0.6), AppTheme.stroke], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: AppTheme.shadow.opacity(0.25), radius: 2, x: 0, y: 1)
                .shadow(color: tint.opacity(0.16), radius: 22, x: 0, y: 12)
        case .voidGlow:
            content
                .background {
                    shape.fill(AppTheme.elevatedHealthSurface)
                    shape.fill(LinearGradient(colors: [tint.opacity(0.12), .clear], startPoint: .top, endPoint: .center))
                }
                .shadow(color: tint.opacity(0.20), radius: 18, x: 0, y: 0)
        }
    }
}

/// Uppercase tracked mini-header that sits OUTSIDE cards, giving each screen a
/// quiet editorial rhythm between sections (instead of every title living inside
/// yet another white box).
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(appLocalized(title))
            .font(AppFont.label)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(AppTheme.textTertiary)
            .padding(.horizontal, AppSpacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    var metricIdentifier: String?
    var minContentHeight: CGFloat?

    var body: some View {
        HealthCard(tint: tint, cornerRadius: AppRadius.card, padding: 12) {
            tileContent(
                valueColor: AppTheme.ink,
                labelColor: AppTheme.muted,
                iconColor: tint,
                iconBackground: tint.opacity(0.14)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appLocalized(title)), \(appLocalized(value))")
        .accessibilityIdentifier(metricIdentifier ?? "\(title)-metric")
    }

    @ViewBuilder
    private func tileContent(valueColor: Color, labelColor: Color, iconColor: Color, iconBackground: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: AppIconSize.small, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(iconBackground, in: Circle())

            if minContentHeight != nil {
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(appLocalized(value))
                    .font(AppFont.metricValue)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScale)
                    .contentTransition(.numericText())
                Text(appLocalized(title))
                    .font(AppFont.label)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScale)
                if let subtitle {
                    Text(appLocalized(subtitle))
                        .font(.caption)
                        .foregroundStyle(labelColor)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: minContentHeight, alignment: .topLeading)
    }
}

struct HeroMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let progress: Double?
    let tint: Color
    let systemImage: String

    var body: some View {
        HealthCard(tint: tint, cornerRadius: AppRadius.hero, padding: AppSpacing.lg) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Label(appLocalized(title), systemImage: systemImage)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(tint)

                    Text(appLocalized(value))
                        .font(AppFont.heroTitle)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(AppType.minScaleTight)
                        .contentTransition(.numericText())

                    Text(appLocalized(subtitle))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if let progress {
                    ProgressRing(progress: progress, tint: tint)
                        .frame(width: 72, height: 72)
                }
            }
        }
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    /// Optional call-to-action, mirroring `ContentUnavailableView`'s
    /// label/description/actions contract so every empty state can carry a clear
    /// next step. When `actionTitle` and `action` are both set, a button renders
    /// beneath the message.
    var actionTitle: String?
    var actionSystemImage: String?
    var action: (() -> Void)?
    var actionIdentifier: String?

    var body: some View {
        HealthCard(tint: tint, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.14), in: Circle())

                Text(appLocalized(title))
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppTheme.ink)

                Text(appLocalized(message))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(spacing: 8) {
                            if let actionSystemImage {
                                Image(systemName: actionSystemImage)
                            }
                            Text(appLocalized(actionTitle))
                        }
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.accentForeground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(tint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(actionIdentifier ?? "emptyStateAction")
                    .padding(.top, 4)
                }
            }
        }
    }
}

enum AppSurfaceRecipe {
    static let statusPillBackgroundOpacity = 0.16
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(appLocalized(text))
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(tint.opacity(AppSurfaceRecipe.statusPillBackgroundOpacity), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.28), lineWidth: 1))
    }
}

struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    // Quick actions are genuine controls, so they live on the functional layer:
    // an interactive Liquid Glass tile carrying its domain tint. Inside
    // AppScreen's GlassEffectContainer adjacent tiles blend as one fluid cluster.
    var body: some View {
        return Button(action: action) {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: AppIconSize.medium, weight: .bold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(tint)
                    .background(tint.opacity(0.14), in: Circle())

                Text(appLocalized(title))
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScale)
            }
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .glassEffect(
                .regular.tint(tint.opacity(0.10)).interactive(),
                in: .rect(cornerRadius: AppRadius.card)
            )
        }
        .buttonStyle(AppPressableButtonStyle())
    }
}

struct SheetActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    // The one prominent action of a sheet/flow: system Liquid Glass prominent
    // button, tinted with the action's semantic color. The system handles pressed
    // shimmer, Reduce Transparency fallback, and disabled dimming.
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(AppFont.bodyStrong)
                Text(appLocalized(title))
                    .font(AppFont.bodyStrong)
            }
            .foregroundStyle(AppTheme.accentForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
    }
}

/// Shared pressed-state physics for custom-label buttons: a gentle settle into
/// the surface (scale + dimming) with a light impact tick on touch-down. Calm by
/// construction — high damping, small travel.
struct AppPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: configuration.isPressed) { _, isPressed in
                isPressed
            }
    }
}

extension View {
    /// Subtle scroll-edge life for repeated rows: slight scale + fade as rows
    /// enter and leave the viewport. Interactive (tracks the finger), no blur,
    /// small travel — list motion should read as depth, not as a slideshow.
    func gentleScrollTransition() -> some View {
        scrollTransition(.interactive) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
                .opacity(phase.isIdentity ? 1 : 0.72)
        }
    }
}

struct AppTextFieldShell<Content: View>: View {
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)

            content
                .font(.body)
                .foregroundStyle(AppTheme.ink)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(AppTheme.inputSurface, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            // Settings-app idiom (matches EditableInfoRow): glyph on a tinted
            // gradient squircle.
            Image(systemName: systemImage)
                .font(.system(size: AppIconSize.small, weight: .semibold))
                .foregroundStyle(AppTheme.accentForeground)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(appLocalized(title))
                .font(AppFont.body)
                .foregroundStyle(AppTheme.ink)

            Spacer(minLength: 12)

            Text(appLocalized(value))
                .font(AppFont.bodyStrong)
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Signature progress ring: a single ring (deliberately NOT Activity-rings) with
/// an angular gradient that deepens toward the tip, rounded caps, a quiet track,
/// and a soft glow at the leading edge. Sweeps in from zero on first appear with
/// a calm, heavily-damped spring; under Reduce Motion it renders settled.
struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.45), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(animatedProgress, 0.001))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Leading-edge glow: a soft halo around the ring tip so progress has
            // a felt "now" point. GeometryReader keeps it correct at any size.
            if animatedProgress > 0.02 {
                GeometryReader { proxy in
                    let radius = (min(proxy.size.width, proxy.size.height) - lineWidth) / 2
                    let angle = animatedProgress * 2 * .pi - .pi / 2
                    Circle()
                        .fill(tint)
                        .frame(width: lineWidth * 0.9, height: lineWidth * 0.9)
                        .blur(radius: lineWidth * 0.55)
                        .position(
                            x: proxy.size.width / 2 + radius * CGFloat(cos(angle)),
                            y: proxy.size.height / 2 + radius * CGFloat(sin(angle))
                        )
                }
                .allowsHitTesting(false)
            }

            Text(appLocalizedValue("\(Int((clamped * 100).rounded()))%"))
                .font(AppFont.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink)
                .contentTransition(.numericText())
        }
        .onAppear {
            if reduceMotion {
                animatedProgress = clamped
            } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) {
                    animatedProgress = clamped
                }
            }
        }
        .onChange(of: clamped) { _, newValue in
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.9)) {
                animatedProgress = newValue
            }
        }
    }
}

/// Muted, never-alarm provisional injection plan, shown before any jab is logged
/// when the user set a preferred injection weekday. Deliberately NOT styled like
/// the live next-injection cards (no countdown, no overdue/ready coloring) — it is
/// a plan to confirm, not a schedule to act on. Shared by Summary and Jabs.
struct ProvisionalInjectionCard: View {
    let weekdayName: String
    let date: Date

    var body: some View {
        HealthCard(tint: AppTheme.muted, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                Image(systemName: AppSymbol.Health.schedule)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.muted.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Next injection")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.ink)
                    Text(appLocalizedValue("Planned for every \(weekdayName) — log your first jab to confirm"))
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(date.appFormatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer(minLength: 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("provisionalInjectionCard")
    }
}

/// Calm paused-treatment surface shared by Summary and Jabs. No alarm color and
/// no countdown — paused treatment must never read as due, overdue, or needing a
/// log. The schedule resumes only from the explicit Resume action in Care.
struct PausedTreatmentCard: View {
    let startedAt: Date?

    var body: some View {
        HealthCard(tint: AppTheme.blue, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                Image(systemName: "pause.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.blue.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Treatment paused")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Resume anytime in Care.")
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer(minLength: 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pausedTreatmentCard")
    }

    private var subtitle: String {
        guard let startedAt else {
            return appLocalized("On a break — no reminders, no overdue.")
        }
        let when = startedAt.appFormatted(.dateTime.month(.abbreviated).day())
        return appLocalizedValue("On a break since \(when) — no reminders, no overdue.")
    }
}

/// Display name for a stored 0-based (Sunday == 0) injection weekday, or nil when
/// unset. Mirrors `TrackerProfile.preferredInjectionDay`'s encoding so callers can
/// pass the stored value straight through.
func injectionWeekdayName(_ preferredInjectionDay: Int?) -> String? {
    guard let day = preferredInjectionDay, (0..<7).contains(day) else { return nil }
    // effectiveCalendar (not Calendar.current) so the name follows the in-app
    // language picker rather than the system locale — see AppLocalization.
    return AppLocalization.effectiveCalendar.weekdaySymbols[day]
}

// Computed (not a stored `let`): the tokens are theme-dependent, so a stored
// global would capture the default theme's dose colours once and never update
// when the user switches theme. Re-reading here keeps the ramp in palette.
private var doseColorRamp: [Color] {
    [
        AppTheme.doseStarter,
        AppTheme.doseFive,
        AppTheme.doseSevenFive,
        AppTheme.doseTen,
        AppTheme.doseTwelveFive,
        AppTheme.doseFifteen
    ]
}

func doseColorBandIndex(_ dose: Double?) -> Int? {
    guard let dose else { return nil }
    let medication = Medication.inferred(fromMg: dose)
    let presetIndex = medication.nearestPresetIndex(to: dose)
    let presetCount = medication.dosePresets.count
    guard presetCount > 1 else { return 0 }

    let scaledIndex = (Double(presetIndex) / Double(presetCount - 1)) * Double(doseColorRamp.count - 1)
    return min(max(Int(scaledIndex.rounded()), 0), doseColorRamp.count - 1)
}

func doseColor(_ dose: Double?) -> Color {
    guard let index = doseColorBandIndex(dose) else { return AppTheme.primary }
    return doseColorRamp[index]
}

func doseBadgeForeground(_ dose: Double, colorScheme: ColorScheme) -> Color {
    // All six light dose bands clear AA (>=4.5:1) with white text now that the
    // teal and amber bands are darkened, so no per-band black-text branch is needed.
    colorScheme == .dark ? .black : .white
}

func doseInputText(_ dose: Double) -> String {
    dose.formatted(.number.precision(.fractionLength(0...2)))
}

func doseOptionValues(for medication: Medication, including currentDose: Double? = nil) -> [Double] {
    var values = medication.dosePresets
    if let currentDose,
       !values.contains(where: { abs($0 - currentDose) < 0.001 }) {
        values.append(currentDose)
    }
    return values.sorted()
}

func doseText(_ dose: Double?) -> String {
    guard let dose else { return appLocalized("Not set") }
    return appLocalizedValue("\(doseInputText(dose)) mg")
}

func weightText(_ weight: Double?) -> String {
    guard let weight else { return appLocalized("-- kg") }
    return appLocalizedValue("\(weight.formatted(.number.precision(.fractionLength(0...1)))) kg")
}

func appLocalized(_ value: String) -> String {
    String(localized: String.LocalizationValue(value), bundle: AppLocalization.currentBundle) // i18n:allow
}
