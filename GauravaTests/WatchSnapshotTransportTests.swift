import XCTest
@testable import Gaurava

// Phase 1 (Apple Watch read-only glance) coverage: the WatchConnectivity
// transport seam and the watch-path `GlanceDisplay` shaping.
//
// The phone publishes the same `GauravaGlanceSnapshot` the widgets consume; on
// the watch it crosses as a property-list `Data` value in the WCSession
// application context, is persisted to the on-device App Group file, and is
// rendered through the shared `GlanceDisplayModel`. These tests pin the parts
// that must hold for the wrist to mirror the phone faithfully and privately,
// without needing a live `WCSession` (which can't activate in a test host).
final class WatchSnapshotTransportTests: XCTestCase {
    private static func d(_ days: Int) -> Date { Date(timeIntervalSince1970: Double(days) * 86_400) }

    private func snapshot(privacy: SurfacePrivacyMode, now: Date = d(46)) -> GauravaGlanceSnapshot {
        let input = GlanceProjectionInput(
            startingWeightKg: 100,
            goalWeightKg: 80,
            weightUnit: "kg",
            weights: [
                .init(weightKg: 100, recordedAt: Self.d(0)),
                .init(weightKg: 95, recordedAt: Self.d(20)),
                .init(weightKg: 90, recordedAt: Self.d(40))
            ],
            injections: [.init(doseMg: 7.5, site: "Thigh - Left", date: Self.d(40))],
            plannedDoseMg: 7.5,
            preferredSites: ["Thigh - Left", "Thigh - Right"],
            privacyMode: privacy,
            producerBuild: "test",
            sourceWatermark: "w1"
        )
        return GlanceProjectionBuilder.makeSnapshot(from: input, now: now)
    }

    // MARK: - WatchConnectivity application-context seam

    func testSnapshotRoundTripsThroughApplicationContextPayload() throws {
        for mode in [SurfacePrivacyMode.full, .minimal, .redacted] {
            let snap = snapshot(privacy: mode)
            let context = try WatchSnapshotPayload.encode(snap)
            let decoded = try XCTUnwrap(WatchSnapshotPayload.decode(context), "\(mode) failed to decode")
            XCTAssertEqual(decoded, snap, "\(mode) did not round-trip through the WC payload")
            XCTAssertNotNil(decoded.status?.kind, "\(mode) lost semantic status")
            XCTAssertNil(decoded.status?.phrase, "\(mode) carried producer-language prose")
        }
    }

    // `updateApplicationContext` accepts only property-list types. Prove the
    // envelope qualifies so the transport can never be rejected at runtime.
    func testApplicationContextPayloadIsPropertyListSerializable() throws {
        let context = try WatchSnapshotPayload.encode(snapshot(privacy: .full))
        XCTAssertTrue(PropertyListSerialization.propertyList(context, isValidFor: .binary))
        XCTAssertNotNil(context[WatchSnapshotPayload.key] as? Data)
    }

    func testDecodeReturnsNilForMissingCorruptOrWrongTypePayload() {
        XCTAssertNil(WatchSnapshotPayload.decode([:]))
        XCTAssertNil(WatchSnapshotPayload.decode([WatchSnapshotPayload.key: Data("not json".utf8)]))
        XCTAssertNil(WatchSnapshotPayload.decode([WatchSnapshotPayload.key: "wrong type"]))
    }

    // The file store and the WC transport must share one codec so on-disk and
    // on-the-wire bytes never drift.
    func testSharedCodecRoundTripsAndRejectsCorruptData() throws {
        let snap = snapshot(privacy: .minimal)
        let data = try GlanceSnapshotCodec.encode(snap)
        XCTAssertEqual(GlanceSnapshotCodec.decode(data), snap)
        XCTAssertNil(GlanceSnapshotCodec.decode(Data("nope".utf8)))
    }

    func testSharedCodecDecodesV1PhraseOnlyFixture() throws {
        let data = try Data(contentsOf: Self.fixtureURL(named: "glance-snapshot-v1-phrase-only"))
        let snap = try XCTUnwrap(GlanceSnapshotCodec.decode(data))
        XCTAssertEqual(snap.schemaVersion, 1)
        XCTAssertEqual(snap.status?.phrase, "Next dose in 2 days")
        XCTAssertNil(snap.status?.kind)

        let display = GlanceDisplayModel.make(from: snap, family: .systemSmall, asOf: Self.d(1))
        XCTAssertEqual(display.statusPhrase, "Next dose in 2 days")
    }

    // MARK: - Watch-path GlanceDisplay shaping

    // The watch app screen uses the rich, non-accessory shape but no trend (small
    // display): schedule + site + Full-tier weight appear; the trend does not.
    func testWatchAppScreenShowsScheduleAndWeightButNoTrend() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemSmall, asOf: Self.d(46))
        XCTAssertNotNil(display.dayCount)
        XCTAssertNotNil(display.doseText)
        XCTAssertNotNil(display.siteText)
        XCTAssertNotNil(display.currentWeightText)        // Full tier survived redaction
        XCTAssertTrue(display.trendPoints.isEmpty)        // small display carries no trend
    }

    // The watch complications (incl. the corner, which reuses the circular shape)
    // stay low-detail under every privacy mode: a safe progress fraction may show,
    // but never an absolute dose / site / weight — even on a public watch face.
    func testWatchComplicationShapeStaysLowDetailEvenUnderFull() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .accessoryCircular, asOf: Self.d(46))
        XCTAssertNil(display.doseText)
        XCTAssertNil(display.siteText)
        XCTAssertNil(display.currentWeightText)
        XCTAssertTrue(display.trendPoints.isEmpty)
        XCTAssertEqual(display.progressFraction ?? 0, 0.5, accuracy: 0.0001) // 0…1 fraction is non-identifying
        XCTAssertFalse(display.statusPhrase.isEmpty)
    }

    // Adaptive states the wrist must render calmly rather than showing stale numbers.
    func testWatchPlaceholderAndExpiredStates() {
        XCTAssertEqual(GlanceDisplayModel.make(from: nil, family: .systemSmall, asOf: Self.d(46)), .placeholder)

        let snap = snapshot(privacy: .full)
        let expired = GlanceDisplayModel.make(from: snap, family: .systemSmall, asOf: snap.expiresAt.addingTimeInterval(1))
        XCTAssertEqual(expired.statusPhrase, "Open to refresh")
        XCTAssertNil(expired.dayCount)
        XCTAssertNil(expired.doseText)
    }

    private static func fixtureURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
            .appendingPathExtension("json")
    }
}
