import Foundation

// Pure, Foundation-only render model the widget draws from.
//
// The producer (GlanceProjectionBuilder) already strips values the user chose
// to hide, so the snapshot never carries raw data it must conceal. This layer
// adds the *surface-shape* rule on top of that privacy shaping: Lock Screen /
// accessory families stay low-detail (status + day count, never absolute
// clinical numbers) regardless of privacy mode, while the larger Home Screen
// families surface whatever safe slices survived redaction.
//
// Living in SharedSurfaces keeps it Foundation-only (no WidgetKit/SwiftUI) and
// unit-testable from the app target, which compiles SharedSurfaces too. The
// widget maps WidgetKit's `WidgetFamily` onto `SurfaceFamilyClass`.

enum SurfaceFamilyClass: Sendable, CaseIterable {
    case systemSmall
    case systemMedium
    case systemLarge
    case systemExtraLarge
    case accessoryInline
    case accessoryCircular
    case accessoryRectangular

    /// Lock Screen / Apple Watch style families. Always low-detail.
    var isAccessory: Bool {
        switch self {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular: return true
        default: return false
        }
    }

    /// Families large enough to carry a trend sparkline when data is present.
    var allowsTrend: Bool {
        self == .systemLarge || self == .systemExtraLarge
    }
}

enum SurfaceLocalizedString {
    static func resolve(_ resource: LocalizedStringResource, locale: Locale) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}

struct GlanceDisplay: Equatable, Sendable {
    // INVARIANT: `statusPhrase` and `dayCountCaption` are two phrasings of the
    // SAME fact. For `.nextDoseInDays` the phrase is "Next dose in 4 days" and the
    // caption is "4 days to next dose". A surface must render AT MOST ONE of them:
    // use the sentence (`statusPhrase`) on its own, OR the hero `dayCount` number
    // paired with `dayCountCaption`. Rendering the sentence AND the caption together
    // reads as a duplicate ("says the same thing twice").
    var statusPhrase: String
    var dayCount: Int?
    var dayCountCaption: String?
    /// Humanized hero for the day count: "Today" / "Tomorrow" for 0–1 days
    /// (a bare "1" is ambiguous at a glance), the plain number for >= 2.
    /// Pairs with `dayCountCaption`, which never restates the count.
    var heroDayText: String? = nil
    /// True when the dose is due (today or overdue) so surfaces can switch to
    /// the attention treatment instead of the everyday calm one.
    var isDoseDue: Bool = false
    var doseText: String?
    /// Producer-computed dose color band index (see `NextActionSlice.doseBandIndex`).
    /// Surfaces map this to their own dose ramp so the dose value reads the same
    /// hue as the app. `nil` whenever no dose is shown (accessory/redacted/expired).
    var doseBandIndex: Int? = nil
    var siteText: String?
    var progressFraction: Double?      // 0...1, always safe to show
    var progressPercentText: String?
    var currentWeightText: String?     // only when .full survived redaction
    /// Signed total change since the starting weight ("−12.4 kg"), the payoff
    /// behind the bare current weight. Only when .full survived redaction and
    /// the change is non-trivial (>= 0.05 kg either way).
    var weightDeltaText: String? = nil
    var trendPoints: [TrendPoint]      // only on large families under .full
    /// Signed change across the visible trend window ("−5.8 kg"); annotates the
    /// chart so it reads as a quantity, not just a shape.
    var trendDeltaText: String? = nil
    /// Goal weight for a chart gridline — only when the goal is close enough to
    /// the trend range to plot without flattening the line (see `nearbyGoal`).
    var trendGoalKg: Double? = nil
    /// Start-of-journey weight for the chart's left end, bare value in the display
    /// unit ("98"); the unit is carried by the nearby current-weight label.
    var trendStartText: String? = nil
    /// Goal weight for the gridline label, bare value ("80"); the view pairs it
    /// with the localized "Goal".
    var trendGoalText: String? = nil
    var inlineSummary: String          // single-line accessoryInline string

