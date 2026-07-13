import XCTest
@testable import Gaurava

/// Coverage for the post-onboarding adaptive-states foundations:
/// `TreatmentMath.projectedNextInjectionDate` (the net-new provisional date math)
/// and the per-field `DashboardSnapshot` predicates that replace the coarse
/// `hasAnyData` gate. See docs/post-onboarding-adaptive-states-plan.html.
final class AdaptiveStatesTests: XCTestCase {
    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return utcCalendar().date(from: components)!
    }

    // MARK: - projectedNextInjectionDate

    func testProjectionNilWeekdayIsNoOp() {
        let calendar = Self.utcCalendar()
        XCTAssertNil(
            TreatmentMath.projectedNextInjectionDate(weekday: nil, from: Self.date(2026, 6, 3), calendar: calendar)
        )
    }

    /// The +1 conversion: a value stored 0-based (Sunday == 0) must map to the
    /// 1-based `Calendar` weekday (Sunday == 1). For every stored weekday the
    /// projection must land on exactly that weekday, strictly in the future, and
    /// within the next 7 days. This also exercises week rollover, since for a
    /// fixed `from` most target weekdays wrap past the end of the week.
    func testProjectionConvertsZeroBasedWeekdayAndStaysInNextSevenDays() throws {
        let calendar = Self.utcCalendar()
        let from = Self.date(2026, 6, 3) // a fixed reference day
        let startOfFrom = calendar.startOfDay(for: from)

        for storedDay in 0..<7 {
            let projected = TreatmentMath.projectedNextInjectionDate(
                weekday: storedDay,
                from: from,
                calendar: calendar
            )
            let date = try XCTUnwrap(projected, "expected a date for stored weekday \(storedDay)")

            // Lands on the intended weekday (stored 0-based + 1 == Calendar 1-based).
            XCTAssertEqual(
                calendar.component(.weekday, from: date),
                storedDay + 1,
                "stored weekday \(storedDay) should project to Calendar weekday \(storedDay + 1)"
            )

            // Strictly in the future, 1...7 whole days out, and start-of-day.
            let delta = calendar.dateComponents([.day], from: startOfFrom, to: date).day ?? 0
            XCTAssertGreaterThanOrEqual(delta, 1, "stored weekday \(storedDay) must be in the future")
            XCTAssertLessThanOrEqual(delta, 7, "stored weekday \(storedDay) must be within a week")
            XCTAssertEqual(date, calendar.startOfDay(for: date), "projection must be start-of-day")
        }
    }

    /// Today-is-the-day rule: when `from` already falls on the chosen weekday, the
    /// projection must skip to NEXT week (delta == 7), never "today".
    func testProjectionWhenTodayIsTheChosenWeekdayProjectsToNextWeek() throws {
        let calendar = Self.utcCalendar()
        let from = Self.date(2026, 6, 3, hour: 9)
        let weekdayOfFrom = calendar.component(.weekday, from: from) // 1-based
        let storedDay = weekdayOfFrom - 1 // back to 0-based storage

        let projected = TreatmentMath.projectedNextInjectionDate(weekday: storedDay, from: from, calendar: calendar)
        let date = try XCTUnwrap(projected)

        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: date).day
        XCTAssertEqual(delta, 7, "today-is-the-day must project a full week out, not today")
        XCTAssertEqual(calendar.component(.weekday, from: date), weekdayOfFrom)
    }

    /// Timezone / start-of-day: two times on the same calendar day yield the same
    /// projected date, and that date is normalized to start-of-day.
    func testProjectionIsStartOfDayAndTimeOfDayInsensitive() throws {
        let calendar = Self.utcCalendar()
        let early = TreatmentMath.projectedNextInjectionDate(weekday: 4, from: Self.date(2026, 6, 3, hour: 1), calendar: calendar)
        let late = TreatmentMath.projectedNextInjectionDate(weekday: 4, from: Self.date(2026, 6, 3, hour: 23), calendar: calendar)

        XCTAssertEqual(early, late, "same day should produce the same projection regardless of time")
        let date = try XCTUnwrap(early)
        XCTAssertEqual(calendar.component(.hour, from: date), 0)
        XCTAssertEqual(calendar.component(.minute, from: date), 0)
    }

    /// Explicit week rollover: from a Saturday, targeting Sunday (stored 0) is the
    /// very next day — it must cross into the following week, not wrap backwards.
    func testProjectionRollsOverFromSaturdayToSunday() throws {
        let calendar = Self.utcCalendar()
        // Walk forward from a reference date until we land on a Saturday (weekday 7).
        var saturday = Self.date(2026, 6, 3)
        while calendar.component(.weekday, from: saturday) != 7 {
            saturday = calendar.date(byAdding: .day, value: 1, to: saturday)!
        }

        let projected = TreatmentMath.projectedNextInjectionDate(weekday: 0, from: saturday, calendar: calendar)
        let date = try XCTUnwrap(projected)
        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: saturday), to: date).day
        XCTAssertEqual(delta, 1, "Saturday -> Sunday is the next day")
        XCTAssertEqual(calendar.component(.weekday, from: date), 1, "must land on Sunday")
    }

    // MARK: - Per-field DashboardSnapshot predicates

    func testEmptySnapshotHasNoData() {
        let snapshot = DashboardSnapshot.empty
        XCTAssertFalse(snapshot.hasWeights)
        XCTAssertFalse(snapshot.hasCurrentWeight)
        XCTAssertFalse(snapshot.hasInjections)
        XCTAssertFalse(snapshot.hasGoal)
        XCTAssertFalse(snapshot.hasLogData)
        XCTAssertFalse(snapshot.hasAnyData)
    }

    func testWeightPredicates() {
        var snapshot = DashboardSnapshot.empty
        snapshot.weights = [WeightSnapshot(weightKg: 92.4, recordedAt: Self.date(2026, 6, 1))]
        XCTAssertTrue(snapshot.hasWeights)
        XCTAssertTrue(snapshot.hasCurrentWeight)
        XCTAssertTrue(snapshot.hasAnyData)
        XCTAssertFalse(snapshot.hasGoal)
        XCTAssertFalse(snapshot.hasInjections)
    }

    func testGoalPredicateRequiresPositiveGoal() {
        var snapshot = DashboardSnapshot.empty
        snapshot.profile.goalWeightKg = 0
        XCTAssertFalse(snapshot.hasGoal)
        snapshot.profile.goalWeightKg = 80
        XCTAssertTrue(snapshot.hasGoal)
    }

    func testInjectionPredicate() {
        var snapshot = DashboardSnapshot.empty
        snapshot.injections = [InjectionSnapshot(doseMg: 5, injectionSite: "Abdomen - Left", injectionDate: Self.date(2026, 6, 1))]
        XCTAssertTrue(snapshot.hasInjections)
        XCTAssertTrue(snapshot.hasAnyData)
    }

    /// Regression guard: a user who only recorded a Log-v1 day capture (a side
    /// effect / mood, with no daily log row) must still count as having data. The
    /// old `hasAnyData` omitted `dayCaptures` and would have dumped them back to
    /// the first-run empty state.
    func testLogDataCoversDayCapturesNotJustDailyLogs() {
        var snapshot = DashboardSnapshot.empty
        snapshot.dayCaptures = [
            DayCaptureSnapshot(logDate: Self.date(2026, 6, 1), symptoms: [], mood: nil, allClear: true, note: nil)
        ]
        XCTAssertTrue(snapshot.hasLogData, "dayCaptures must satisfy hasLogData")
        XCTAssertTrue(snapshot.hasAnyData, "a day-capture-only user must not be treated as empty")
    }

    func testProjectedNextInjectionDateOnlyWhenNoInjections() {
        var snapshot = DashboardSnapshot.empty
        snapshot.profile.preferredInjectionDay = 4 // Thursday (stored 0-based)
        XCTAssertNotNil(snapshot.projectedNextInjectionDate)

        // Once a real injection exists the logged cadence takes over.
        snapshot.injections = [InjectionSnapshot(doseMg: 5, injectionSite: "Abdomen - Left", injectionDate: Self.date(2026, 6, 1))]
        XCTAssertNil(snapshot.projectedNextInjectionDate)
    }

    func testSuggestedSiteDisplayIsNilWithoutHistory() {
        let snapshot = DashboardSnapshot.empty
        XCTAssertNil(snapshot.suggestedInjectionSiteDisplay, "no jab history -> no display site")
        // The form default is always concrete so the Add Injection picker has a value.
        XCTAssertFalse(snapshot.suggestedInjectionSite.isEmpty)
    }

    // MARK: - Injection-day weekday localization

    /// Regression guard for the "Injection day shows in Tamil in all languages"
    /// bug: the weekday-name helpers used `Calendar.current.weekdaySymbols`, which
    /// resolves against the SYSTEM locale (`Locale.current`, derived from
    /// `AppleLanguages`) and so ignored the in-app language picker. Once Tamil had
    /// been mirrored into `AppleLanguages`, every in-app language showed the Tamil
    /// weekday name. The fix routes the helpers through
    /// `AppLocalization.effectiveCalendar`, which pins `effectiveLocale`. Here we
    /// pin the picker per-language and assert the weekday name follows it (and so
    /// differs across languages) instead of staying locked to one locale.
    func testInjectionWeekdayNameFollowsInAppPickerNotSystemLocale() throws {
        let key = AppLocalization.storageKey
        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        // The guard relies on these translations being bundled in this build.
        for code in ["hi", "ta"] {
            try XCTSkipUnless(
                AppLanguage.supportedCodes.contains(code),
                "language \(code) not bundled in this build — skipping localization guard"
            )
        }

        // Index 1 == Monday in `weekdaySymbols` (stored 0-based, Sunday == 0).
        func mondayName(picking code: String) -> String {
            defaults.set(code, forKey: key)
            return injectionWeekdayName(1)!
        }

        let hindi = mondayName(picking: "hi")
        let tamil = mondayName(picking: "ta")

        // Heart of the regression: the old Calendar.current code returned the same
        // system-locale name for both picks, so these would be equal.
        XCTAssertNotEqual(hindi, tamil, "injection weekday name must change with the in-app language picker")

        // …and each must match a calendar explicitly pinned to that language.
        XCTAssertEqual(hindi, referenceMonday(for: "hi"))
        XCTAssertEqual(tamil, referenceMonday(for: "ta"))

        // The shared calendar's locale must track the picker too.
        defaults.set("ta", forKey: key)
        XCTAssertEqual(AppLocalization.effectiveCalendar.locale?.identifier, "ta")
    }

    private func referenceMonday(for code: String) -> String {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: code)
        return calendar.weekdaySymbols[1]
    }
}
