import XCTest
import SwiftUI
import WidgetKit

/// Renders the REAL Gaurava surface views (Home-Screen widget + Apple Watch
/// glance) off-device via `ImageRenderer`, seeded with the same ~5-month journey
/// the marketing deck uses, and attaches the PNGs so the deck generator can crop
/// them into the ecosystem slide. This is a self-contained target: it compiles
/// the widget + watch view sources and the Foundation-only shared glance model
/// directly (no @testable import, which would duplicate those shared types).
///
/// Run: xcodebuild test -only-testing:GauravaSurfaceSnapshots ... then export the
/// xcresult attachments (same path as MarketingScreenshotTests).
@MainActor
final class SurfaceSnapshotTests: XCTestCase {

    func testSharedSurfaceAdaptersMatchBrandTokens() {
        let tokens = SharedThemeTokens.brand
        assertWidgetColor(WidgetTheme.healthPrimary, token: tokens.healthPrimary)
        assertWidgetColor(WidgetTheme.textSecondary, token: tokens.textSecondary)
        assertWidgetColor(WidgetTheme.chartPlotSurface, token: tokens.chartPlotSurface)

        let expectedDoseFaces = [tokens.doseStarter, tokens.doseFive, tokens.doseSevenFive, tokens.doseTen, tokens.doseTwelveFive, tokens.doseFifteen]
        XCTAssertEqual(WidgetTheme.doseRamp.count, expectedDoseFaces.count)
        for (color, token) in zip(WidgetTheme.doseRamp, expectedDoseFaces) {
            assertWidgetColor(color, token: token)
        }

        assertColor(WatchTheme.healthPrimary, matches: tokens.healthPrimary.dark)
        assertColor(WatchTheme.textSecondary, matches: tokens.textSecondary.dark)
        assertColor(WatchTheme.medication, matches: tokens.medication.dark)
    }

    /// A believable, Full-privacy-tier glance for the marketing journey:
    /// next dose in 4 days · 12.5 mg · Upper Arm – Left · 84.3 kg · 76% to goal.
    private func seededSnapshot() -> GauravaGlanceSnapshot {
        let now = Date()
        let next = Calendar.current.date(byAdding: .day, value: 4, to: now) ?? now
        // The WHOLE journey (98 → 84.3), so the chart's start label matches the
        // 98 kg starting weight and the "−13.7 kg since you started" total.
        let journey: [Double] = [98.0, 96.0, 94.3, 92.5, 91.0, 89.4, 87.9, 86.7, 85.7, 85.0, 84.6, 84.3]
        let trend = journey.enumerated().map { i, kg in
            TrendPoint(date: Calendar.current.date(byAdding: .day, value: -14 * (journey.count - 1 - i), to: now) ?? now,
                       weightKg: kg)
        }
        return GauravaGlanceSnapshot(
            schemaVersion: 2,
            producerBuild: "marketing",
            generatedAt: now,
            expiresAt: Calendar.current.date(byAdding: .hour, value: 12, to: now) ?? now,
            sourceWatermark: "marketing-seed",
            privacyMode: .full,
            renderPolicyVersion: 1,
            nextAction: NextActionSlice(daysUntilNextInjection: 4, nextInjectionDate: next,
                                        doseMg: 12.5, suggestedSite: "Upper Arm - Left",
                                        doseBandIndex: doseColorBandIndex(12.5)),
            progress: ProgressSlice(progressToGoal: 0.76, currentWeightKg: 84.3, totalLostKg: 13.7,
                                    startingWeightKg: 98.0, goalWeightKg: 80.0, weightUnit: "kg"),
            trend: TrendSlice(points: trend),
            status: SafeStatusSlice.nextDose(daysUntil: 4)
        )
    }

