import SwiftData
import XCTest
@testable import Gaurava

// Build 1 coverage: glance projection (incl. producer-side redaction), the
// versioned snapshot codec + stale gating, the file store, and the save
// choke point republish hook. See docs/widget-build-runbook.md Section 5.
final class GlanceSurfaceTests: XCTestCase {
    private static func d(_ days: Int) -> Date { Date(timeIntervalSince1970: Double(days) * 86_400) }

    private func makeInput(privacy: SurfacePrivacyMode, suppressed: Bool = false) -> GlanceProjectionInput {
        GlanceProjectionInput(
            startingWeightKg: 100,
            goalWeightKg: 80,
            weightUnit: "kg",
            weights: [
                .init(weightKg: 100, recordedAt: Self.d(0)),
                .init(weightKg: 90, recordedAt: Self.d(40))
            ],
            injections: [
                .init(doseMg: 5, site: "Abdomen - Left", date: Self.d(33)),
                .init(doseMg: 7.5, site: "Thigh - Left", date: Self.d(40))
            ],
            plannedDoseMg: 7.5,
            preferredSites: ["Thigh - Left", "Thigh - Right"],
            privacyMode: privacy,
            producerBuild: "test",
            sourceWatermark: "w1",
            scheduleSuppressed: suppressed
        )
    }

    // MARK: - Projection + producer-side redaction

