import XCTest

// Issue #13: the tabViewBottomAccessory quick-add bar is the unified in-app
// entry point for the most frequent logging actions. Each chip must route to
// the same tab + sheet as its widget deep-link equivalent (the bar shares the
// deep links' routing state in AppRootView).
@MainActor
final class QuickAddBarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()
        return app
    }

    func testWeightChipPresentsAddWeightSheetOnSummary() throws {
        let app = launchApp()
        let chip = app.descendants(matching: .any)["quickAdd-weight"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "Quick-add bar should be visible above the tab bar")
        chip.tap()

        XCTAssertTrue(app.gauravaTab(.summary).isSelected, "Weight chip should land on Summary")
        XCTAssertTrue(app.descendants(matching: .any)["add-weight-sheet"].waitForExistence(timeout: 5))
    }

    func testJabChipPresentsAddInjectionSheetOnJabs() throws {
        let app = launchApp()
        let chip = app.descendants(matching: .any)["quickAdd-jab"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()

        XCTAssertTrue(app.gauravaTab(.jabs).waitForExistence(timeout: 5))
        XCTAssertTrue(app.gauravaTab(.jabs).isSelected, "Jab chip should land on Jabs")
        XCTAssertTrue(app.descendants(matching: .any)["add-injection-sheet"].waitForExistence(timeout: 5))
    }

    func testNoteChipPresentsDailyNoteSheetOnSummary() throws {
        let app = launchApp()
        let chip = app.descendants(matching: .any)["quickAdd-note"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()

        XCTAssertTrue(app.gauravaTab(.summary).isSelected, "Note chip should land on Summary")
        XCTAssertTrue(app.navigationBars["Daily Note"].waitForExistence(timeout: 5))
    }
}
