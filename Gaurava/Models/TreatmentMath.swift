import Foundation

// Single source of truth for clinically meaningful derivations.
//
// These rules previously lived as computed properties on DashboardSnapshot,
// which imports SwiftUI and carries Color. The glance-surface projection
// (see docs/widget-options-deep-dive.html) must stay import-clean and cannot
// depend on DashboardSnapshot, so the math lives here, in Foundation only,
// and both the in-app view model and the projection call it. This prevents a
// second, divergent definition of values like "next injection date".
//
// Behavior is intentionally identical to the original DashboardSnapshot
// computed properties; this is a refactor, not a logic change.
enum TreatmentMath {
    /// Default cadence between injections, in days.
    static let injectionIntervalDays = 7

    /// Most recent weight value by recording time, or nil if there are none.
    static func latestWeightKg(_ samples: [(weightKg: Double, recordedAt: Date)]) -> Double? {
        samples.sorted { $0.recordedAt > $1.recordedAt }.first?.weightKg
    }

    /// Total weight change from the starting weight, or nil without a current weight.
    static func totalLostKg(startingWeightKg: Double, currentWeightKg: Double?) -> Double? {
        guard let currentWeightKg else { return nil }
        return startingWeightKg - currentWeightKg
    }

    /// Progress toward goal, clamped to 0...1. Returns 0 when undefined.
    static func progress(startingWeightKg: Double, goalWeightKg: Double, currentWeightKg: Double?) -> Double {
        guard let currentWeightKg else { return 0 }
        let span = startingWeightKg - goalWeightKg
        guard span > 0 else { return 0 }
        return min(max((startingWeightKg - currentWeightKg) / span, 0), 1)
    }

    /// Projected next injection date: the latest injection plus the cadence.
    static func nextInjectionDate(
        afterLastInjectionDate lastInjectionDate: Date?,
        intervalDays: Int = injectionIntervalDays,
        calendar: Calendar = .current
    ) -> Date? {
        guard let lastInjectionDate else { return nil }
        return calendar.date(byAdding: .day, value: intervalDays, to: lastInjectionDate)
    }

    /// Whole-day count from `now` to `target`, comparing start-of-day to start-of-day.
    static func dayCount(from now: Date, to target: Date?, calendar: Calendar = .current) -> Int? {
        guard let target else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: target)
        ).day
    }

    /// Provisional next-injection date for a never-logged plan: the next future
    /// occurrence of the user's preferred injection weekday. Used only when there
    /// are no logged injections, surfaced as a visibly provisional plan.
    ///
    /// Encoding: `preferredInjectionDay` is stored 0-based with Sunday == 0 (it
    /// indexes `Calendar.weekdaySymbols`), while `Calendar`'s `.weekday` component
    /// is 1-based with Sunday == 1, so the value is converted with `+ 1`. A nil
    /// weekday (the toggle is off) is a no-op and returns nil.
    ///
    /// When `from` already falls on the chosen weekday we deliberately project to
    /// NEXT week rather than today: a brand-new, never-logged plan must never tell
    /// the user to inject today. The result is always start-of-day and strictly in
    /// the future (1...7 days out).
    static func projectedNextInjectionDate(
        weekday preferredInjectionDay: Int?,
        from now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let preferredInjectionDay else { return nil }
        let targetWeekday = preferredInjectionDay + 1
        let startOfToday = calendar.startOfDay(for: now)
        let currentWeekday = calendar.component(.weekday, from: startOfToday)
        var delta = ((targetWeekday - currentWeekday) % 7 + 7) % 7
        if delta == 0 { delta = 7 } // today is the chosen weekday -> next week
        return calendar.date(byAdding: .day, value: delta, to: startOfToday)
    }
}