    static let placeholder = GlanceDisplayModel.placeholderDisplay()
}

enum GlanceDisplayModel {
    /// Build the per-family display from a snapshot. Returns `.placeholder` for a
    /// missing snapshot and a refresh-shaped display for an expired one so the
    /// widget never renders silently-stale clinical numbers. The snapshot is
    /// already privacy-shaped by the producer (the app republishes redacted when
    /// the owner changes the Care > Widget Privacy setting), so this layer only
    /// applies the per-family surface-shape rule.
    static func make(
        from snapshot: GauravaGlanceSnapshot?,
        family: SurfaceFamilyClass,
        asOf now: Date = Date(),
        locale: Locale = .current
    ) -> GlanceDisplay {
        guard let snapshot else { return placeholderDisplay(locale: locale) }
        guard !snapshot.isExpired(asOf: now) else {
            return GlanceDisplay(
                statusPhrase: SurfaceLocalizedString.resolve(.glanceStatusOpenToRefresh, locale: locale),
                dayCount: nil,
                dayCountCaption: nil,
                doseText: nil,
                siteText: nil,
                progressFraction: nil,
                progressPercentText: nil,
                currentWeightText: nil,
                trendPoints: [],
                inlineSummary: SurfaceLocalizedString.resolve(.glanceStatusOpenToRefresh, locale: locale)
            )
        }

        let phrase = statusPhrase(from: snapshot.status, locale: locale)
        let days = snapshot.nextAction?.daysUntilNextInjection ?? snapshot.status?.daysUntilNextInjection
        let caption = days.map { dayCaption($0, locale: locale) }
        let hero = days.map { heroDayText($0, locale: locale) }
        let isDue = snapshot.status?.kind == .doseDue || days.map { $0 <= 0 } ?? false

        // Accessory families: status + safe day count / progress only.
        if family.isAccessory {
            let fraction = family == .accessoryCircular ? snapshot.progress?.progressToGoal : nil
            return GlanceDisplay(
                statusPhrase: phrase,
                dayCount: days,
                dayCountCaption: caption,
                heroDayText: hero,
                isDoseDue: isDue,
                doseText: nil,
                siteText: nil,
                progressFraction: fraction,
                progressPercentText: fraction.map { SurfaceDisplayFormatters.percent($0, locale: locale) },
                currentWeightText: nil,
                trendPoints: [],
                inlineSummary: phrase
            )
        }

        let unit = snapshot.progress?.weightUnit ?? "kg"
        let fraction = snapshot.progress?.progressToGoal
        let weightText = snapshot.progress?.currentWeightKg.map {
            SurfaceDisplayFormatters.weight(kg: $0, unit: unit, locale: locale)
        }
        // totalLostKg is positive when weight went DOWN; display the change with
        // its real sign ("−12.4 kg" lost / "+1.2 kg" gained).
        let weightDelta = snapshot.progress?.totalLostKg.flatMap { lost in
            abs(lost) >= 0.05
                ? SurfaceDisplayFormatters.signedWeightChange(kg: -lost, unit: unit, locale: locale)
                : nil
        }
        let points = family.allowsTrend ? (snapshot.trend?.points ?? []) : []
        let hasTrend = points.count >= 2
        // The chart's headline change is the all-time loss since the STARTING
        // weight ("−19 kg · since you started"), not last-point-minus-first-point
        // of the plotted window — a window delta understates the journey and
        // contradicts the row's total. Identical to `weightDeltaText`; shown only
        // where the chart actually renders.
        let trendDelta: String? = hasTrend ? weightDelta : nil
        // Endpoint + goal labels for the plot. The goal is computed once and
        // reused for both the gridline and its label so they can never disagree.
        let goalForGrid = hasTrend ? nearbyGoal(snapshot.progress?.goalWeightKg, points: points) : nil
        let trendStart = hasTrend ? points.first.map {
            SurfaceDisplayFormatters.weightValue(kg: $0.weightKg, unit: unit, locale: locale)
        } : nil
        let trendGoalLabel = goalForGrid.map {
            SurfaceDisplayFormatters.weightValue(kg: $0, unit: unit, locale: locale)
        }

        return GlanceDisplay(
            statusPhrase: phrase,
            dayCount: days,
            dayCountCaption: caption,
            heroDayText: hero,
            isDoseDue: isDue,
            doseText: snapshot.nextAction?.doseMg.map { SurfaceDisplayFormatters.dose(mg: $0, locale: locale) },
            doseBandIndex: snapshot.nextAction?.doseBandIndex,
            siteText: snapshot.nextAction?.suggestedSite.map { localizedInjectionSite($0, locale: locale) },
            progressFraction: fraction,
            progressPercentText: fraction.map { SurfaceDisplayFormatters.percent($0, locale: locale) },
            currentWeightText: weightText,
            weightDeltaText: weightDelta,
            trendPoints: points,
            trendDeltaText: trendDelta,
            trendGoalKg: goalForGrid,
            trendStartText: trendStart,
            trendGoalText: trendGoalLabel,
            inlineSummary: phrase
        )
    }

