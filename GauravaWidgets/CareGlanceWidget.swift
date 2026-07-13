import SwiftUI
import WidgetKit

// Care Glance widget.
//
// Home Screen: systemSmall / systemMedium / systemLarge, and systemExtraLarge on
// iPad. Lock Screen: accessoryInline / accessoryCircular / accessoryRectangular.
// Every family renders from the App Group glance snapshot via the shared,
// Foundation-only `GlanceDisplayModel`, which applies the surface-shape privacy
// rule (accessory families stay low-detail). The widget only reads; it never
// imports SwiftData and never builds the model container. Defensive states:
// placeholder (no file) and refresh (expired) are handled inside the display
// model. Producer-side redaction already happened, so we render what survives.

struct CareGlanceEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: GauravaGlanceSnapshot?
    let localeIdentifier: String

    var surfaceLocale: Locale { Locale(identifier: localeIdentifier) }
}

struct CareGlanceProvider: TimelineProvider {
    private let store = AppGroupFileSnapshotStore()

    func placeholder(in context: Context) -> CareGlanceEntry {
        makeEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CareGlanceEntry) -> Void) {
        completion(makeEntry(date: Date(), snapshot: store.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CareGlanceEntry>) -> Void) {
        let now = Date()
        let snapshot = store.read()
        let entry = makeEntry(date: now, snapshot: snapshot)
        // Refresh at the next injection boundary if known, otherwise hourly.
        let candidates = [snapshot?.nextAction?.nextInjectionDate, now.addingTimeInterval(3600)]
            .compactMap { $0 }
            .filter { $0 > now }
        let reloadAt = candidates.min() ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(reloadAt)))
    }

    private func makeEntry(date: Date, snapshot: GauravaGlanceSnapshot?) -> CareGlanceEntry {
        CareGlanceEntry(
            date: date,
            snapshot: snapshot,
            localeIdentifier: GauravaSurface.surfaceLocaleIdentifier()
        )
    }
}

struct CareGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GauravaSurface.careGlanceWidgetKind, provider: CareGlanceProvider()) { entry in
            CareGlanceView(entry: entry)
        }
        .configurationDisplayName(.widgetCareGlanceDisplayName)
        .description(.widgetCareGlanceDescription)
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

// MARK: - Family routing

private extension WidgetFamily {
    var surfaceClass: SurfaceFamilyClass {
        switch self {
        case .systemSmall: return .systemSmall
        case .systemMedium: return .systemMedium
        case .systemLarge: return .systemLarge
        case .systemExtraLarge: return .systemExtraLarge
        case .accessoryInline: return .accessoryInline
        case .accessoryCircular: return .accessoryCircular
        case .accessoryRectangular: return .accessoryRectangular
        @unknown default: return .systemSmall
        }
    }
}

struct CareGlanceView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CareGlanceEntry
    var familyOverride: WidgetFamily?

    private var display: GlanceDisplay {
        GlanceDisplayModel.make(
            from: entry.snapshot,
            family: effectiveFamily.surfaceClass,
            asOf: entry.date,
            locale: entry.surfaceLocale
        )
    }

    private var effectiveFamily: WidgetFamily {
        familyOverride ?? family
    }

    var body: some View {
        content
            .environment(\.locale, entry.surfaceLocale)
            .widgetURL(URL(string: "gaurava://jabs"))
            .modifier(SurfaceBackground(family: effectiveFamily))
    }

    @ViewBuilder
    private var content: some View {
        let display = display
        switch effectiveFamily {
        case .systemSmall: SmallContent(display: display)
        case .systemMedium: MediumContent(display: display)
        case .systemLarge: LargeContent(display: display)
        case .systemExtraLarge: ExtraLargeContent(display: display)
        case .accessoryInline: InlineContent(display: display)
        case .accessoryCircular: CircularContent(display: display)
        case .accessoryRectangular: RectangularContent(display: display)
        @unknown default: SmallContent(display: display)
        }
    }
}

/// Per-family container background: the warm Gaurava surface behind Home Screen
/// widgets; transparent behind Lock Screen accessories so the system vibrant
/// treatment shows through.
private struct SurfaceBackground: ViewModifier {
    let family: WidgetFamily

    func body(content: Content) -> some View {
        if family.surfaceClass.isAccessory {
            content.containerBackground(for: .widget) { Color.clear }
        } else {
            content.containerBackground(for: .widget) { GlanceSurfaceBackground() }
        }
    }
}

// MARK: - Home Screen families

private struct GlanceHeader: View {
    var font: Font = WidgetFont.header

    var body: some View {
        Label(.widgetBrandGaurava, systemImage: WidgetSymbol.injection)
            .font(font)
            .foregroundStyle(WidgetTheme.healthPrimary)
    }
}

