import ActivityKit
import Foundation

// Pure decision for the injection-day Live Activity (Build 4).
//
// Import-clean app-side logic (ActivityKit for the ContentState type + the
// Foundation-only TreatmentMath). Like GlanceProjectionBuilder it does NOT
// import SwiftData, SwiftUI, WidgetKit, or DashboardSnapshot, and derives the
// activity state from the SAME projection inputs as the glance snapshot — the
// activity never gets its own SwiftData access. This keeps "next injection",
// "due today", and "suggested site" defined exactly once (in TreatmentMath).
//
// Privacy is applied here, producer-side: under a restrictive mode the dose and
// site are dropped before the activity is started/updated, mirroring the glance
// projection. The activity therefore never carries values it must hide.

/// The inputs the projection needs — all primitives, no model objects.
struct InjectionActivityInput: Sendable {
    var optedIn: Bool
    var privacyMode: SurfacePrivacyMode
    var lastInjectionDate: Date?
    var lastInjectionSite: String?
    var plannedDoseMg: Double?
    var lastDoseMg: Double?
    var preferredSites: [String]
    /// Active treatment pause: while paused there is no due/overdue, so no
    /// injection Live Activity should run.
    var isPaused: Bool
    /// Hours after the due day's start at which the window closes. The activity
    /// must not remain stale past this. Defaults to a full day (the due day).
    var windowHours: Int

    init(
        optedIn: Bool,
        privacyMode: SurfacePrivacyMode,
        lastInjectionDate: Date?,
        lastInjectionSite: String? = nil,
        plannedDoseMg: Double?,
        lastDoseMg: Double?,
        preferredSites: [String],
        isPaused: Bool = false,
        windowHours: Int = 24
    ) {
        self.optedIn = optedIn
        self.privacyMode = privacyMode
        self.lastInjectionDate = lastInjectionDate
        self.lastInjectionSite = lastInjectionSite
        self.plannedDoseMg = plannedDoseMg
        self.lastDoseMg = lastDoseMg
        self.preferredSites = preferredSites
        self.isPaused = isPaused
        self.windowHours = windowHours
    }
}

/// What the controller should do with the (at most one) running activity.
enum InjectionActivityDecision: Equatable, Sendable {
    /// No activity should be running — end any that is.
    case inactive
    /// An activity should be running with this content — start or update it.
    case active(GauravaInjectionActivityAttributes.ContentState)
    /// Today's injection is logged — show a brief confirmation, then end. Only
    /// acts on an already-running activity; never starts a fresh one.
    case completed(GauravaInjectionActivityAttributes.ContentState)
}

enum InjectionActivityProjection {
    static func decide(
        input: InjectionActivityInput,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> InjectionActivityDecision {
        guard input.optedIn else { return .inactive }
        // Paused treatment suppresses the injection activity entirely.
        guard !input.isPaused else { return .inactive }

        // "Logged today" means the most recent injection is today — the user has
        // already taken (or recorded) the dose, so today's activity is complete.
        let loggedToday = input.lastInjectionDate
            .map { calendar.isDate($0, inSameDayAs: now) } ?? false
        if loggedToday {
            // Confirmation state; the controller only ends an existing activity.
            let dueDate = calendar.startOfDay(for: now)
            let windowEnd = windowEnd(dueDate: dueDate, hours: input.windowHours, calendar: calendar)
            return .completed(makeState(
                dueDate: dueDate,
                windowEnd: windowEnd,
                statusKind: .logged,
                input: input,
                isCompleted: true
            ))
        }

        // Otherwise the activity is only relevant on the due day itself.
        let nextDate = TreatmentMath.nextInjectionDate(
            afterLastInjectionDate: input.lastInjectionDate,
            calendar: calendar
        )
        guard let nextDate,
              let daysUntil = TreatmentMath.dayCount(from: now, to: nextDate, calendar: calendar),
              daysUntil <= 0 else {
            return .inactive
        }

        let dueDate = calendar.startOfDay(for: nextDate)
        let windowEnd = windowEnd(dueDate: dueDate, hours: input.windowHours, calendar: calendar)
        // Cannot remain stale past the due window.
        guard now < windowEnd else { return .inactive }

        return .active(makeState(
            dueDate: dueDate,
            windowEnd: windowEnd,
            statusKind: daysUntil < 0 ? .overdue : .dueToday,
            input: input,
            isCompleted: false
        ))
    }

    // MARK: - Helpers

    private static func windowEnd(dueDate: Date, hours: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .hour, value: hours, to: dueDate)
            ?? dueDate.addingTimeInterval(TimeInterval(hours) * 3600)
    }

    private static func makeState(
        dueDate: Date,
        windowEnd: Date,
        statusKind: GauravaInjectionActivityAttributes.StatusKind,
        input: InjectionActivityInput,
        isCompleted: Bool
    ) -> GauravaInjectionActivityAttributes.ContentState {
        let dose = input.plannedDoseMg ?? input.lastDoseMg
        let site = InjectionSiteRotation.suggestedSite(
            after: input.lastInjectionSite,
            preferredSites: input.preferredSites
        )

        // Producer-side redaction: hide exact dose/site under restrictive modes.
        let showsDetail = input.privacyMode == .full || input.privacyMode == .minimal
        return GauravaInjectionActivityAttributes.ContentState(
            dueDate: dueDate,
            windowEnd: windowEnd,
            statusKind: statusKind,
            statusPhrase: nil,
            doseMg: showsDetail ? dose : nil,
            suggestedSite: showsDetail ? site : nil,
            isCompleted: isCompleted
        )
    }
}
