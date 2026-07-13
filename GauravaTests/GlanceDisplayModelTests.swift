import XCTest
@testable import Gaurava

// Build 2: per-family display + the surface-shape privacy rule.
//
// Producer-side redaction (tested in GlanceSurfaceTests) decides what slices a
// snapshot carries; this layer decides what each surface family renders, with
// Lock Screen / accessory families staying low-detail regardless of mode.
final class GlanceDisplayModelTests: XCTestCase {
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

    private func semanticSnapshot(daysUntilNextInjection days: Int?) -> GauravaGlanceSnapshot {
        GauravaGlanceSnapshot(
            schemaVersion: GauravaSurface.schemaVersion,
            producerBuild: "test",
            generatedAt: Self.d(40),
            expiresAt: Self.d(90),
            sourceWatermark: "semantic-\(days.map(String.init) ?? "none")",
            privacyMode: .minimal,
            renderPolicyVersion: 1,
            nextAction: days.map {
                NextActionSlice(
                    daysUntilNextInjection: $0,
                    nextInjectionDate: nil,
                    doseMg: nil,
                    suggestedSite: nil
                )
            },
            progress: nil,
            trend: nil,
            status: SafeStatusSlice.nextDose(daysUntil: days)
        )
    }

    // MARK: - Accessory families stay low-detail under every privacy mode

    func testAccessoryNeverLeaksAbsoluteValuesEvenUnderFullDetail() {
        let snap = snapshot(privacy: .full)
        for family in [SurfaceFamilyClass.accessoryInline, .accessoryCircular, .accessoryRectangular] {
            let display = GlanceDisplayModel.make(from: snap, family: family, asOf: Self.d(46))
            XCTAssertNil(display.doseText, "\(family) leaked dose")
            XCTAssertNil(display.siteText, "\(family) leaked site")
            XCTAssertNil(display.currentWeightText, "\(family) leaked weight")
            XCTAssertTrue(display.trendPoints.isEmpty, "\(family) leaked trend")
            XCTAssertFalse(display.statusPhrase.isEmpty)
        }
    }

