import Foundation

// Phase 0 data contract for onboarding honesty (see
// docs/onboarding-issues-and-fixes.html). These types are Foundation-only so
// both the in-app view model (DashboardSnapshot) and the import-clean glance /
// Live Activity projections can share one definition of treatment state.

/// Where the user is in treatment. Persisted on `TrackerProfile` as an optional
/// raw string (CloudKit-safe); a nil raw value reads as `.unknown`. This is the
/// source of truth for post-onboarding state — it is never inferred only from a
/// dose date.
enum TreatmentStatus: String, CaseIterable, Sendable, Codable {
    case unknown
    case startingNow = "starting_now"
    case active
    case paused
}

/// How confident the app is about the next-injection schedule. Drives whether a
/// countdown is shown and whether overdue is honest (small, recent) or should
/// instead ask the user to confirm their most recent dose.
enum ScheduleAnchorState: String, CaseIterable, Sendable, Codable {
    case unknown
    case plannedWeekday = "planned_weekday"
    case confirmedLatestDose = "confirmed_latest_dose"
    case staleNeedsConfirmation = "stale_needs_confirmation"
    case paused
}

/// The rendered schedule state, derived ONCE from the durable contract so every
/// surface agrees. A historical first dose or a stale latest dose can never turn
/// into a giant overdue count: past the stale threshold the state becomes
/// `.needsConfirmation` instead of an alarming negative day count.
enum TreatmentScheduleState: Equatable, Sendable {
    /// Treatment is paused — no due / overdue / needs-logging anywhere.
    case paused
    /// A provisional weekly plan from the preferred weekday, before any real dose.
    /// Always in the future; never reads as today or overdue.
    case planned(next: Date)
    /// A confirmed most-recent dose anchors the next due date. `dayCount` is the
    /// whole-day count from today to `next`: positive = upcoming, 0 = due,
    /// negative (but within the stale threshold) = honestly overdue / needs logging.
    case scheduled(next: Date, dayCount: Int)
    /// The confirmed dose is stale (more overdue than the threshold), or the user
    /// is active without any confirmed recent dose. Ask for the most recent dose
    /// rather than showing a giant overdue count.
    case needsConfirmation
    /// Nothing to schedule yet (unknown status, no weekday, no dose). Calm — no
    /// countdown, no CTA pressure beyond an optional "log your first dose".
    case idle

    /// Confirmed cadence date, only when `.scheduled`.
    var scheduledDate: Date? {
        if case let .scheduled(next, _) = self { return next }
        return nil
    }

    /// Whole-day count to the confirmed date, only when `.scheduled`.
    var scheduledDayCount: Int? {
        if case let .scheduled(_, days) = self { return days }
        return nil
    }

    /// Provisional plan date, only when `.planned`.
    var plannedDate: Date? {
        if case let .planned(next) = self { return next }
        return nil
    }

    var isPaused: Bool { self == .paused }
    var needsConfirmation: Bool { self == .needsConfirmation }
}

/// Single source of truth for turning the persisted treatment contract into a
/// rendered schedule state. Foundation-only and fully deterministic so it can be
/// unit-tested and shared with the glance / Live Activity projections.
enum TreatmentScheduleEngine {
    /// Days after which an overdue confirmed dose is treated as stale: instead of
    /// a large overdue count the app asks the user to confirm their recent dose.
    static let staleOverdueThresholdDays = 14

    static func state(
        status: TreatmentStatus,
        anchorDate: Date?,
        newestInjectionDate: Date?,
        preferredInjectionDay: Int?,
        isPaused: Bool,
        intervalDays: Int = TreatmentMath.injectionIntervalDays,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TreatmentScheduleState {
        if isPaused || status == .paused { return .paused }

        // The effective anchor is the most recent CONFIRMED dose: a logged
        // injection always wins; otherwise the onboarding-provided anchor date.
        let effectiveAnchor = [newestInjectionDate, anchorDate].compactMap { $0 }.max()

        if let effectiveAnchor,
           let next = calendar.date(byAdding: .day, value: intervalDays, to: effectiveAnchor),
           let days = TreatmentMath.dayCount(from: now, to: next, calendar: calendar) {
            // Overdue beyond the stale threshold → ask for confirmation, never a
            // giant overdue count.
            if days < -staleOverdueThresholdDays { return .needsConfirmation }
            return .scheduled(next: next, dayCount: days)
        }

        // No confirmed dose. An active / mid-treatment user with no recent dose is
        // asked to confirm one rather than being given a provisional plan.
        switch status {
        case .active:
            return .needsConfirmation
        case .startingNow, .unknown:
            if let projected = TreatmentMath.projectedNextInjectionDate(
                weekday: preferredInjectionDay,
                from: now,
                calendar: calendar
            ) {
                return .planned(next: projected)
            }
            return .idle
        case .paused:
            return .paused
        }
    }
}

extension TreatmentPause {
    /// The active-pause predicate from the schedule state machine: started, not
    /// ended, and either no resume scheduled or a resume that is still in the
    /// future. An active pause suppresses due / overdue across every surface.
    func isActive(asOf now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard startedAt <= now, endedAt == nil else { return false }
        if let resumedOnDate {
            return calendar.startOfDay(for: resumedOnDate) > calendar.startOfDay(for: now)
        }
        return true
    }
}
