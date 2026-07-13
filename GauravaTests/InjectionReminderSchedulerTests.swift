import XCTest
@testable import Gaurava

// Coverage for the scheduler core (see docs/injection-reminders-plan.html,
// Component 2). A fake NotificationScheduling records the decisions the core
// applies, so we lock the single-pending reconcile contract — schedule when
// eligible, remove on opt-out / no-authorization / suppression — without touching
// UNUserNotificationCenter. The real adapter's fixed identifier guarantees the
// "single pending" by construction (cancel-then-add on one id).
final class InjectionReminderSchedulerTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14))!

    private func input(optedIn: Bool = true, state: TreatmentScheduleState) -> InjectionReminderScheduler.Input {
        .init(
            scheduleState: state,
            reminderDaysBefore: 1,
            optedIn: optedIn,
            privacy: .full,
            doseMg: 5,
            medication: .tirzepatide
        )
    }

    private func scheduledState(inDays days: Int) -> TreatmentScheduleState {
        let next = calendar.date(byAdding: .day, value: days, to: now)!
        return .scheduled(next: next, dayCount: days)
    }

    func testAuthorizedScheduledSchedulesExactlyOne() async {
        let fake = FakeNotificationScheduler(authorized: true)
        await InjectionReminderScheduler.reconcile(
            input: input(state: scheduledState(inDays: 5)), scheduler: fake, now: now, calendar: calendar
        )
        let applied = await fake.applied
        XCTAssertEqual(applied.count, 1)
        guard case .schedule = applied.first else {
            return XCTFail("expected a single .schedule, got \(String(describing: applied.first))")
        }
    }

    func testUnauthorizedRemovesInsteadOfScheduling() async {
        let fake = FakeNotificationScheduler(authorized: false)
        await InjectionReminderScheduler.reconcile(
            input: input(state: scheduledState(inDays: 5)), scheduler: fake, now: now, calendar: calendar
        )
        let applied = await fake.applied
        XCTAssertEqual(applied, [InjectionReminderPlan.Decision.none], "no authorization → remove any pending reminder")
    }

    func testOptedOutRemoves() async {
        let fake = FakeNotificationScheduler(authorized: true)
        await InjectionReminderScheduler.reconcile(
            input: input(optedIn: false, state: scheduledState(inDays: 5)), scheduler: fake, now: now, calendar: calendar
        )
        let applied = await fake.applied
        XCTAssertEqual(applied, [InjectionReminderPlan.Decision.none])
    }

    func testPausedRemoves() async {
        let fake = FakeNotificationScheduler(authorized: true)
        await InjectionReminderScheduler.reconcile(
            input: input(state: .paused), scheduler: fake, now: now, calendar: calendar
        )
        let applied = await fake.applied
        XCTAssertEqual(applied, [InjectionReminderPlan.Decision.none])
    }

    func testScheduleThenSuppressRemovesAcrossReconciles() async {
        let fake = FakeNotificationScheduler(authorized: true)
        await InjectionReminderScheduler.reconcile(
            input: input(state: scheduledState(inDays: 5)), scheduler: fake, now: now, calendar: calendar
        )
        // A later reconcile after the user pauses must clear the pending reminder.
        await InjectionReminderScheduler.reconcile(
            input: input(state: .paused), scheduler: fake, now: now, calendar: calendar
        )
        let applied = await fake.applied
        XCTAssertEqual(applied.count, 2)
        guard case .schedule = applied.first else { return XCTFail("first reconcile should schedule") }
        XCTAssertEqual(applied[1], InjectionReminderPlan.Decision.none, "pausing removes the pending reminder")
    }
}

/// Records the decisions the core applies. An actor so it is Sendable under
/// complete strict concurrency.
private actor FakeNotificationScheduler: NotificationScheduling {
    private let authorizedValue: Bool
    private(set) var applied: [InjectionReminderPlan.Decision] = []

    init(authorized: Bool) { self.authorizedValue = authorized }

    func isAuthorized() async -> Bool { authorizedValue }
    func apply(_ decision: InjectionReminderPlan.Decision) async { applied.append(decision) }
}
