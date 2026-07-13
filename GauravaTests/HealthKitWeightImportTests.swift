import SwiftData
import XCTest
@testable import Gaurava

/// Exercises the pure dedup + insert seam of the HealthKit weight importer
/// (`HealthKitWeightImport.apply`) against an in-memory SwiftData store. The
/// HealthKit query layer (`HealthKitWeightSource`) needs a device/simulator with
/// a HealthKit store + user authorization and is validated by the live run; this
/// is the deterministic proof that mapping, kg fidelity, provenance, and
/// dedup-by-UUID behave on every CI pass.
final class HealthKitWeightImportTests: XCTestCase {
    private func makeContext() -> ModelContext {
        ModelContext(GauravaModelContainer.make(inMemory: true))
    }

    private func sample(_ uuid: UUID = UUID(), kg: Double, daysAgo: Int, tz: String? = "Asia/Kolkata") -> ImportedWeightSample {
        ImportedWeightSample(
            healthKitUUID: uuid,
            weightKg: kg,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400),
            timeZoneIdentifier: tz
        )
    }

    func testApplyInsertsNewReadingsAsWeightEntries() throws {
        let context = makeContext()
        let inserted = try HealthKitWeightImport.apply(
            samples: [sample(kg: 92.4, daysAgo: 2), sample(kg: 91.8, daysAgo: 1)],
            into: context
        )
        XCTAssertEqual(inserted, 2)

        let stored = try context.fetch(FetchDescriptor<WeightEntry>())
        XCTAssertEqual(stored.count, 2)
        XCTAssertTrue(stored.allSatisfy { $0.sourceHealthKitUUID != nil }, "every imported row carries its HealthKit UUID")
        XCTAssertEqual(Set(stored.map(\.weightKg)), [92.4, 91.8])
    }

    func testApplyIsIdempotentByHealthKitUUID() throws {
        let context = makeContext()
        let uuid = UUID()
        XCTAssertEqual(try HealthKitWeightImport.apply(samples: [sample(uuid, kg: 90, daysAgo: 1)], into: context), 1)
        // Re-importing the SAME HealthKit sample must not create a duplicate.
        XCTAssertEqual(try HealthKitWeightImport.apply(samples: [sample(uuid, kg: 90, daysAgo: 1)], into: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).count, 1)
    }

    func testReSyncInsertsOnlyTrulyNewSamples() throws {
        let context = makeContext()
        let keep = UUID()
        _ = try HealthKitWeightImport.apply(samples: [sample(keep, kg: 88, daysAgo: 3)], into: context)
        let fresh = UUID()
        let inserted = try HealthKitWeightImport.apply(
            samples: [sample(keep, kg: 88, daysAgo: 3), sample(fresh, kg: 87.5, daysAgo: 1)],
            into: context
        )
        XCTAssertEqual(inserted, 1, "the already-known sample is skipped; only the new one lands")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).count, 2)
    }

    func testApplyNeverDedupesAgainstTypedEntries() throws {
        // A hand-typed weight (no HealthKit UUID) must never block an import, even
        // at the same value — provenance, not value, is the dedup key.
        let context = makeContext()
        context.insert(WeightEntry(weightKg: 90, recordedAt: Date()))
        try ModelWriteService.saveOrThrow(context)

        let inserted = try HealthKitWeightImport.apply(samples: [sample(kg: 90, daysAgo: 0)], into: context)
        XCTAssertEqual(inserted, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).count, 2)
    }

    func testApplyMapsKilogramsAndTimeZone() throws {
        let context = makeContext()
        _ = try HealthKitWeightImport.apply(samples: [sample(kg: 84.3, daysAgo: 0, tz: "America/New_York")], into: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<WeightEntry>()).first)
        XCTAssertEqual(entry.weightKg, 84.3, accuracy: 0.0001)
        XCTAssertEqual(entry.timeZoneIdentifier, "America/New_York")
        XCTAssertNil(entry.notes, "import leaves notes user-owned")
    }

    func testApplyFallsBackToCurrentTimeZoneWhenMissing() throws {
        let context = makeContext()
        _ = try HealthKitWeightImport.apply(samples: [sample(kg: 80, daysAgo: 0, tz: nil)], into: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<WeightEntry>()).first)
        XCTAssertEqual(entry.timeZoneIdentifier, TimeZone.current.identifier)
    }

    func testApplyEmptyIsNoOp() throws {
        let context = makeContext()
        XCTAssertEqual(try HealthKitWeightImport.apply(samples: [], into: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).count, 0)
    }
}
