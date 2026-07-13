import XCTest
@testable import Gaurava

final class DosePhaseMathTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Double) -> Date {
        base.addingTimeInterval(offset * 86_400)
    }

    private func weeklyInjections(doses: [Double]) -> [(doseMg: Double, injectionDate: Date)] {
        doses.enumerated().map { index, dose in
            (doseMg: dose, injectionDate: day(Double(index * 7)))
        }
    }

    func testEmptyInjectionsProduceNoPhases() {
        let phases = DosePhaseMath.phases(
            injections: [],
            weights: [(weightKg: 100, recordedAt: day(0))],
            now: day(30)
        )
        XCTAssertTrue(phases.isEmpty)
    }

    func testEscalationGroupsContiguousRuns() {
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [2.5, 2.5, 2.5, 2.5, 5, 5, 5]),
            weights: [],
            now: day(45)
        )
        XCTAssertEqual(phases.count, 2)
        XCTAssertEqual(phases[0].doseMg, 2.5)
        XCTAssertEqual(phases[0].injectionCount, 4)
        XCTAssertEqual(phases[0].start, day(0))
        XCTAssertEqual(phases[0].end, day(28))
        XCTAssertEqual(phases[0].days, 28)
        XCTAssertFalse(phases[0].isOngoing)
        XCTAssertEqual(phases[1].doseMg, 5)
        XCTAssertEqual(phases[1].injectionCount, 3)
        XCTAssertNil(phases[1].end)
        XCTAssertTrue(phases[1].isOngoing)
        XCTAssertEqual(phases[1].days, 17)
    }

    func testRevisitedDoseIsASeparatePhase() {
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [5, 5, 7.5, 7.5, 5, 5]),
            weights: [],
            now: day(60)
        )
        XCTAssertEqual(phases.map(\.doseMg), [5, 7.5, 5])
        XCTAssertEqual(phases.map(\.injectionCount), [2, 2, 2])
    }

    func testUnsortedInputIsSortedBeforeGrouping() {
        let injections: [(doseMg: Double, injectionDate: Date)] = [
            (doseMg: 5, injectionDate: day(14)),
            (doseMg: 2.5, injectionDate: day(0)),
            (doseMg: 2.5, injectionDate: day(7))
        ]
        let phases = DosePhaseMath.phases(injections: injections, weights: [], now: day(20))
        XCTAssertEqual(phases.map(\.doseMg), [2.5, 5])
        XCTAssertEqual(phases[0].injectionCount, 2)
    }

    func testBoundaryWeightsInterpolateBetweenSamples() {
        // Dose change on day 14 sits midway between weigh-ins on days 10 and 18
        // (92 kg and 90 kg), so the shared boundary weight is 91 kg.
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [2.5, 2.5, 5, 5]),
            weights: [
                (weightKg: 94, recordedAt: day(0)),
                (weightKg: 92, recordedAt: day(10)),
                (weightKg: 90, recordedAt: day(18)),
                (weightKg: 88, recordedAt: day(28))
            ],
            now: day(28)
        )
        XCTAssertEqual(phases.count, 2)
        XCTAssertEqual(phases[0].startWeightKg ?? -1, 94, accuracy: 0.001)
        XCTAssertEqual(phases[0].endWeightKg ?? -1, 91, accuracy: 0.001)
        XCTAssertEqual(phases[1].startWeightKg ?? -1, 91, accuracy: 0.001)
        XCTAssertEqual(phases[1].endWeightKg ?? -1, 88, accuracy: 0.001)
        XCTAssertEqual(phases[0].changeKg ?? 0, -3, accuracy: 0.001)
        XCTAssertEqual(phases[1].changeKg ?? 0, -3, accuracy: 0.001)
    }

    func testPhaseChangesTelescopeToTotalChange() {
        let weights: [(weightKg: Double, recordedAt: Date)] = stride(from: 0, through: 70, by: 4).map {
            (weightKg: 100 - Double($0) * 0.25, recordedAt: day(Double($0)))
        }
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [2.5, 2.5, 5, 5, 5, 7.5, 7.5, 7.5, 10, 10]),
            weights: weights,
            now: day(70)
        )
        let summed = phases.compactMap(\.changeKg).reduce(0, +)
        let total = weights.last!.weightKg - weights.first!.weightKg
        XCTAssertEqual(phases.compactMap(\.changeKg).count, phases.count)
        XCTAssertEqual(summed, total, accuracy: 0.001)
    }

    func testWeeklyRateUsesPhaseDuration() {
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [5, 5, 5, 5]),
            weights: [
                (weightKg: 100, recordedAt: day(0)),
                (weightKg: 98, recordedAt: day(28))
            ],
            now: day(28)
        )
        XCTAssertEqual(phases.count, 1)
        XCTAssertEqual(phases[0].weeklyRateKg ?? 0, -0.5, accuracy: 0.001)
    }

    func testWeeklyRateIsNilUnderOneWeek() {
        let phases = DosePhaseMath.phases(
            injections: [(doseMg: 5, injectionDate: day(0))],
            weights: [
                (weightKg: 100, recordedAt: day(0)),
                (weightKg: 99.5, recordedAt: day(3))
            ],
            now: day(3)
        )
        XCTAssertEqual(phases.count, 1)
        XCTAssertNotNil(phases[0].changeKg)
        XCTAssertNil(phases[0].weeklyRateKg)
    }

    func testPhaseOutsideWeightSpanHasNilChange() {
        // All weigh-ins predate the second phase; its change must be nil, not 0.
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [2.5, 2.5, 5, 5]),
            weights: [
                (weightKg: 100, recordedAt: day(0)),
                (weightKg: 99, recordedAt: day(8))
            ],
            now: day(28)
        )
        XCTAssertEqual(phases.count, 2)
        XCTAssertNotNil(phases[0].changeKg)
        XCTAssertNil(phases[1].changeKg)
        XCTAssertNil(phases[1].weeklyRateKg)
    }

    // The owner's real journey: a two-week travel pause inside the 7.5 mg run
    // must not count as time on the dose, or four weekly jabs display as
    // "5 weeks" and the weekly rate dilutes.
    func testPauseInsidePhaseIsExcludedFromActiveDaysAndRate() {
        let phases = DosePhaseMath.phases(
            injections: [
                (doseMg: 7.5, injectionDate: day(0)),
                (doseMg: 7.5, injectionDate: day(7)),
                (doseMg: 7.5, injectionDate: day(28)),
                (doseMg: 10, injectionDate: day(35))
            ],
            weights: [
                (weightKg: 100, recordedAt: day(0)),
                (weightKg: 96, recordedAt: day(35))
            ],
            pauses: [(start: day(11), end: day(25))],
            now: day(35)
        )
        XCTAssertEqual(phases.count, 2)
        XCTAssertEqual(phases[0].days, 35)
        XCTAssertEqual(phases[0].pausedDays, 14)
        XCTAssertEqual(phases[0].activeDays, 21)
        // Change still spans the whole window (-4 kg), but the rate is per
        // active week: -4 / 3 weeks.
        XCTAssertEqual(phases[0].weeklyRateKg ?? 0, -4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(phases[1].pausedDays, 0)
    }

    func testOpenPauseClampsToOngoingPhaseEnd() {
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [5, 5]),
            weights: [],
            pauses: [(start: day(10), end: nil)],
            now: day(17)
        )
        XCTAssertEqual(phases.count, 1)
        XCTAssertEqual(phases[0].days, 17)
        XCTAssertEqual(phases[0].pausedDays, 7)
        XCTAssertEqual(phases[0].activeDays, 10)
    }

    func testPauseSpanningDoseChangeSplitsAcrossPhases() {
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [2.5, 2.5, 5, 5]),
            weights: [],
            pauses: [(start: day(10), end: day(18))],
            now: day(28)
        )
        XCTAssertEqual(phases.count, 2)
        XCTAssertEqual(phases[0].pausedDays, 4)
        XCTAssertEqual(phases[1].pausedDays, 4)
    }

    func testOverlappingPausesAreCountedOnce() {
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [5, 5, 5]),
            weights: [],
            pauses: [
                (start: day(2), end: day(8)),
                (start: day(6), end: day(10))
            ],
            now: day(21)
        )
        XCTAssertEqual(phases.count, 1)
        XCTAssertEqual(phases[0].pausedDays, 8)
        XCTAssertEqual(phases[0].activeDays, 13)
    }

    func testPauseOutsidePhaseWindowChangesNothing() {
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [5, 5]),
            weights: [],
            pauses: [(start: day(-20), end: day(-10))],
            now: day(14)
        )
        XCTAssertEqual(phases.count, 1)
        XCTAssertEqual(phases[0].pausedDays, 0)
        XCTAssertEqual(phases[0].activeDays, phases[0].days)
    }

    func testNoWeightsMeansNilChangeEverywhere() {
        let phases = DosePhaseMath.phases(
            injections: weeklyInjections(doses: [2.5, 5]),
            weights: [],
            now: day(14)
        )
        XCTAssertEqual(phases.count, 2)
        XCTAssertTrue(phases.allSatisfy { $0.changeKg == nil })
    }
}
