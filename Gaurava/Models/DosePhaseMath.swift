import Foundation

// Per-dose weight attribution for the Results "By Dose" ledger and the trend
// chart's phase bands.
//
// A "phase" is one contiguous run of injections at the same dose; revisiting a
// dose later starts a new phase, because "what happened while I was on 5 mg
// this time" is the question the ledger answers. Like TreatmentMath, this is
// Foundation-only math so it stays testable and import-clean.
//
// Boundary weights are linear interpolations between the recorded samples
// nearest each phase boundary, clamped to the recorded range. Consecutive
// phases therefore share their boundary weight, so per-phase changes
// telescope: their sum equals the overall change across the covered span and
// the ledger can never disagree with the headline total above it.

struct DosePhase: Identifiable, Equatable {
    let doseMg: Double
    /// First injection date of the run.
    let start: Date
    /// First injection date of the next run; nil while this dose is current.
    let end: Date?
    let injectionCount: Int
    /// Estimated weight at the phase boundaries; nil when the phase window has
    /// no overlap with the recorded weight span.
    let startWeightKg: Double?
    let endWeightKg: Double?
    /// Whole days covered, measured to `end` or to the build-time `now`.
    let days: Int
    /// Whole days of recorded treatment pause overlapping the phase window.
    let pausedDays: Int

    var id: String { "\(start.timeIntervalSince1970)-\(doseMg)" }

    var isOngoing: Bool { end == nil }

    /// Days actually on the dose: the calendar window minus recorded pauses.
    /// This is what "N weeks on 7.5 mg" must mean — a two-week travel pause
    /// is not time on the dose.
    var activeDays: Int { max(0, days - pausedDays) }

    /// Weight change across the phase; negative means loss.
    var changeKg: Double? {
        guard let startWeightKg, let endWeightKg else { return nil }
        return endWeightKg - startWeightKg
    }

    /// Average change per week of active (unpaused) time on the dose. Nil
    /// under one active week — a rate extrapolated from a few days reads as
    /// more signal than it is.
    var weeklyRateKg: Double? {
        guard let changeKg, activeDays >= 7 else { return nil }
        return changeKg / (Double(activeDays) / 7)
    }
}

enum DosePhaseMath {
    /// Groups injections into contiguous same-dose runs and estimates the
    /// weight change across each run's window. Input order does not matter.
    /// `pauses` are recorded treatment pauses (`end` nil while still open);
    /// their overlap with a phase is excluded from that phase's active time.
    static func phases(
        injections: [(doseMg: Double, injectionDate: Date)],
        weights: [(weightKg: Double, recordedAt: Date)],
        pauses: [(start: Date, end: Date?)] = [],
        now: Date = Date()
    ) -> [DosePhase] {
        let orderedInjections = injections.sorted { $0.injectionDate < $1.injectionDate }
        guard !orderedInjections.isEmpty else { return [] }

        var runs: [(doseMg: Double, start: Date, count: Int)] = []
        for injection in orderedInjections {
            if let last = runs.last, abs(last.doseMg - injection.doseMg) < 0.001 {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((injection.doseMg, injection.injectionDate, 1))
            }
        }

        let orderedWeights = weights.sorted { $0.recordedAt < $1.recordedAt }

        let pauseIntervals = mergedPauseIntervals(pauses, openEnd: max(now, orderedInjections.last?.injectionDate ?? now))

        return runs.enumerated().map { index, run in
            let end = index + 1 < runs.count ? runs[index + 1].start : nil
            let windowEnd = end ?? max(now, run.start)
            let boundaries = boundaryWeights(start: run.start, end: windowEnd, weights: orderedWeights)
            return DosePhase(
                doseMg: run.doseMg,
                start: run.start,
                end: end,
                injectionCount: run.count,
                startWeightKg: boundaries?.start,
                endWeightKg: boundaries?.end,
                days: max(0, Int(windowEnd.timeIntervalSince(run.start) / 86_400)),
                pausedDays: pausedDays(start: run.start, end: windowEnd, pauses: pauseIntervals)
            )
        }
    }

    /// Pauses sorted and merged into disjoint intervals; an open pause runs to
    /// `openEnd` so it can overlap the ongoing phase.
    private static func mergedPauseIntervals(
        _ pauses: [(start: Date, end: Date?)],
        openEnd: Date
    ) -> [(start: Date, end: Date)] {
        let closed = pauses
            .map { (start: $0.start, end: $0.end ?? openEnd) }
            .filter { $0.start < $0.end }
            .sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        for pause in closed {
            if let last = merged.indices.last, merged[last].end >= pause.start {
                merged[last].end = max(merged[last].end, pause.end)
            } else {
                merged.append(pause)
            }
        }
        return merged
    }

    /// Whole days of pause time inside [start, end].
    private static func pausedDays(
        start: Date,
        end: Date,
        pauses: [(start: Date, end: Date)]
    ) -> Int {
        let overlap = pauses.reduce(0.0) { total, pause in
            let lower = max(pause.start, start)
            let upper = min(pause.end, end)
            return upper > lower ? total + upper.timeIntervalSince(lower) : total
        }
        return Int(overlap / 86_400)
    }

    private static func boundaryWeights(
        start: Date,
        end: Date,
        weights: [(weightKg: Double, recordedAt: Date)]
    ) -> (start: Double, end: Double)? {
        guard let first = weights.first, let last = weights.last else { return nil }
        // Without overlap between the phase window and the recorded span, both
        // boundaries would clamp to the same sample and report a meaningless 0.0.
        guard end >= first.recordedAt, start <= last.recordedAt else { return nil }
        guard let startWeight = interpolatedWeight(at: start, weights: weights),
              let endWeight = interpolatedWeight(at: end, weights: weights) else { return nil }
        return (startWeight, endWeight)
    }

    /// Linear interpolation between the samples bracketing `date`, clamped to
    /// the first/last sample outside the recorded range. `weights` must be
    /// sorted ascending by `recordedAt`.
    static func interpolatedWeight(
        at date: Date,
        weights: [(weightKg: Double, recordedAt: Date)]
    ) -> Double? {
        guard let first = weights.first, let last = weights.last else { return nil }
        if date <= first.recordedAt { return first.weightKg }
        if date >= last.recordedAt { return last.weightKg }
        for index in 1..<weights.count {
            let lower = weights[index - 1]
            let upper = weights[index]
            guard upper.recordedAt >= date else { continue }
            let span = upper.recordedAt.timeIntervalSince(lower.recordedAt)
            guard span > 0 else { return upper.weightKg }
            let fraction = date.timeIntervalSince(lower.recordedAt) / span
            return lower.weightKg + (upper.weightKg - lower.weightKg) * fraction
        }
        return last.weightKg
    }
}
