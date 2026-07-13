import XCTest
@testable import Gaurava

/// Unit coverage for the Phase 0 treatment contract: the schedule engine, the
/// active-pause predicate, and how DashboardSnapshot threads them. See
/// docs/onboarding-issues-and-fixes.html.
final class TreatmentScheduleTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    /// A stable mid-day reference so start-of-day day counts are never near a
    /// midnight boundary.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    // MARK: - Schedule engine

    func testConfirmedRecentDoseSchedulesFromTheDose() {
        let state = TreatmentScheduleEngine.state(
            status: .active,
            anchorDate: day(-3),
            newestInjectionDate: nil,
            preferredInjectionDay: nil,
            isPaused: false,
            now: now,
            calendar: calendar
        )
        guard case let .scheduled(_, days) = state else { return XCTFail("expected .scheduled, got \(state)") }
        XCTAssertEqual(days, 4, "anchor 3 days ago + 7-day cadence is due in 4 days")
    }

    func testRecentlyOverdueWithinThresholdStaysHonest() {
        // Dose 10 days ago → due 3 days ago → overdue 3 (within the 14-day window).
        let state = TreatmentScheduleEngine.state(
            status: .active, anchorDate: day(-10), newestInjectionDate: nil,
            preferredInjectionDay: nil, isPaused: false, now: now, calendar: calendar
        )
        guard case let .scheduled(_, days) = state else { return XCTFail("expected .scheduled") }
        XCTAssertEqual(days, -3)
    }

    func testStaleDoseBecomesNeedsConfirmationNotGiantOverdue() {
        // Dose 30 days ago → due 23 days ago → beyond the 14-day stale threshold.
        let state = TreatmentScheduleEngine.state(
            status: .active, anchorDate: day(-30), newestInjectionDate: nil,
            preferredInjectionDay: nil, isPaused: false, now: now, calendar: calendar
        )
        XCTAssertEqual(state, .needsConfirmation)
    }

    func testPausedSuppressesEverything() {
        let state = TreatmentScheduleEngine.state(
            status: .active, anchorDate: day(-3), newestInjectionDate: day(-2),
            preferredInjectionDay: 1, isPaused: true, now: now, calendar: calendar
        )
        XCTAssertEqual(state, .paused)
    }

    func testStartingNowWithWeekdayIsPlannedAndNeverOverdue() {
        let state = TreatmentScheduleEngine.state(
            status: .startingNow, anchorDate: nil, newestInjectionDate: nil,
            preferredInjectionDay: 1, isPaused: false, now: now, calendar: calendar
        )
        guard case let .planned(date) = state else { return XCTFail("expected .planned, got \(state)") }
        XCTAssertGreaterThan(date, now, "a provisional plan is always in the future")
    }

    func testStartingNowWithoutWeekdayIsIdle() {
        let state = TreatmentScheduleEngine.state(
            status: .startingNow, anchorDate: nil, newestInjectionDate: nil,
            preferredInjectionDay: nil, isPaused: false, now: now, calendar: calendar
        )
        XCTAssertEqual(state, .idle, "no countdown before the first dose")
    }

    func testActiveWithoutAnyDoseAsksForConfirmation() {
        // On treatment, no confirmed/logged dose, even with a weekday set: ask for
        // the recent dose rather than inventing a provisional plan.
        let state = TreatmentScheduleEngine.state(
            status: .active, anchorDate: nil, newestInjectionDate: nil,
            preferredInjectionDay: 1, isPaused: false, now: now, calendar: calendar
        )
        XCTAssertEqual(state, .needsConfirmation)
    }

    func testLoggedInjectionAnchorsEvenForUnknownStatus() {
        // A skipped/unknown user who logs a jab still gets an honest schedule.
        let state = TreatmentScheduleEngine.state(
            status: .unknown, anchorDate: nil, newestInjectionDate: day(-2),
            preferredInjectionDay: nil, isPaused: false, now: now, calendar: calendar
        )
        guard case let .scheduled(_, days) = state else { return XCTFail("expected .scheduled") }
        XCTAssertEqual(days, 5)
    }

    func testNewestInjectionWinsOverOlderProfileAnchor() {
        let state = TreatmentScheduleEngine.state(
            status: .active, anchorDate: day(-20), newestInjectionDate: day(-1),
            preferredInjectionDay: nil, isPaused: false, now: now, calendar: calendar
        )
        guard case let .scheduled(_, days) = state else { return XCTFail("expected .scheduled") }
        XCTAssertEqual(days, 6, "the most recent dose (1 day ago) anchors the schedule")
    }

    // MARK: - Active-pause predicate

    func testPauseActivePredicate() {
        XCTAssertTrue(TreatmentPause(startedAt: day(-1)).isActive(asOf: now, calendar: calendar))
        XCTAssertFalse(
            TreatmentPause(startedAt: day(-1), endedAt: now).isActive(asOf: now, calendar: calendar),
            "an ended pause is not active"
        )
        XCTAssertTrue(
            TreatmentPause(startedAt: day(-5), resumedOnDate: day(2)).isActive(asOf: now, calendar: calendar),
            "a future resume date keeps the pause active today"
        )
        XCTAssertFalse(
            TreatmentPause(startedAt: day(-5), resumedOnDate: day(-1)).isActive(asOf: now, calendar: calendar),
            "a past resume date ends the pause"
        )
    }

    // MARK: - Snapshot propagation

    func testSnapshotCarriesPauseAndSuppressesNextDue() {
        let profile = TrackerProfile(treatmentStatusRaw: TreatmentStatus.active.rawValue)
        let injection = InjectionEntry(doseMg: 5, injectionSite: "Abdomen - Left", injectionDate: day(-2))
        let pause = TreatmentPause(startedAt: day(-1))

        let snapshot = DashboardSnapshot.fromModels(
            profiles: [profile], preferences: [], weights: [], injections: [injection],
            dailyLogs: [], dailyLogEntries: [], sideEffects: [], checkIns: [], receipts: [],
            pauses: [pause], now: now
        )

        XCTAssertTrue(snapshot.isTreatmentPaused)
        XCTAssertEqual(snapshot.scheduleState, .paused)
        XCTAssertNil(snapshot.nextInjectionDate, "paused treatment shows no countdown")
        XCTAssertNil(snapshot.projectedNextInjectionDate)
    }

    func testSnapshotKeepsUnknownMedicationUnknown() {
        // A profile that never recorded a medication must not surface tirzepatide.
        let profile = TrackerProfile(startingWeightKg: 90)
        let snapshot = DashboardSnapshot.fromModels(
            profiles: [profile], preferences: [], weights: [], injections: [],
            dailyLogs: [], dailyLogEntries: [], sideEffects: [], checkIns: [], receipts: [],
            pauses: [], now: now
        )
        XCTAssertNil(snapshot.profile.medication)
    }

    func testSnapshotHonorsRecordedMedication() {
        let profile = TrackerProfile(medicationRaw: Medication.semaglutide.rawValue)
        let snapshot = DashboardSnapshot.fromModels(
            profiles: [profile], preferences: [], weights: [], injections: [],
            dailyLogs: [], dailyLogEntries: [], sideEffects: [], checkIns: [], receipts: [],
            pauses: [], now: now
        )
        XCTAssertEqual(snapshot.profile.medication, .semaglutide)
    }
}