private struct SmallContent: View {
    let display: GlanceDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlanceHeader()
            Spacer(minLength: 0)
            if let hero = display.heroDayText {
                Text(hero)
                    .font(WidgetFont.hero(hero.count > 2 ? 28 : 40))
                    .foregroundStyle(display.isDoseDue ? WidgetTheme.attention : WidgetTheme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(display.dayCountCaption ?? "")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.textSecondary)
            } else {
                Text(display.statusPhrase)
                    .font(WidgetFont.cardTitle)
                    .foregroundStyle(WidgetTheme.textPrimary)
            }
            // Detail rows stay quiet at this size — one accent (the header) is
            // enough; the icons already say what each row is.
            if let site = display.siteText {
                Label(site, systemImage: WidgetSymbol.site)
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.textSecondary)
                    .lineLimit(1)
            }
            // Full tier reveals weight; Minimal hides it. The signed change is
            // the payoff, so it leads; absolute weight is the fallback.
            if let weight = display.weightDeltaText ?? display.currentWeightText {
                Label(weight, systemImage: WidgetSymbol.weight)
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumContent: View {
    let display: GlanceDisplay

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                GlanceHeader()
                headline
                if let dose = display.doseText {
                    Label(dose, systemImage: WidgetSymbol.dose)
                        .font(WidgetFont.metric)
                        .foregroundStyle(WidgetTheme.doseColor(bandIndex: display.doseBandIndex))
                }
                if let site = display.siteText {
                    Label(site, systemImage: WidgetSymbol.site)
                        .font(.caption)
                        .foregroundStyle(WidgetTheme.healthPrimary)
                        .lineLimit(1)
                }
                // Full tier reveals weight; Minimal hides it. Absolute weight
                // plus the signed change since start ("86.5 kg · −12.4 kg").
                if let weight = combinedWeightText {
                    Label(weight, systemImage: WidgetSymbol.weight)
                        .font(.caption)
                        .foregroundStyle(WidgetTheme.weight)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 12)
            if let fraction = display.progressFraction {
                WidgetProgressRing(progress: fraction, percentText: display.progressPercentText ?? "")
                    .frame(width: 52, height: 52)
                    .ringCaption()
            } else if let hero = display.heroDayText {
                // Redacted tier has no ring; keep Medium balanced with the hero
                // day. The left title already reads "Next dose in N days", so we
                // show only the glanceable hero here (no caption — it would
                // restate the title in words).
                Text(hero)
                    .font(WidgetFont.hero(hero.count > 2 ? 28 : 40))
                    .foregroundStyle(display.isDoseDue ? WidgetTheme.attention : WidgetTheme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var headline: some View {
        if let hero = display.heroDayText {
            VStack(alignment: .leading, spacing: 1) {
                Text(hero)
                    .font(WidgetFont.hero(hero.count > 2 ? 30 : 40))
                    .foregroundStyle(display.isDoseDue ? WidgetTheme.attention : WidgetTheme.textPrimary)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(display.dayCountCaption ?? "")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
        } else {
            Text(display.statusPhrase)
                .font(WidgetFont.cardTitle)
                .foregroundStyle(display.isDoseDue ? WidgetTheme.attention : WidgetTheme.textPrimary)
        }
    }

    private var combinedWeightText: String? {
        let parts = [display.currentWeightText, display.weightDeltaText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// "to goal" under the progress ring — an unlabeled percentage doesn't say what
/// it measures.
private extension View {
    func ringCaption() -> some View {
        VStack(spacing: 2) {
            self
            Text(.widgetCareGlanceToGoal)
                .font(.caption2)
                .foregroundStyle(WidgetTheme.textSecondary)
        }
    }
}

// The large families compose three zones: a fixed header band, a fixed focus
// block (hero + details), and — only in Full tier — a flexible trend block that
// absorbs ALL remaining height. Exactly one flexible region per tier, so slack
// can never pool into a dead band:
//   - Full:     header at top, focus below it, trend chart fills the rest.
//   - Minimal:  no trend; the focus block is vertically centered.
//   - Redacted: just the countdown, vertically centered — calm by design.

private struct LargeContent: View {
    let display: GlanceDisplay

    private var hasTrend: Bool { display.trendPoints.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlanceRingHeader(display: display, headerFont: WidgetFont.headerLarge)

            if hasTrend {
                // Tighter top band + a smaller hero hand the freed height to the
                // chart (the only `maxHeight: .infinity` child), so the plot reads
                // as a real chart instead of a sliver. The countdown stays the
                // largest element; weight just stops being top-heavy.
                Spacer().frame(height: 10)
                GlanceFocusBlock(display: display, heroSize: 36, includeWeight: false)
                Spacer().frame(height: 10)
                TrendChart(
                    points: display.trendPoints,
                    deltaText: display.trendDeltaText,
                    goalKg: display.trendGoalKg,
                    startText: display.trendStartText,
                    currentText: display.currentWeightText,
                    goalText: display.trendGoalText
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 12)
                GlanceFocusBlock(display: display)
                Spacer(minLength: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// iPad extra-large: a wide 2:1 canvas. When a trend exists, split into a focus
/// column (left) and a hero trend chart (right) so the chart gets width instead
/// of being letterboxed. Without a trend, collapse to the centered single column.
private struct ExtraLargeContent: View {
    let display: GlanceDisplay

    private var hasTrend: Bool { display.trendPoints.count >= 2 }

    var body: some View {
        if hasTrend {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    GlanceRingHeader(display: display, headerFont: WidgetFont.headerLarge)
                    Spacer().frame(height: 16)
                    GlanceFocusBlock(display: display, includeWeight: false)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                TrendChart(
                    points: display.trendPoints,
                    deltaText: display.trendDeltaText,
                    goalKg: display.trendGoalKg,
                    startText: display.trendStartText,
                    currentText: display.currentWeightText,
                    goalText: display.trendGoalText
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            LargeContent(display: display)
        }
    }
}

// MARK: - Shared large-family building blocks

private struct GlanceRingHeader: View {
    let display: GlanceDisplay
    var headerFont: Font = WidgetFont.headerLarge

    var body: some View {
        HStack(alignment: .center) {
            GlanceHeader(font: headerFont)
            Spacer()
            if let fraction = display.progressFraction {
                WidgetProgressRing(progress: fraction, percentText: display.progressPercentText ?? "")
                    .frame(width: 58, height: 58)
                    .ringCaption()
            }
        }
    }
}

private struct GlanceFocusBlock: View {
    let display: GlanceDisplay
    var heroSize: CGFloat = 52
    /// Large families hide weight here when the trend chart is present — the
    /// chart shows current weight and the total instead, so a row would duplicate
    /// it. With no chart this stays the only place weight appears.
    var includeWeight: Bool = true

    private var hasDetails: Bool {
        display.doseText != nil || display.siteText != nil || (includeWeight && display.currentWeightText != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let hero = display.heroDayText {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hero)
                        .font(WidgetFont.hero(hero.count > 2 ? heroSize * 0.7 : heroSize))
                        .foregroundStyle(display.isDoseDue ? WidgetTheme.attention : WidgetTheme.textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(display.dayCountCaption ?? "")
                        .font(.subheadline)
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
            } else {
                Text(display.statusPhrase)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(WidgetTheme.textPrimary)
            }

            if hasDetails {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        if let dose = display.doseText {
                            Label(dose, systemImage: WidgetSymbol.dose)
                                .font(WidgetFont.metric)
                                .foregroundStyle(WidgetTheme.doseColor(bandIndex: display.doseBandIndex))
                        }
                        if let site = display.siteText {
                            Label(site, systemImage: WidgetSymbol.site)
                                .font(WidgetFont.metric)
                                .foregroundStyle(WidgetTheme.healthPrimary)
                                .lineLimit(1)
                        }
                    }
                    if includeWeight, let weight = combinedWeightText {
                        Label(weight, systemImage: WidgetSymbol.weight)
                            .font(WidgetFont.metric)
                            .foregroundStyle(WidgetTheme.weight)
                    }
                }
            }
        }
    }

    private var combinedWeightText: String? {
        let parts = [display.currentWeightText, display.weightDeltaText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Weight-trend as a plotted area chart inside a rounded plot surface — a real
/// "section" with presence, not a hairline. Hand-drawn with `Path` (no Charts
/// dependency): area gradient fill, weight-token line, a ringed end marker, the
/// all-time loss since the starting weight in the header ("−19 kg · since you
/// started"), the start and current weights labelled on the line, and a goal
/// gridline when the goal is near enough to plot (one faint mean gridline
/// otherwise). Tapping it deep links to the weight surface. Fills its parent.
private struct TrendChart: View {
    @Environment(\.locale) private var locale
    let points: [TrendPoint]
    var deltaText: String?
    var goalKg: Double?
    var startText: String?
    var currentText: String?
    var goalText: String?

    var body: some View {
        Link(destination: GauravaScreen.weight.url) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(.widgetCareGlanceWeightTrend)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetTheme.textSecondary)
                    Spacer()
                    if let deltaText {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(deltaText)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WidgetTheme.weight)
                            Text(.widgetCareGlanceSinceStart)
                                .font(.caption2)
                                .foregroundStyle(WidgetTheme.textTertiary)
                        }
                    }
                }
                plot
            }
        }
    }

    /// "Goal 80" when the gridline shows, else just "Goal".
    private var goalCaption: String {
        let goal = SurfaceLocalizedString.resolve(.widgetCareGlanceGoal, locale: locale)
        return goalText.map { "\(goal) \($0)" } ?? goal
    }

    private var plot: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return GeometryReader { geo in
            let insetX: CGFloat = 12
            let insetY: CGFloat = 10
            let w = max(geo.size.width - insetX * 2, 1)
            let h = max(geo.size.height - insetY * 2, 1)
            let weights = points.map(\.weightKg)
            // The goal (already vetted as nearby by the display model) joins the
            // domain so its gridline sits at an honest position.
            let minW = min(weights.min() ?? 0, goalKg ?? .greatestFiniteMagnitude)
            let maxW = max(weights.max() ?? 1, goalKg ?? -.greatestFiniteMagnitude)
            let range = max(maxW - minW, 0.0001)
            let stepX = points.count > 1 ? w / CGFloat(points.count - 1) : 0
            let yFor = { (weightKg: Double) -> CGFloat in
                insetY + h * (1 - CGFloat((weightKg - minW) / range))
            }
            let pts = points.enumerated().map { index, point in
                CGPoint(x: insetX + CGFloat(index) * stepX, y: yFor(point.weightKg))
            }
            let baseY = insetY + h

            ZStack(alignment: .topLeading) {
                if let goalKg {
                    let goalY = yFor(goalKg)
                    Path { path in
                        path.move(to: CGPoint(x: insetX, y: goalY))
                        path.addLine(to: CGPoint(x: insetX + w, y: goalY))
                    }
                    .stroke(WidgetTheme.healthPrimary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Text(goalCaption)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WidgetTheme.healthPrimary)
                        .position(x: insetX + 18, y: max(goalY - 8, insetY))
                } else {
                    // One faint mean gridline for reference (no clutter).
                    Path { path in
                        let y = insetY + h / 2
                        path.move(to: CGPoint(x: insetX, y: y))
                        path.addLine(to: CGPoint(x: insetX + w, y: y))
                    }
                    .stroke(WidgetTheme.chartGrid, lineWidth: 1)
                }

                // Area fill under the line gives the chart its presence.
                Path { path in
                    guard let first = pts.first, let last = pts.last else { return }
                    path.move(to: CGPoint(x: first.x, y: baseY))
                    path.addLine(to: first)
                    for point in pts.dropFirst() { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: last.x, y: baseY))
                    path.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [WidgetTheme.weight.opacity(0.28), WidgetTheme.weight.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                Path { path in
                    for (index, point) in pts.enumerated() {
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(WidgetTheme.weight, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Start-of-journey value by the first plotted point (top-left).
                if let startText, let first = pts.first {
                    Text(startText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WidgetTheme.textTertiary)
                        .position(x: insetX + 16, y: max(first.y - 9, insetY + 7))
                }

                if let last = pts.last {
                    Circle()
                        .fill(WidgetTheme.chartPlotSurface)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(WidgetTheme.weight, lineWidth: 2))
                        .position(last)
                    // Current weight just above the end marker — the only place it
                    // appears now the large-family detail row drops it.
                    if let currentText {
                        Text(currentText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WidgetTheme.weight)
                            .position(x: min(last.x - 2, insetX + w - 24), y: max(last.y - 13, insetY + 8))
                    }
                }
            }
        }
        .background(shape.fill(WidgetTheme.chartPlotSurface))
        .overlay(shape.stroke(WidgetTheme.stroke, lineWidth: 1))
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Lock Screen accessory families (low-detail)

private struct InlineContent: View {
    let display: GlanceDisplay

    var body: some View {
        Label(display.inlineSummary, systemImage: WidgetSymbol.injection)
    }
}

private struct CircularContent: View {
    let display: GlanceDisplay

    var body: some View {
        if let days = display.dayCount {
            Gauge(value: display.progressFraction ?? 0) {
                Image(systemName: WidgetSymbol.injection)
            } currentValueLabel: {
                Text("\(max(days, 0))")
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: WidgetSymbol.injection)
            }
        }
    }
}

private struct RectangularContent: View {
    let display: GlanceDisplay

    var body: some View {
        // `statusPhrase` already encodes the day count ("Next dose in 4 days"),
        // so we never also render `dayCountCaption` ("4 days to next dose") here:
        // the two are alternate phrasings of ONE fact (see GlanceDisplay). Filling
        // the full height (maxHeight) vertically centers the content instead of
        // pinning it to the top-left corner.
        VStack(alignment: .leading, spacing: 3) {
            Label(.widgetBrandGaurava, systemImage: WidgetSymbol.injection)
                .font(.caption2.weight(.semibold))
            Text(display.statusPhrase)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
