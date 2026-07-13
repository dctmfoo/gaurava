import SwiftData
import XCTest
@testable import Gaurava

// Build 0 refactor coverage: the extracted TreatmentMath derivations and the
// ModelWriteService save choke point. See docs/widget-options-deep-dive.html.
final class Build0RefactorTests: XCTestCase {
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

    // MARK: - TreatmentMath

    func testLatestWeightPicksMostRecentByRecordedAt() {
        let samples = [
            (weightKg: 100.0, recordedAt: Self.date(2026, 1, 1)),
            (weightKg: 90.8, recordedAt: Self.date(2026, 3, 1)),
            (weightKg: 97.0, recordedAt: Self.date(2026, 2, 1))
        ]
        XCTAssertEqual(TreatmentMath.latestWeightKg(samples), 90.8)
        XCTAssertNil(TreatmentMath.latestWeightKg([]))
    }

    func testTotalLostKg() {
        XCTAssertEqual(TreatmentMath.totalLostKg(startingWeightKg: 98.0, currentWeightKg: 90.8) ?? 0, 7.2, accuracy: 0.0001)
        XCTAssertNil(TreatmentMath.totalLostKg(startingWeightKg: 98.0, currentWeightKg: nil))
    }

    func testProgressClampsAndGuardsSpan() {
        // Halfway from 100 to 80 at 90kg.
        XCTAssertEqual(TreatmentMath.progress(startingWeightKg: 100, goalWeightKg: 80, currentWeightKg: 90), 0.5, accuracy: 0.0001)
        // Below goal clamps to 1.
        XCTAssertEqual(TreatmentMath.progress(startingWeightKg: 100, goalWeightKg: 80, currentWeightKg: 70), 1.0, accuracy: 0.0001)
        // Above starting clamps to 0.
        XCTAssertEqual(TreatmentMath.progress(startingWeightKg: 100, goalWeightKg: 80, currentWeightKg: 110), 0.0, accuracy: 0.0001)
        // Non-positive span returns 0.
        XCTAssertEqual(TreatmentMath.progress(startingWeightKg: 80, goalWeightKg: 100, currentWeightKg: 85), 0.0, accuracy: 0.0001)
        // No current weight returns 0.
        XCTAssertEqual(TreatmentMath.progress(startingWeightKg: 100, goalWeightKg: 80, currentWeightKg: nil), 0.0, accuracy: 0.0001)
    }

    func testNextInjectionDateAddsSevenDays() {
        let calendar = Self.utcCalendar()
        let last = Self.date(2026, 5, 24)
        let next = TreatmentMath.nextInjectionDate(afterLastInjectionDate: last, calendar: calendar)
        XCTAssertEqual(next, Self.date(2026, 5, 31))
        XCTAssertNil(TreatmentMath.nextInjectionDate(afterLastInjectionDate: nil, calendar: calendar))
    }

    func testDayCountUsesStartOfDayBoundaries() {
        let calendar = Self.utcCalendar()
        // Late on day 1 to early on day 4 should be 3 whole days, not 2.
        let now = Self.date(2026, 5, 28, hour: 23)
        let target = Self.date(2026, 5, 31, hour: 1)
        XCTAssertEqual(TreatmentMath.dayCount(from: now, to: target, calendar: calendar), 3)
        XCTAssertNil(TreatmentMath.dayCount(from: now, to: nil, calendar: calendar))
    }

    // MARK: - ModelWriteService

    func testSavePersistsChangesAndReturnsTrue() throws {
        let container = GauravaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(WeightEntry(weightKg: 90.8, recordedAt: Self.date(2026, 5, 28)))

        XCTAssertTrue(ModelWriteService.save(context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).count, 1)
    }

    func testSaveWithNoChangesIsANoopAndReturnsTrue() {
        let container = GauravaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        XCTAssertTrue(ModelWriteService.save(context))
    }

    func testSaveOrThrowPersistsChanges() throws {
        let container = GauravaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(InjectionEntry(doseMg: 7.5, injectionSite: "Abdomen - Left", injectionDate: Self.date(2026, 5, 24)))

        try ModelWriteService.saveOrThrow(context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InjectionEntry>()).count, 1)
    }
}