    // MARK: - Formatting (Foundation only)

    static func placeholderDisplay(locale: Locale = .current) -> GlanceDisplay {
        GlanceDisplay(
            statusPhrase: SurfaceLocalizedString.resolve(.glanceStatusOpenGaurava, locale: locale),
            dayCount: nil,
            dayCountCaption: nil,
            doseText: nil,
            siteText: nil,
            progressFraction: nil,
            progressPercentText: nil,
            currentWeightText: nil,
            trendPoints: [],
            inlineSummary: SurfaceLocalizedString.resolve(.glanceStatusGaurava, locale: locale)
        )
    }

    private static func statusPhrase(from status: SafeStatusSlice?, locale: Locale) -> String {
        guard let status else { return SurfaceLocalizedString.resolve(.glanceStatusGaurava, locale: locale) }
        switch status.kind {
        case .noDataYet:
            return SurfaceLocalizedString.resolve(.glanceStatusNoDataYet, locale: locale)
        case .noDoseScheduled:
            return SurfaceLocalizedString.resolve(.glanceStatusNoDoseScheduled, locale: locale)
        case .doseDue:
            return SurfaceLocalizedString.resolve(.glanceStatusDoseDue, locale: locale)
        case .nextDoseInDays:
            let days = max(status.daysUntilNextInjection ?? 0, 0)
            if days == 1 { return SurfaceLocalizedString.resolve(.glanceStatusNextDoseTomorrow, locale: locale) }
            return SurfaceLocalizedString.resolve(.glanceStatusNextDoseInDays(days), locale: locale)
        case .none:
            return status.phrase ?? SurfaceLocalizedString.resolve(.glanceStatusGaurava, locale: locale)
        }
    }

    // Hero + caption form one statement and the caption never restates the
    // count: "Today / dose due", "Tomorrow / next dose", "4 / days to next dose".
    // The old numbered caption ("1 day to next dose" under a hero "1") said the
    // same number twice.
    private static func dayCaption(_ days: Int, locale: Locale) -> String {
        if days <= 0 { return SurfaceLocalizedString.resolve(.glanceDayCaptionDoseDue, locale: locale) }
        if days == 1 { return SurfaceLocalizedString.resolve(.glanceDayCaptionNextDose, locale: locale) }
        return SurfaceLocalizedString.resolve(.glanceDayCaptionDaysToNextDoseShort, locale: locale)
    }

    private static func heroDayText(_ days: Int, locale: Locale) -> String {
        if days <= 0 { return SurfaceLocalizedString.resolve(.glanceHeroToday, locale: locale) }
        if days == 1 { return SurfaceLocalizedString.resolve(.glanceHeroTomorrow, locale: locale) }
        return "\(days)"
    }

