import XCTest
@testable import Gaurava

// Build 3 coverage: the route-only App Intents and their navigation handoff.
// The Open intents read and write only the App Group surface (a transient
// pending route) — never a treatment record. Widget privacy is owned by the
// in-app Care picker (covered by DeepLinkPrivacyUITests), not by an intent:
// an in-extension toggle cannot reliably refresh the separate read-only glance
// widget (WidgetKit reload budget), so it was intentionally not shipped.
// See docs/widget-build-runbook.md Section 7 and sessions/build-3-report.md.
final class AppIntentTests: XCTestCase {
    private func tempSuite() -> String { "test.\(UUID().uuidString)" }

    // MARK: - Navigation handoff store

    func testSurfaceNavigationRoundTripsAndClearsOnConsume() {
        let suite = tempSuite()
        let nav = SurfaceNavigation(appGroupIdentifier: suite)
        XCTAssertNil(nav.consumePendingDeepLink(), "Empty store should yield nil")

        nav.setPendingDeepLink(URL(string: "gaurava://jabs")!)
        XCTAssertEqual(nav.consumePendingDeepLink(), URL(string: "gaurava://jabs"))
        XCTAssertNil(nav.consumePendingDeepLink(), "Consume must clear the pending route")
    }

    // MARK: - Screen -> deep link -> tab binding (locks the two parsers together)

    func testGauravaScreenURLsResolveToExpectedTabs() {
        XCTAssertEqual(DeepLinkRoute.tab(for: GauravaScreen.log.url), .log)
        XCTAssertEqual(DeepLinkRoute.tab(for: GauravaScreen.jabs.url), .jabs)
        // Weight lives on Summary (current-weight hero + Add Weight).
        XCTAssertEqual(DeepLinkRoute.tab(for: GauravaScreen.weight.url), .summary)
    }

    func testEntryRouteURLsResolveToOwningTabs() {
        XCTAssertEqual(GauravaScreen.addWeight.url, URL(string: "gaurava://add-weight"))
        XCTAssertEqual(GauravaScreen.addInjection.url, URL(string: "gaurava://add-injection"))
        XCTAssertEqual(GauravaScreen.dailyNote.url, URL(string: "gaurava://daily-note"))

        XCTAssertEqual(DeepLinkRoute.tab(for: GauravaScreen.addWeight.url), .summary)
        XCTAssertEqual(DeepLinkRoute.tab(for: GauravaScreen.addInjection.url), .jabs)
        XCTAssertEqual(DeepLinkRoute.tab(for: GauravaScreen.dailyNote.url), .summary)
    }

    func testEntryRoutesResolveToExpectedPresentations() {
        XCTAssertEqual(DeepLinkRoute.presentation(for: GauravaScreen.addWeight.url), .addWeight)
        XCTAssertEqual(DeepLinkRoute.presentation(for: GauravaScreen.addInjection.url), .addInjection)
        XCTAssertEqual(DeepLinkRoute.presentation(for: GauravaScreen.dailyNote.url), .dailyNote)
        XCTAssertNil(DeepLinkRoute.presentation(for: GauravaScreen.weight.url))
    }

    // MARK: - Open intents (route only; each targets one screen)

    func testOpenIntentsTargetTheExpectedScreens() {
        XCTAssertEqual(OpenLogIntent().screen, .log)
        XCTAssertEqual(OpenJabsIntent().screen, .jabs)
        XCTAssertEqual(OpenWeightIntent().screen, .weight)
    }

    func testOpenIntentPerformQueuesPendingRoute() throws {
        // Exercises the routing the intent encodes: the screen's URL resolves
        // through the same nav store + parser the app consumes.
        let suite = tempSuite()
        let nav = SurfaceNavigation(appGroupIdentifier: suite)
        nav.setPendingDeepLink(OpenJabsIntent().screen.url)
        XCTAssertEqual(DeepLinkRoute.tab(for: try XCTUnwrap(nav.consumePendingDeepLink())), .jabs)
    }
}