    func testCircularKeepsSafeProgressFractionButNoWeight() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .accessoryCircular, asOf: Self.d(46))
        XCTAssertEqual(display.progressFraction ?? 0, 0.5, accuracy: 0.0001) // 0...1 fraction is non-identifying
        XCTAssertNil(display.currentWeightText)
    }

    func testInlineAndRectangularHaveNoProgressRing() {
        XCTAssertNil(GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .accessoryInline, asOf: Self.d(46)).progressFraction)
        XCTAssertNil(GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .accessoryRectangular, asOf: Self.d(46)).progressFraction)
    }

    // MARK: - Home Screen families honor producer redaction

    func testLargeShowsWeightAndTrendUnderFull() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemLarge, asOf: Self.d(46))
        XCTAssertNotNil(display.doseText)
        XCTAssertNotNil(display.siteText)
        XCTAssertNotNil(display.currentWeightText)
        XCTAssertGreaterThanOrEqual(display.trendPoints.count, 2)
    }

    func testLargeHidesWeightAndTrendUnderMinimal() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .minimal), family: .systemLarge, asOf: Self.d(46))
        XCTAssertNil(display.currentWeightText)              // producer dropped absolute weight
        XCTAssertTrue(display.trendPoints.isEmpty)
        XCTAssertEqual(display.progressFraction ?? 0, 0.5, accuracy: 0.0001) // fraction still safe
        XCTAssertNotNil(display.doseText)                    // schedule still shown
    }

    func testRedactedKeepsOnlyStatusAndDayCount() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .redacted), family: .systemLarge, asOf: Self.d(46))
        XCTAssertFalse(display.statusPhrase.isEmpty)
        XCTAssertNotNil(display.dayCount)
        XCTAssertNil(display.doseText)
        XCTAssertNil(display.siteText)
        XCTAssertNil(display.progressFraction)
        XCTAssertNil(display.currentWeightText)
    }

    // MARK: - Semantic status and grammar variables

    // Hero + caption form one statement; the caption never restates the count,
    // and 0/1 days read as words ("Today" / "Tomorrow"), not a bare digit.
    func testSemanticStatusHeroAndCaptionsForRequiredCounts() {
        let cases: [(days: Int, phrase: String, hero: String, caption: String, due: Bool)] = [
            (0, "Dose due", "Today", "dose due", true),
            (1, "Next dose tomorrow", "Tomorrow", "next dose", false),
            (2, "Next dose in 2 days", "2", "days to next dose", false),
            (7, "Next dose in 7 days", "7", "days to next dose", false)
        ]

        for item in cases {
            let display = GlanceDisplayModel.make(
                from: semanticSnapshot(daysUntilNextInjection: item.days),
                family: .systemSmall,
                asOf: Self.d(46)
            )
            XCTAssertEqual(display.statusPhrase, item.phrase)
            XCTAssertEqual(display.dayCount, item.days)
            XCTAssertEqual(display.heroDayText, item.hero)
            XCTAssertEqual(display.dayCountCaption, item.caption)
            XCTAssertEqual(display.isDoseDue, item.due)
        }
    }

    func testPluralResourcesUseOtherFormForZeroAndMultiDayCounts() {
        let cases: [(days: Int, phrase: String, caption: String)] = [
            (0, "Next dose in 0 days", "0 days to next dose"),
            (1, "Next dose in 1 day", "1 day to next dose"),
            (2, "Next dose in 2 days", "2 days to next dose"),
            (7, "Next dose in 7 days", "7 days to next dose")
        ]

        for item in cases {
            XCTAssertEqual(String(localized: .glanceStatusNextDoseInDays(item.days)), item.phrase)
            XCTAssertEqual(String(localized: .glanceDayCaptionDaysToNextDose(item.days)), item.caption)
        }
    }

    func testOverdueSemanticStatusUsesDueCopyWithoutProducerPhrase() {
        let display = GlanceDisplayModel.make(
            from: semanticSnapshot(daysUntilNextInjection: -1),
            family: .systemSmall,
            asOf: Self.d(46)
        )
        XCTAssertEqual(display.statusPhrase, "Dose due")
        XCTAssertEqual(display.dayCountCaption, "dose due")
        XCTAssertEqual(display.heroDayText, "Today")
        XCTAssertTrue(display.isDoseDue)
    }

    func testSemanticStatusHeroCaptionAndSiteUsePassedLocale() {
        let tamil = Locale(identifier: "ta")
        let tamilDisplay = GlanceDisplayModel.make(
            from: semanticSnapshot(daysUntilNextInjection: 1),
            family: .systemSmall,
            asOf: Self.d(46),
            locale: tamil
        )
        XCTAssertEqual(tamilDisplay.statusPhrase, "அடுத்த அளவு நாளை")
        XCTAssertEqual(tamilDisplay.heroDayText, "நாளை")
        XCTAssertEqual(tamilDisplay.dayCountCaption, "அடுத்த அளவு")

        let hindi = Locale(identifier: "hi")
        let dueDisplay = GlanceDisplayModel.make(
            from: semanticSnapshot(daysUntilNextInjection: 0),
            family: .systemSmall,
            asOf: Self.d(46),
            locale: hindi
        )
        XCTAssertEqual(dueDisplay.statusPhrase, "खुराक देय है")
        XCTAssertEqual(dueDisplay.heroDayText, "आज")
        XCTAssertEqual(dueDisplay.dayCountCaption, "खुराक देय")

        let fullDisplay = GlanceDisplayModel.make(
            from: snapshot(privacy: .full),
            family: .systemMedium,
            asOf: Self.d(46),
            locale: hindi
        )
        XCTAssertEqual(fullDisplay.statusPhrase, "अगली खुराक कल है")
        XCTAssertEqual(fullDisplay.siteText, "जांघ · दाईं")
    }

    // MARK: - Weight delta, trend annotation, goal gridline

    func testFullTierCarriesSignedWeightDeltaAndTrendDelta() {
        // Fixture: 100 kg start, 90 kg current → lost 10 kg, shown as a signed
        // CHANGE with a real minus sign, alongside (not replacing) the absolute.
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemLarge, asOf: Self.d(46))
        XCTAssertEqual(display.weightDeltaText, "−10.0kg")
        XCTAssertNotNil(display.currentWeightText)
        // The chart delta is the all-time loss (start 100 → current 90), the same
        // figure as the row — NOT a windowed first-point-to-last-point change.
        XCTAssertEqual(display.trendDeltaText, "−10.0kg")
    }

    func testTrendDeltaIsAnchoredToStartingWeightNotFirstPlottedPoint() {
        // Starting weight (110) sits ABOVE the earliest logged weigh-in (100): the
        // plotted line starts at 100, but "since you started" must measure from 110.
        // This is the regression the redesign fixed — the old window delta read the
        // first plotted point (−10), understating the journey.
        let input = GlanceProjectionInput(
            startingWeightKg: 110,
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
            privacyMode: .full,
            producerBuild: "test",
            sourceWatermark: "w1"
        )
        let snap = GlanceProjectionBuilder.makeSnapshot(from: input, now: Self.d(46))
        let display = GlanceDisplayModel.make(from: snap, family: .systemLarge, asOf: Self.d(46))
        XCTAssertEqual(display.trendDeltaText, "−20.0kg")   // 110 − 90, not 100 − 90
        XCTAssertEqual(display.weightDeltaText, "−20.0kg")  // chart agrees with the row
        XCTAssertEqual(display.trendStartText, "100")       // line still starts at the earliest weigh-in
    }

    func testTrendStartAndGoalLabelsPresentUnderFullLargeOnly() {
        let large = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemLarge, asOf: Self.d(46))
        XCTAssertEqual(large.trendStartText, "100")  // earliest weigh-in, bare value
        XCTAssertEqual(large.trendGoalText, "80")    // goal value for the gridline label
        // Medium carries no trend → no chart labels.
        let medium = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemMedium, asOf: Self.d(46))
        XCTAssertNil(medium.trendStartText)
        XCTAssertNil(medium.trendGoalText)
        // Minimal drops the trend entirely.
        let minimal = GlanceDisplayModel.make(from: snapshot(privacy: .minimal), family: .systemLarge, asOf: Self.d(46))
        XCTAssertNil(minimal.trendStartText)
        XCTAssertNil(minimal.trendGoalText)
    }

    func testMinimalTierHasNoWeightDeltaOrTrendAnnotations() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .minimal), family: .systemLarge, asOf: Self.d(46))
        XCTAssertNil(display.weightDeltaText)
        XCTAssertNil(display.trendDeltaText)
        XCTAssertNil(display.trendGoalKg)
    }

    func testGoalGridlineAppearsOnlyWhenGoalIsNearTheTrendRange() {
        // Fixture: weights 90...100 (range 10), goal 80 → 10 kg below the range,
        // exactly at the max(3, range) threshold → plotted.
        let near = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemLarge, asOf: Self.d(46))
        XCTAssertEqual(near.trendGoalKg, 80)

        // A far goal (40 kg below) would flatten the trend line → omitted.
        var far = snapshot(privacy: .full)
        far.progress?.goalWeightKg = 50
        let display = GlanceDisplayModel.make(from: far, family: .systemLarge, asOf: Self.d(46))
        XCTAssertNil(display.trendGoalKg)

        // Medium has no trend, so no goal line either.
        let medium = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemMedium, asOf: Self.d(46))
        XCTAssertNil(medium.trendGoalKg)
    }

    func testGlanceSiteUsesMiddleDotSeparator() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemMedium, asOf: Self.d(46))
        XCTAssertEqual(display.siteText, "Thigh · Right")
    }

    func testNoDoseScheduledAndLegacyPhraseFallbacks() {
        let noDose = GlanceDisplayModel.make(
            from: semanticSnapshot(daysUntilNextInjection: nil),
            family: .systemSmall,
            asOf: Self.d(46)
        )
        XCTAssertEqual(noDose.statusPhrase, "No dose scheduled")

        var legacy = semanticSnapshot(daysUntilNextInjection: nil)
        legacy.status = SafeStatusSlice(legacyPhrase: "Next dose in 2 days")
        let fallback = GlanceDisplayModel.make(from: legacy, family: .systemSmall, asOf: Self.d(46))
        XCTAssertEqual(fallback.statusPhrase, "Next dose in 2 days")
    }

    func testExtraLargeAllowsTrendLikeLarge() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemExtraLarge, asOf: Self.d(46))
        XCTAssertGreaterThanOrEqual(display.trendPoints.count, 2)
    }

    func testMediumDoesNotCarryTrend() {
        let display = GlanceDisplayModel.make(from: snapshot(privacy: .full), family: .systemMedium, asOf: Self.d(46))
        XCTAssertTrue(display.trendPoints.isEmpty)
        XCTAssertNotNil(display.progressFraction)
    }

    // MARK: - Defensive states

    func testMissingSnapshotRendersPlaceholder() {
        let display = GlanceDisplayModel.make(from: nil, family: .systemSmall, asOf: Self.d(46))
        XCTAssertEqual(display, .placeholder)
    }

    func testExpiredSnapshotRendersRefreshNotStaleNumbers() {
        let snap = snapshot(privacy: .full)
        let afterTTL = snap.expiresAt.addingTimeInterval(1)
        let display = GlanceDisplayModel.make(from: snap, family: .systemLarge, asOf: afterTTL)
        XCTAssertNil(display.doseText)
        XCTAssertNil(display.currentWeightText)
        XCTAssertNil(display.dayCount)
        XCTAssertEqual(display.statusPhrase, "Open to refresh")
    }

    func testSurfaceFormattersAreLocaleAwareAndNonEmpty() {
        let locales = [
            Locale(identifier: "en_US"),
            Locale(identifier: "hi_IN"),
            Locale(identifier: "ta_IN"),
            Locale(identifier: "ar_SA")
        ]
        for locale in locales {
            XCTAssertFalse(SurfaceDisplayFormatters.dose(mg: 7.5, locale: locale).isEmpty)
            XCTAssertFalse(SurfaceDisplayFormatters.weight(kg: 92.25, unit: "kg", locale: locale).isEmpty)
            XCTAssertFalse(SurfaceDisplayFormatters.weight(kg: 92.25, unit: "lb", locale: locale).isEmpty)
            XCTAssertFalse(SurfaceDisplayFormatters.percent(0.425, locale: locale).isEmpty)
            XCTAssertFalse(
                SurfaceDisplayFormatters.dateRange(Self.d(1), Self.d(7), locale: locale).isEmpty
            )
        }
    }

    // The kg expectations pin MeasurementFormatter's short style ("12.4kg", no
    // space) — the same rendering the widget already uses for absolute weights.
    func testSignedWeightChangeAlwaysCarriesAnExplicitSign() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(SurfaceDisplayFormatters.signedWeightChange(kg: -12.4, unit: "kg", locale: locale), "−12.4kg")
        XCTAssertEqual(SurfaceDisplayFormatters.signedWeightChange(kg: 1.2, unit: "kg", locale: locale), "+1.2kg")
        XCTAssertTrue(SurfaceDisplayFormatters.signedWeightChange(kg: -5, unit: "lb", locale: locale).hasPrefix("−"))
    }
}