    /// A goal gridline is only honest when the goal sits near the plotted
    /// window: inside the weight range, or within max(3 kg, one range-height)
    /// outside it. A far-away goal would flatten the trend into a line hugging
    /// the top of the chart, so it stays off until the user approaches it.
    private static func nearbyGoal(_ goal: Double?, points: [TrendPoint]) -> Double? {
        guard let goal else { return nil }
        let weights = points.map(\.weightKg)
        guard let minW = weights.min(), let maxW = weights.max() else { return nil }
        if (minW...maxW).contains(goal) { return goal }
        let threshold = max(3.0, maxW - minW)
        let distance = goal < minW ? minW - goal : goal - maxW
        return distance <= threshold ? goal : nil
    }

    private static func localizedInjectionSite(_ rawSite: String, locale: Locale) -> String {
        let localized: String
        switch rawSite {
        case "Abdomen - Left": localized = SurfaceLocalizedString.resolve(.injectionSiteAbdomenLeft, locale: locale)
        case "Abdomen - Right": localized = SurfaceLocalizedString.resolve(.injectionSiteAbdomenRight, locale: locale)
        case "Thigh - Left": localized = SurfaceLocalizedString.resolve(.injectionSiteThighLeft, locale: locale)
        case "Thigh - Right": localized = SurfaceLocalizedString.resolve(.injectionSiteThighRight, locale: locale)
        case "Upper Arm - Left": localized = SurfaceLocalizedString.resolve(.injectionSiteUpperArmLeft, locale: locale)
        case "Upper Arm - Right": localized = SurfaceLocalizedString.resolve(.injectionSiteUpperArmRight, locale: locale)
        default: localized = rawSite
        }
        // Glance surfaces render the area/side pair with a middle dot — quieter
        // than the data-layer hyphen at widget sizes. Every locale's catalog
        // value keeps the " - " separator, so this stays a display-only swap.
        return localized.replacingOccurrences(of: " - ", with: " · ")
    }
}

enum SurfaceDisplayFormatters {
    static func percent(_ fraction: Double, locale: Locale = .current) -> String {
        let clamped = min(max(fraction, 0), 1)
        return clamped.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    static func dose(mg: Double, locale: Locale = .current) -> String {
        measurement(value: mg, unit: UnitMass.milligrams, locale: locale, minFraction: 0, maxFraction: 2)
    }

    static func weight(kg: Double, unit: String, locale: Locale = .current) -> String {
        if unit.lowercased().hasPrefix("lb") {
            return measurement(value: kg * 2.204_622_621_85, unit: UnitMass.pounds, locale: locale, minFraction: 1, maxFraction: 1)
        }
        return measurement(value: kg, unit: UnitMass.kilograms, locale: locale, minFraction: 1, maxFraction: 1)
    }

    /// A bare weight VALUE in the display unit — no unit suffix, rounded to whole
    /// numbers — for compact chart axis labels ("98", "80") where a nearby
    /// labelled value already establishes kg vs lb.
    static func weightValue(kg: Double, unit: String, locale: Locale = .current) -> String {
        let value = unit.lowercased().hasPrefix("lb") ? kg * 2.204_622_621_85 : kg
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
    }

    /// A weight CHANGE with an explicit sign: "−12.4 kg" / "+1.2 kg". The sign
    /// is always shown (U+2212 minus, not a hyphen) because the delta is the
    /// point of the string.
    static func signedWeightChange(kg: Double, unit: String, locale: Locale = .current) -> String {
        (kg < 0 ? "−" : "+") + weight(kg: abs(kg), unit: unit, locale: locale)
    }

    static func dateRange(_ start: Date, _ end: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start, to: end)
    }

    private static func measurement(
        value: Double,
        unit: UnitMass,
        locale: Locale,
        minFraction: Int,
        maxFraction: Int
    ) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = locale
        numberFormatter.minimumFractionDigits = minFraction
        numberFormatter.maximumFractionDigits = maxFraction

        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter = numberFormatter
        return formatter.string(from: Measurement(value: value, unit: unit))
    }
}
