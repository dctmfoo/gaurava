import XCTest

@MainActor
final class TabBarMinimizeUITests: XCTestCase {
    func testTabBarMinimizesOnScrollAndRestoresForTabNavigation() throws {
        let app = try launchSeededApp()

        // Seed-agnostic: confirm the Summary weight hero rendered with a numeric
        // value, rather than matching a hardcoded weight from one seed snapshot
        // (the old `CONTAINS "87"` re-broke when the owner seed was refreshed).
        let hero = app.descendants(matching: .any)["summary-current-weight-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 30), "Seeded Summary weight hero never appeared")

        let weightValue = app.descendants(matching: .any)["summary-current-weight-value"]
        XCTAssertTrue(weightValue.waitForExistence(timeout: 5), "Summary hero weight value never appeared")
        XCTAssertNotNil(
            weightValue.label.range(of: #"[0-9]"#, options: .regularExpression),
            "Expected the hero to show a numeric weight value, got '\(weightValue.label)'"
        )
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))

        app.gauravaTab(.results).tap()
        let weightCount = app.descendants(matching: .any)["results-weight-entry-count"]
        XCTAssertTrue(weightCount.waitForExistence(timeout: 20), "Seeded Results content never appeared")

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5), "Results scroll view never appeared")
        scrollView.swipeUp()
        scrollView.swipeUp()

        let minimizedTrendsControl = app.tabBars.buttons["Trends"]
        XCTAssertTrue(
            minimizedTrendsControl.waitForExistence(timeout: 5),
            "Expected the iOS 26 tab bar to keep the selected Trends tab as the corner icon after scrolling"
        )
        XCTAssertTrue(
            app.tabBars.buttons.element(boundBy: 1).waitForNonExistence(timeout: 5),
            "Expected the iOS 26 tab bar to collapse to one selected tab button after scrolling"
        )

        app.gauravaTab(.log).tap()
        XCTAssertTrue(app.gauravaTab(.log).waitForExistence(timeout: 5))
        XCTAssertTrue(app.gauravaTab(.log).isSelected)
    }

    private func launchSeededApp() throws -> XCUIApplication {
        let seedURL = URL(fileURLWithPath: Self.privateOwnerSeedPath)
        guard FileManager.default.fileExists(atPath: seedURL.path) else {
            throw XCTSkip("Private owner seed JSON is not available on this machine.")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-owner-seed-import",
            seedURL.path
        ]
        app.launch()
        return app
    }

    private static let privateOwnerSeedPath = PrivateOwnerSeed.path
}
