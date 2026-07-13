import Foundation

// Pure decision layer for the local injection reminder (see
// docs/injection-reminders-plan.html).
//
// Mirrors InjectionActivityProjection / GlanceProjectionBuilder: a Foundation-only,
// deterministic function that decides WHAT the reminder should be, with zero
// UserNotifications import. It reuses TreatmentScheduleEngine.state verbatim, so
// suppression falls straight out of the engine's existing cases — there is no new
// "is it paused?" logic here. Everything is injectable (now, calendar, fireHour)
// so the whole matrix is unit-testable with no simulator, exactly like the
// existing projections.
//
// v1 scope (owner-decided defaults): confirmed-only (remind only on a real
// `.scheduled` anchor, never a provisional `.planned` weekday), 09:00 local fire
// time, and privacy-shaped content so the lock screen honours SurfacePrivacyMode.
enum InjectionReminderPlan {
    /// The privacy-shaped payload the reminder should carry. The pure layer bakes
    /// the privacy decision in here (which facts are present), so the impure copy
    /// renderer never holds a value it must hide — the same producer-side redaction
    /// the glance and Live Activity use.
    struct Content: Equatable, Sendable {
        /// What clinical detail, if any, the lock-screen copy may reveal.
        enum Detail: Equatable, Sendable {
            /// Full mode: medication + dose may be shown.
            case detailed(medication: Medication?, doseMg: Double?)
            /// Minimal mode: timing only, no medication or dose.
            case timing
            /// Redacted mode: nothing clinical — a generic nudge.
            case generic
        }

        var detail: Detail
        /// Whole days from the moment the reminder fires to the due date (>= 0):
        /// 0 = "due today", 1 = "due tomorrow", n = "due in n days". Drives the
        /// timing phrase regardless of privacy mode.
        var daysUntilDueAtFire: Int
    }

    /// What the scheduler should do with the single pending reminder.
    enum Decision: Equatable, Sendable {
        /// No reminder should exist — remove any pending one.
        case none
        /// A reminder should fire at `fireDate` with this content — replace any
        /// pending one with it. `dueDate` is the start-of-day of the dose this
        /// reminder is for: it is the stable identity the scheduler fingerprints on,
        /// so a short-fuse reminder (whose `fireDate` is "soon" and shifts on every
        /// foreground) is not perpetually rescheduled before it can deliver.
        case schedule(fireDate: Date, dueDate: Date, content: Content)
    }

    /// Decide the reminder from the same schedule state every other surface trusts.
    ///
    /// - Parameters:
    ///   - scheduleState: the rendered state from `TreatmentScheduleEngine.state`.
    ///   - reminderDaysBefore: lead time from `TrackerProfile.reminderDaysBefore`.
    ///   - optedIn: the per-device App Group opt-in flag (default off).
    ///   - authorized: whether the user has granted notification authorization.
    ///   - privacy: the per-device `SurfacePrivacyMode` (shapes the content).
    ///   - doseMg / medication: shown only under `.full` privacy.
    ///   - fireHour: local hour to fire on the (due − daysBefore) day. v1 = 09:00.
    static func decide(
        scheduleState: TreatmentScheduleState,
        reminderDaysBefore: Int,
        optedIn: Bool,
        authorized: Bool,
        privacy: SurfacePrivacyMode,
        doseMg: Double?,
        medication: Medication?,
        fireHour: Int = 9,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Decision {
        // Off, or no system permission → never schedule.
        guard optedIn, authorized else { return .none }

        // Confirmed-only for v1: only a real `.scheduled` anchor earns a reminder.
        // `.paused` / `.needsConfirmation` / `.idle` / `.planned` all stay silent —
        // suppression falls straight out of the engine's cases.
        guard case let .scheduled(next, dayCount) = scheduleState else { return .none }

        // Already overdue (negative day count, still within the stale threshold):
        // the in-app card owns the overdue conversation — don't nag from the lock
        // screen.
        guard dayCount >= 0 else { return .none }

        let daysBefore = max(0, reminderDaysBefore)
        // The reminder fires on the (due − daysBefore) day, at `fireHour` local.
        // Calendar arithmetic keeps it DST-safe.
        let dueDay = calendar.startOfDay(for: next)
        let fireDay = calendar.date(byAdding: .day, value: -daysBefore, to: dueDay) ?? dueDay
        let idealFire = calendar.date(bySettingHour: fireHour, minute: 0, second: 0, of: fireDay) ?? fireDay

        if idealFire > now {
            // Normal case: at fire time the dose is `daysBefore` days out.
            return .schedule(
                fireDate: idealFire,
                dueDate: dueDay,
                content: makeContent(privacy: privacy, medication: medication, doseMg: doseMg, daysUntilDueAtFire: daysBefore)
            )
        }

        // Past-date guard: the ideal "day before" moment has already passed, but the
        // dose is still upcoming or due today (dayCount >= 0). A reminder scheduled in
        // the past would never deliver, so fire a short-fuse "due today / due in N"
        // nudge instead. The day count at fire time is the live `dayCount`.
        let shortFuse = calendar.date(byAdding: .minute, value: 1, to: now) ?? now
        return .schedule(
            fireDate: shortFuse,
            dueDate: dueDay,
            content: makeContent(privacy: privacy, medication: medication, doseMg: doseMg, daysUntilDueAtFire: dayCount)
        )
    }

    private static func makeContent(
        privacy: SurfacePrivacyMode,
        medication: Medication?,
        doseMg: Double?,
        daysUntilDueAtFire: Int
    ) -> Content {
        let detail: Content.Detail
        switch privacy {
        case .full:
            detail = .detailed(medication: medication, doseMg: doseMg)
        case .minimal:
            detail = .timing
        case .redacted:
            detail = .generic
        }
        return Content(detail: detail, daysUntilDueAtFire: max(0, daysUntilDueAtFire))
    }
}