    private func renderPNG(_ view: some View, size: CGSize, scale: CGFloat = 3, dark: Bool = false) -> UIImage? {
        let renderer = ImageRenderer(content:
            view.frame(width: size.width, height: size.height)
                .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.isOpaque = false
        return renderer.uiImage
    }

    private func attach(_ image: UIImage?, _ name: String) {
        guard let image else { XCTFail("nil render for \(name)"); return }
        let a = XCTAttachment(image: image)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func assertWidgetColor(_ color: Color, token: SharedColorToken, file: StaticString = #filePath, line: UInt = #line) {
        let uiColor = UIColor(color)
        let appearances: [(UIUserInterfaceStyle, UIAccessibilityContrast, SharedColorFace)] = [
            (.light, .normal, token.light),
            (.light, .high, token.lightHighContrast ?? token.light),
            (.dark, .normal, token.dark),
            (.dark, .high, token.darkHighContrast ?? token.dark)
        ]
        for (style, contrast, face) in appearances {
            let traits = UITraitCollection(mutations: { mutableTraits in
                mutableTraits.userInterfaceStyle = style
                mutableTraits.accessibilityContrast = contrast
            })
            assertUIColor(uiColor.resolvedColor(with: traits), matches: face, file: file, line: line)
        }
    }

    private func assertColor(_ color: Color, matches face: SharedColorFace, file: StaticString = #filePath, line: UInt = #line) {
        assertUIColor(UIColor(color), matches: face, file: file, line: line)
    }

    private func assertUIColor(_ color: UIColor, matches face: SharedColorFace, file: StaticString, line: UInt) {
        guard let components = color.cgColor.components else {
            XCTFail("Color has no components", file: file, line: line)
            return
        }
        XCTAssertEqual(components[0], face.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components[1], face.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components[2], face.blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components[3], face.alpha, accuracy: 0.001, file: file, line: line)
    }

    func testCaptureSurfaceSnapshots() throws {
        testSharedSurfaceAdaptersMatchBrandTokens()
        let snap = seededSnapshot()
        let entry = CareGlanceEntry(date: Date(), snapshot: snap, localeIdentifier: "en")

        // Home-Screen widgets — wrap in the real warm Gaurava surface (the
        // widget-only .containerBackground is a no-op off-host), clipped to the
        // widget's rounded rect. The medium family is compact; the large/iPad
        // extra-large families are the ones that carry the trend chart.
        let medium = CGSize(width: 360, height: 170)
        let widget = ZStack {
            GlanceSurfaceBackground()
            CareGlanceView(entry: entry).padding(16)
        }
        .frame(width: medium.width, height: medium.height)
        .clipShape(RoundedRectangle(cornerRadius: medium.height * 0.22, style: .continuous))
        attach(renderPNG(widget, size: medium), "surface-widget-medium")

        let large = CGSize(width: 360, height: 380)
        let largeWidget = ZStack {
            GlanceSurfaceBackground()
            CareGlanceView(entry: entry, familyOverride: .systemLarge)
                .padding(16)
        }
        .frame(width: large.width, height: large.height)
        .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
        attach(renderPNG(largeWidget, size: large), "surface-widget-large")

        let extraLarge = CGSize(width: 720, height: 340)
        let extraLargeWidget = ZStack {
            GlanceSurfaceBackground()
            CareGlanceView(entry: entry, familyOverride: .systemExtraLarge)
                .padding(22)
        }
        .frame(width: extraLarge.width, height: extraLarge.height)
        .clipShape(RoundedRectangle(cornerRadius: 54, style: .continuous))
        attach(renderPNG(extraLargeWidget, size: extraLarge, scale: 2), "surface-widget-extra-large")

        // Care Actions widget — the interactive Weight / Jab / Note quick-action
        // surface (a distinct Home-Screen widget), to fill the ecosystem slide.
        let actionsDisplay = GlanceDisplayModel.make(from: snap, family: .systemMedium, asOf: Date())
        let actionsEntry = CareActionsEntry(date: Date(), statusPhrase: actionsDisplay.statusPhrase, localeIdentifier: "en")
        let actions = ZStack {
            GlanceSurfaceBackground()
            CareActionsView(entry: actionsEntry).padding(16)
        }
        .frame(width: medium.width, height: medium.height)
        .clipShape(RoundedRectangle(cornerRadius: medium.height * 0.22, style: .continuous))
        attach(renderPNG(actions, size: medium), "surface-actions")

        // Apple Watch glance — render the real WatchGlanceBody directly over the
        // watch surface (the enclosing ScrollView collapses under ImageRenderer).
        // The watch is always dark-appearance. ~45mm point size.
        let watchSize = CGSize(width: 198, height: 280)
        let watchDisplay = GlanceDisplayModel.make(from: snap, family: .systemSmall)
        let watch = ZStack {
            WatchSurfaceBackground()
            WatchGlanceBody(display: watchDisplay)
        }
        .frame(width: watchSize.width, height: watchSize.height)
        .clipShape(RoundedRectangle(cornerRadius: watchSize.width * 0.30, style: .continuous))
        attach(renderPNG(watch, size: watchSize, dark: true), "surface-watch")

        // Share-card OUTPUT — the pure ShareJourneyCardView (what people post on
        // the subreddits), seeded with the same journey, rendered at its own
        // canvas. Two templates for the "worth sharing" slide.
        let card = ShareCardSnapshot(
            displayName: "",
            startWeightKg: 98.0, currentWeightKg: 84.3, goalWeightKg: 80.0,
            heightCm: 178, treatmentStartDate: Calendar.current.date(byAdding: .day, value: -161, to: Date()) ?? Date(),
            weekCount: 23, currentDoseMg: 12.5,
            weightPoints: cardWeightPoints(), doseSteps: cardDoseSteps()
        )
        for tpl in [ShareCardTemplate.story, .milestone, .dataSheet] {
            let cfg = ShareCardConfiguration(template: tpl, colorScheme: .light,
                                             privacyMode: .exact, dateVisibility: .hide, unit: .kg)
            let canvas = tpl.canvas.points
            let view = ShareJourneyCardView(snapshot: card, configuration: cfg)
                .environment(\.colorScheme, .light)
            attach(renderPNG(view, size: CGSize(width: canvas.width, height: canvas.height), scale: 2),
                   "surface-card-\(tpl.rawValue)")
        }
    }

    func testWidgetResourcesResolveWithPinnedSurfaceLocale() {
        let tamil = Locale(identifier: "ta")
        XCTAssertEqual(SurfaceLocalizedString.resolve(.widgetCareActionsWeight, locale: tamil), "எடை")
        XCTAssertEqual(SurfaceLocalizedString.resolve(.widgetCareActionsJab, locale: tamil), "ஊசி செலுத்துதல்")
        XCTAssertEqual(SurfaceLocalizedString.resolve(.widgetCareActionsNote, locale: tamil), "குறிப்பு")
        XCTAssertEqual(SurfaceLocalizedString.resolve(.widgetCareGlanceGoal, locale: tamil), "இலக்கு")

        let display = GlanceDisplayModel.make(
            from: seededSnapshot(),
            family: .systemMedium,
            locale: tamil
        )
        XCTAssertEqual(display.statusPhrase, "4 நாட்களில் அடுத்த அளவு")
    }

    private func cardWeightPoints() -> [ShareCardWeightPoint] {
        let kgs: [Double] = [98.0, 96.0, 94.3, 92.5, 91.0, 89.4, 87.9, 86.7, 85.7, 85.0, 84.6, 84.3]
        let doses: [Double] = [2.5, 2.5, 5, 5, 7.5, 7.5, 10, 10, 12.5, 12.5, 12.5, 12.5]
        let cal = Calendar.current; let now = Date()
        return kgs.enumerated().map { i, kg in
            let day = -7 * (kgs.count - 1 - i)
            return ShareCardWeightPoint(id: UUID(),
                                        date: cal.date(byAdding: .day, value: day, to: now) ?? now,
                                        weightKg: kg, doseMg: doses[i])
        }
    }

    private func cardDoseSteps() -> [ShareCardDoseStep] {
        let cal = Calendar.current; let now = Date()
        let steps: [(Double, Int)] = [(2.5, -154), (5, -126), (7.5, -98), (10, -63), (12.5, -28)]
        return steps.map { ShareCardDoseStep(doseMg: $0.0,
                                             startDate: cal.date(byAdding: .day, value: $0.1, to: now) ?? now) }
    }
}
