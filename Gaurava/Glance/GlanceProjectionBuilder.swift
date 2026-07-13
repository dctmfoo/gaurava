import Foundation

// Pure projection from app model values to a privacy-shaped glance snapshot.
//
// Import-clean (Foundation + the Foundation-only TreatmentMath /
// InjectionSiteRotation). Does NOT import SwiftData, SwiftUI, WidgetKit, or
// DashboardSnapshot, so it stays the single source of truth and can be reused
// by a future watchOS target. Lives app-side because only the app produces
// snapshots; the widget extension only reads them.

struct GlanceProjectionInput: Sendable {
    var startingWeightKg: Double
    var goalWeightKg: Double
    var weightUnit: String
    var weights: [WeightPoint]
    var injections: [InjectionPoint]
    var plannedDoseMg: Double?
    var preferredSites: [String]
    var privacyMode: SurfacePrivacyMode
    var producerBuild: String
    var sourceWatermark: String
    /// When the treatment schedule has no honest countdown — paused, or a stale
    /// dose that needs confirmation — the glance suppresses the next-due math and
    /// shows a calm "no dose scheduled" instead of a misleading overdue.
    var scheduleSuppressed: Bool = false

    struct WeightPoint: Sendable { var weightKg: Double; var recordedAt: Date }
    struct InjectionPoint: Sendable { var doseMg: Double; var site: String; var date: Date }
}

enum GlanceProjectionBuilder {
    static func makeSnapshot(
        from input: GlanceProjectionInput,
        now: Date = Date(),
        ttl: TimeInterval = GauravaSurface.defaultTTL,
        calendar: Calendar = .current
    ) -> GauravaGlanceSnapshot {
        let currentWeight = TreatmentMath.latestWeightKg(input.weights.map { ($0.weightKg, $0.recordedAt) })
        let progressFraction = TreatmentMath.progress(
            startingWeightKg: input.startingWeightKg,
            goalWeightKg: input.goalWeightKg,
            currentWeightKg: currentWeight
        )
        let totalLost = TreatmentMath.totalLostKg(startingWeightKg: input.startingWeightKg, currentWeightKg: currentWeight)

        let sortedInjections = input.injections.sorted { $0.date > $1.date }
        let lastInjectionDate = sortedInjections.first?.date
        let rawNextDate = TreatmentMath.nextInjectionDate(afterLastInjectionDate: lastInjectionDate, calendar: calendar)
        let rawDaysUntil = TreatmentMath.dayCount(from: now, to: rawNextDate, calendar: calendar)
        // Paused or stale (needs confirmation): suppress the countdown so the
        // glance shows a calm "no dose scheduled" instead of a misleading overdue.
        let nextDate = input.scheduleSuppressed ? nil : rawNextDate
        let daysUntil = input.scheduleSuppressed ? nil : rawDaysUntil
        let lastSite = sortedInjections.first?.site
        let suggestedSite = InjectionSiteRotation.suggestedSite(after: lastSite, preferredSites: input.preferredSites)
        // When the schedule is suppressed (paused / needs confirmation) the surface shows a
        // calm "no dose scheduled"; don't leak a planned or logged dose that has no date
        // beside it — that reads as a half-rendered overdue.
        let dose = input.scheduleSuppressed ? nil : (input.plannedDoseMg ?? sortedInjections.first?.doseMg)

        let status = SafeStatusSlice.nextDose(daysUntil: daysUntil)

        let nextAction: NextActionSlice?
        let progress: ProgressSlice?
        let trend: TrendSlice?

        switch input.privacyMode {
        case .full:
            nextAction = NextActionSlice(daysUntilNextInjection: daysUntil, nextInjectionDate: nextDate, doseMg: dose, suggestedSite: suggestedSite, doseBandIndex: doseColorBandIndex(dose))
            progress = ProgressSlice(
                progressToGoal: progressFraction,
                currentWeightKg: currentWeight,
                totalLostKg: totalLost,
                startingWeightKg: input.startingWeightKg,
                goalWeightKg: input.goalWeightKg,
                weightUnit: input.weightUnit
            )
            // The WHOLE journey, not a trailing window. A windowed delta
            // (first-of-window → now) understates the real loss and disagrees
            // with the all-time "since you started" figure shown beside it.
            // Downsample so the App Group payload stays small while the plotted
            // span (and its start/now end labels) stays honest.
            trend = TrendSlice(points: GlanceProjectionBuilder.downsampleEvenly(
                input.weights
                    .sorted { $0.recordedAt < $1.recordedAt }
                    .map { TrendPoint(date: $0.recordedAt, weightKg: $0.weightKg) },
                max: 20))
        case .minimal:
            nextAction = NextActionSlice(daysUntilNextInjection: daysUntil, nextInjectionDate: nextDate, doseMg: dose, suggestedSite: suggestedSite, doseBandIndex: doseColorBandIndex(dose))
            progress = ProgressSlice(
                progressToGoal: progressFraction,
                currentWeightKg: nil,
                totalLostKg: nil,
                startingWeightKg: nil,
                goalWeightKg: nil,
                weightUnit: input.weightUnit
            )
            trend = nil
        case .redacted:
            nextAction = NextActionSlice(daysUntilNextInjection: daysUntil, nextInjectionDate: nil, doseMg: nil, suggestedSite: nil)
            progress = nil
            trend = nil
        }

        return GauravaGlanceSnapshot(
            schemaVersion: GauravaSurface.schemaVersion,
            producerBuild: input.producerBuild,
            generatedAt: now,
            expiresAt: now.addingTimeInterval(ttl),
            sourceWatermark: input.sourceWatermark,
            privacyMode: input.privacyMode,
            renderPolicyVersion: 1,
            nextAction: nextAction,
            progress: progress,
            trend: trend,
            status: status
        )
    }

    /// Evenly subsamples by index to at most `max` points, always preserving the
    /// first and last so the plotted span — and the start/now end labels derived
    /// from it — stay honest. A no-op when already within budget. Deterministic
    /// and Foundation-only (no `Date.now`/randomness), so resume/tests are stable.
    static func downsampleEvenly(_ points: [TrendPoint], max maxCount: Int) -> [TrendPoint] {
        let count = points.count
        guard count > maxCount, maxCount >= 2 else { return points }
        var result: [TrendPoint] = []
        result.reserveCapacity(maxCount)
        var lastIndex = -1
        for step in 0..<maxCount {
            let index = Int((Double(step) / Double(maxCount - 1) * Double(count - 1)).rounded())
            if index != lastIndex {
                result.append(points[index])
                lastIndex = index
            }
        }
        return result
    }

}
