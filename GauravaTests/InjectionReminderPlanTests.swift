import XCTest
@testable import Gaurava

// Coverage for the pure injection-reminder decision layer (see
// docs/injection-reminders-plan.html, Component 1). Like the schedule-engine and
// Live-Activity-projection tests, this derives everything from primitives with an
// injected calendar + `now`, so the full suppression matrix, the past-date guard,
// the day-offset math, and privacy shaping are locked without a simulator.
final class InjectionReminderPlanTests: XCTestCase {
    // Pinned to UTC so the 09:00 fire-hour reasoning is deterministic on any host.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    // A fixed mid-afternoon reference: today 09:00 is in the past, tomorrow 09:00
    // is in the future — the two cases the fire-time math must split on.
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14, minute: 0))!

    /// A due date `days` out from `now`, at noon (time-of-day is irrelevant — the
    /// plan anchors to start-of-day).
    private func due(inDays days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!)!
    }

    private func decide(
        state: TreatmentScheduleState,
        daysBefore: Int = 1,
        optedIn: Bool = true,
        authorized: Bool = true,
        privacy: SurfacePrivacyMode = .full,
        doseMg: Double? = 5,
        medication: Medication? = .tirzepatide
    ) -> InjectionReminderPlan.Decision {
        InjectionReminderPlan.decide(
            scheduleState: state,
            reminderDaysBefore: daysBefore,
            optedIn: optedIn,
            authorized: authorized,
            privacy: privacy,
            doseMg: doseMg,
            medication: medication,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Gating

    func testOptedOutIsNone() {
        XCTAssertEqual(decide(state: .scheduled(next: due(inDays: 5), dayCount: 5), optedIn: false), .none)
    }

    func testUnauthorizedIsNone() {
        XCTAssertEqual(decide(state: .scheduled(next: due(inDays: 5), dayCount: 5), authorized: false), .none)
    }

    // MARK: - Suppression matrix (reuses the engine's cases verbatim)

    func testPausedIsNone() {
        XCTAssertEqual(decide(state: .paused), .none)
    }

    func testNeedsConfirmationIsNone() {
        XCTAssertEqual(decide(state: .needsConfirmation), .none)
    }

    func testIdleIsNone() {
        XCTAssertEqual(decide(state: .idle), .none)
    }

    func testPlannedIsNoneInV1() {
        // Confirmed-only for v1: a provisional weekday earns no reminder.
        XCTAssertEqual(decide(state: .planned(next: due(inDays: 3))), .none)
    }

    func testOverdueIsNone() {
        // Within the stale threshold the engine still reports `.scheduled` with a
        // negative day count; the in-app card owns overdue, so stay silent.
        XCTAssertEqual(decide(state: .scheduled(next: due(inDays: -3), dayCount: -3)), .none)
    }

    // MARK: - Scheduling + day-offset math

    func testScheduledFiresDayBeforeAtNineLocal() {
        let decision = decide(state: .scheduled(next: due(inDays: 5), dayCount: 5), daysBefore: 1)
        guard case let .schedule(fireDate, dueDate, content) = decision else {
            return XCTFail("expected .schedule, got \(decision)")
        }
        // Due day 20 → fire day 19 at 09:00 UTC.
        let expected = calendar.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 9))!
        XCTAssertEqual(fireDate, expected)
        // dueDate is the start-of-day of the dose (the scheduler's fingerprint key).
        XCTAssertEqual(dueDate, calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 0))!)
        XCTAssertEqual(content.daysUntilDueAtFire, 1, "fires the day before → due tomorrow at fire time")
    }

    func testReminderDaysBeforeZeroFiresOnDueDay() {
        let decision = decide(state: .scheduled(next: due(inDays: 5), dayCount: 5), daysBefore: 0)
        guard case let .schedule(fireDate, _, content) = decision else {
            return XCTFail("expected .schedule, got \(decision)")
        }
        let expected = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9))!
        XCTAssertEqual(fireDate, expected)
        XCTAssertEqual(content.daysUntilDueAtFire, 0, "same-day reminder → due today at fire time")
    }

    func testThreeDaysBeforeFiresThreeDaysOut() {
        let decision = decide(state: .scheduled(next: due(inDays: 10), dayCount: 10), daysBefore: 3)
        guard case let .schedule(fireDate, _, content) = decision else {
            return XCTFail("expected .schedule, got \(decision)")
        }
        // Due day 25 → fire day 22 at 09:00.
        let expected = calendar.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 9))!
        XCTAssertEqual(fireDate, expected)
        XCTAssertEqual(content.daysUntilDueAtFire, 3)
    }

    // MARK: - Past-date guard (short-fuse "due today / soon")

    func testDueTodayAfterNineUsesShortFuse() {
        // Due today, 1-day lead → ideal fire was yesterday 09:00 (past). Dose still
        // due (dayCount 0), so fire a short-fuse "due today" nudge just ahead of now.
        let decision = decide(state: .scheduled(next: due(inDays: 0), dayCount: 0), daysBefore: 1)
        guard case let .schedule(fireDate, _, content) = decision else {
            return XCTFail("expected .schedule, got \(decision)")
        }
        XCTAssertGreaterThan(fireDate, now, "a short-fuse reminder must be in the future, not the past")
        XCTAssertLessThanOrEqual(fireDate, calendar.date(byAdding: .minute, value: 5, to: now)!)
        XCTAssertEqual(content.daysUntilDueAtFire, 0, "due today")
    }

    func testLeadLongerThanRemainingUsesShortFuseWithLiveDayCount() {
        // Due in 2 days but a 5-day lead → ideal fire is in the past. The dose is
        // still 2 days out, so the short-fuse copy must say "due in 2 days".
        let decision = decide(state: .scheduled(next: due(inDays: 2), dayCount: 2), daysBefore: 5)
        guard case let .schedule(fireDate, _, content) = decision else {
            return XCTFail("expected .schedule, got \(decision)")
        }
        XCTAssertGreaterThan(fireDate, now)
        XCTAssertEqual(content.daysUntilDueAtFire, 2)
    }

    func testDueTomorrowBeforeNineFiresThatMorning() {
        // From an early-morning `now`, the day-before 09:00 is still ahead → normal.
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 6))!
        let decision = InjectionReminderPlan.decide(
            scheduleState: .scheduled(next: due(inDays: 1), dayCount: 1),
            reminderDaysBefore: 1,
            optedIn: true, authorized: true, privacy: .full,
            doseMg: 5, medication: .tirzepatide,
            now: earlyMorning, calendar: calendar
        )
        guard case let .schedule(fireDate, _, _) = decision else {
            return XCTFail("expected .schedule, got \(decision)")
        }
        let expected = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
        XCTAssertEqual(fireDate, expected, "fires today 09:00 — the day before tomorrow's dose")
    }

    // MARK: - Privacy shaping (producer-side redaction)

    func testFullPrivacyKeepsMedicationAndDose() {
        let decision = decide(state: .scheduled(next: due(inDays: 5), dayCount: 5), privacy: .full)
        guard case let .schedule(_, _, content) = decision else { return XCTFail("expected .schedule") }
        XCTAssertEqual(content.detail, .detailed(medication: .tirzepatide, doseMg: 5))
    }

    func testMinimalPrivacyDropsMedicationAndDose() {
        let decision = decide(state: .scheduled(next: due(inDays: 5), dayCount: 5), privacy: .minimal)
        guard case let .schedule(_, _, content) = decision else { return XCTFail("expected .schedule") }
        XCTAssertEqual(content.detail, .timing)
    }

    func testRedactedPrivacyIsGeneric() {
        let decision = decide(state: .scheduled(next: due(inDays: 5), dayCount: 5), privacy: .redacted)
        guard case let .schedule(_, _, content) = decision else { return XCTFail("expected .schedule") }
        XCTAssertEqual(content.detail, .generic)
    }
}