    func testFullProjectionPopulatesAllSlicesAndSharesTreatmentMath() {
        let now = Self.d(46) // 6 days after last injection (day 40 + 7 = day 47)
        let snap = GlanceProjectionBuilder.makeSnapshot(from: makeInput(privacy: .full), now: now, calendar: .current)

        XCTAssertEqual(snap.schemaVersion, GauravaSurface.schemaVersion)
        XCTAssertEqual(snap.nextAction?.daysUntilNextInjection, 1)             // matches TreatmentMath
        XCTAssertEqual(snap.nextAction?.suggestedSite, "Thigh - Right")        // rotation after Thigh - Left
        XCTAssertEqual(snap.nextAction?.doseMg, 7.5)
        XCTAssertEqual(snap.progress?.currentWeightKg, 90)
        XCTAssertEqual(snap.progress?.totalLostKg ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(snap.progress?.progressToGoal ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertFalse(snap.trend?.points.isEmpty ?? true)
    }

    func testTrendCoversFullJourneyDownsampledPreservingEnds() {
        // 60 daily weigh-ins (120 → 90.5). The trend must span the WHOLE journey
        // (not a trailing window) yet stay capped so the App Group payload is small.
        var input = makeInput(privacy: .full)
        input.startingWeightKg = 120
        input.weights = (0..<60).map { .init(weightKg: 120 - Double($0) * 0.5, recordedAt: Self.d($0)) }
        let pts = GlanceProjectionBuilder.makeSnapshot(from: input, now: Self.d(60)).trend?.points ?? []
        XCTAssertGreaterThanOrEqual(pts.count, 2)
        XCTAssertLessThanOrEqual(pts.count, 20)                      // capped
        XCTAssertEqual(pts.first?.weightKg ?? 0, 120, accuracy: 0.001)   // start preserved
        XCTAssertEqual(pts.last?.weightKg ?? 0, 90.5, accuracy: 0.001)   // latest weigh-in preserved
    }

    func testDownsampleEvenlyCapsAndKeepsEnds() {
        let points = (0..<100).map { TrendPoint(date: Self.d($0), weightKg: Double($0)) }
        let sampled = GlanceProjectionBuilder.downsampleEvenly(points, max: 20)
        XCTAssertLessThanOrEqual(sampled.count, 20)
        XCTAssertEqual(sampled.first?.weightKg, 0)
        XCTAssertEqual(sampled.last?.weightKg, 99)
        // A no-op when already within budget.
        XCTAssertEqual(GlanceProjectionBuilder.downsampleEvenly(Array(points.prefix(10)), max: 20).count, 10)
    }

    func testSuppressedScheduleDropsCountdownAndDoseAcrossPrivacyModes() {
        // Paused / needs-confirmation: no date AND no dose, so the surface can't render a
        // dose chip with no countdown beside it (the "half-overdue" inconsistency).
        for privacy in [SurfacePrivacyMode.full, .minimal] {
            let snap = GlanceProjectionBuilder.makeSnapshot(
                from: makeInput(privacy: privacy, suppressed: true), now: Self.d(46))
            XCTAssertNil(snap.nextAction?.nextInjectionDate, "\(privacy)")
            XCTAssertNil(snap.nextAction?.daysUntilNextInjection, "\(privacy)")
            XCTAssertNil(snap.nextAction?.doseMg, "\(privacy)")
        }
    }

    func testMinimalRedactionDropsAbsoluteWeightsButKeepsFractionAndSchedule() {
        let snap = GlanceProjectionBuilder.makeSnapshot(from: makeInput(privacy: .minimal), now: Self.d(46))
        XCTAssertNotNil(snap.nextAction?.daysUntilNextInjection)
        XCTAssertEqual(snap.progress?.progressToGoal ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertNil(snap.progress?.currentWeightKg)        // no absolute weight leaked
        XCTAssertNil(snap.progress?.totalLostKg)
        XCTAssertNil(snap.trend)
    }

    func testRedactedKeepsOnlyStatusAndDayCount() {
        let snap = GlanceProjectionBuilder.makeSnapshot(from: makeInput(privacy: .redacted), now: Self.d(46))
        XCTAssertEqual(snap.status?.kind, .nextDoseInDays)
        XCTAssertEqual(snap.status?.daysUntilNextInjection, 1)
        XCTAssertNil(snap.status?.phrase)
        XCTAssertNotNil(snap.nextAction?.daysUntilNextInjection)
        XCTAssertNil(snap.nextAction?.doseMg)
        XCTAssertNil(snap.nextAction?.suggestedSite)
        XCTAssertNil(snap.progress)
        XCTAssertNil(snap.trend)
    }

    // MARK: - Codec + stale gating

    func testSnapshotRoundTripsAndStaleGates() throws {
        let snap = GlanceProjectionBuilder.makeSnapshot(from: makeInput(privacy: .full), now: Self.d(46), ttl: 3600)
        let store = FileSnapshotStore(fileURL: Self.tempURL())
        try store.write(snap)
        let read = try XCTUnwrap(store.read())
        XCTAssertEqual(read, snap)

        XCTAssertFalse(read.isExpired(asOf: read.generatedAt.addingTimeInterval(3599)))
        XCTAssertTrue(read.isExpired(asOf: read.generatedAt.addingTimeInterval(3601)))
    }

    func testDecodesPriorVersionFixture() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: Self.fixtureURL(named: "glance-snapshot-v1-phrase-only"))
        let snap = try decoder.decode(GauravaGlanceSnapshot.self, from: data)
        XCTAssertEqual(snap.schemaVersion, 1)
        XCTAssertEqual(snap.status?.phrase, "Next dose in 2 days")
        XCTAssertNil(snap.status?.kind)
        XCTAssertNil(snap.progress)
    }

    func testNewSnapshotsCarrySemanticStatusNotProducerPhrases() throws {
        let snap = GlanceProjectionBuilder.makeSnapshot(from: makeInput(privacy: .full), now: Self.d(46))
        XCTAssertEqual(snap.schemaVersion, 2)
        XCTAssertEqual(snap.status?.kind, .nextDoseInDays)
        XCTAssertEqual(snap.status?.daysUntilNextInjection, 1)
        XCTAssertNil(snap.status?.phrase)
    }

    // MARK: - Store defensiveness + tombstone

    func testCorruptFileReadsAsNil() throws {
        let url = Self.tempURL()
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(FileSnapshotStore(fileURL: url).read())
    }

    func testTombstoneClearsPayload() throws {
        let store = FileSnapshotStore(fileURL: Self.tempURL())
        try store.writeTombstone(producerBuild: "t", now: Self.d(1))
        let read = try XCTUnwrap(store.read())
        XCTAssertNil(read.progress)
        XCTAssertNil(read.nextAction)
        XCTAssertEqual(read.status?.kind, .noDataYet)
        XCTAssertNil(read.status?.phrase)
        XCTAssertEqual(read.sourceWatermark, "tombstone")
    }

    // MARK: - Save choke point republish hook

    func testAfterSaveHookFiresOnEverySavePath() throws {
        let container = GauravaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        var fired = 0
        ModelWriteService.afterSave = { _ in fired += 1 }
        defer { ModelWriteService.afterSave = nil }

        context.insert(WeightEntry(weightKg: 90, recordedAt: Self.d(1)))
        XCTAssertTrue(ModelWriteService.save(context))

        context.insert(InjectionEntry(doseMg: 5, injectionSite: "Abdomen - Left", injectionDate: Self.d(1)))
        try ModelWriteService.saveOrThrow(context)

        XCTAssertEqual(fired, 2)
    }

    // MARK: - App Group surface language preference

    func testSurfaceLanguagePreferenceReadsAndWritesAppGroupKey() {
        let suiteName = "group.com.nags.gaurava.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        let preferences = SurfacePreferences(appGroupIdentifier: suiteName)
        XCTAssertEqual(preferences.languageCode, "")

        preferences.languageCode = "ta"

        XCTAssertEqual(preferences.languageCode, "ta")
        XCTAssertEqual(defaults?.string(forKey: GauravaSurface.surfaceLanguageCodeKey), "ta")
    }

    func testSurfaceLocaleResolverFallsBackForEmptyMissingAndUnsupportedCodes() {
        let localizations = ["en", "hi", "ta", "te"]
        let fallback = Locale(identifier: "en_US")

        XCTAssertEqual(
            GauravaSurface.resolvedSurfaceLocaleIdentifier(
                languageCode: "ta",
                availableLocalizations: localizations,
                fallback: fallback
            ),
            "ta"
        )
        XCTAssertEqual(
            GauravaSurface.resolvedSurfaceLocaleIdentifier(
                languageCode: "",
                availableLocalizations: localizations,
                fallback: fallback
            ),
            "en_US"
        )
        XCTAssertEqual(
            GauravaSurface.resolvedSurfaceLocaleIdentifier(
                languageCode: nil,
                availableLocalizations: localizations,
                fallback: fallback
            ),
            "en_US"
        )
        XCTAssertEqual(
            GauravaSurface.resolvedSurfaceLocaleIdentifier(
                languageCode: "fr",
                availableLocalizations: localizations,
                fallback: fallback
            ),
            "en_US"
        )
    }

    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private static func fixtureURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
            .appendingPathExtension("json")
    }
}
