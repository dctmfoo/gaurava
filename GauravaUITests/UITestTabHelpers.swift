import XCTest

enum GauravaUITestTab {
    case summary
    case jabs
    case results
    case log
    case care

    var identifier: String {
        switch self {
        case .summary: "tab-summary"
        case .jabs: "tab-jabs"
        case .results: "tab-results"
        case .log: "tab-log"
        case .care: "tab-care"
        }
    }

    var fallbackTitle: String {
        switch self {
        case .summary: "Summary"
        case .jabs: "Jabs"
        case .results: "Trends"
        case .log: "Log"
        case .care: "Care"
        }
    }

    var tabIndex: Int {
        switch self {
        case .summary: 0
        case .jabs: 1
        case .results: 2
        case .log: 3
        case .care: 4
        }
    }
}

extension XCUIApplication {
    func gauravaTab(_ tab: GauravaUITestTab) -> XCUIElement {
        let identified = tabBars.buttons[tab.identifier]
        if identified.exists {
            return identified
        }

        let titled = tabBars.buttons[tab.fallbackTitle]
        if titled.exists {
            return titled
        }

        expandMinimizedTabBar()

        let expandedIdentified = tabBars.buttons[tab.identifier]
        if expandedIdentified.exists {
            return expandedIdentified
        }

        let expandedTitled = tabBars.buttons[tab.fallbackTitle]
        if expandedTitled.exists {
            return expandedTitled
        }

        return tabBars.buttons.element(boundBy: tab.tabIndex)
    }

    func expandMinimizedTabBar() {
        let firstButton = tabBars.buttons.element(boundBy: 0)
        if firstButton.exists && !tabBars.buttons.element(boundBy: 1).exists {
            firstButton.tap()
            _ = tabBars.buttons.element(boundBy: 1).waitForExistence(timeout: 1)
        }
        swipeDown()
        _ = tabBars.buttons.element(boundBy: 1).waitForExistence(timeout: 1)
    }

    func revealFirstRunInjectionDayPicker(timeout: TimeInterval = 5) -> XCUIElement {
        // The weekday chips are always shown now (no toggle); Monday is the anchor.
        let picker = buttons["firstRunInjectionDay-1"]
        if picker.waitForExistence(timeout: 1) {
            return picker
        }
        swipeUp()
        _ = picker.waitForExistence(timeout: timeout)
        return picker
    }

    /// Tap the onboarding primary Continue (advance one step), swiping up first if
    /// the floating action bar is below the fold.
    func tapOnboardingContinue(file: StaticString = #file, line: UInt = #line) {
        let cont = buttons["firstRunContinue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "missing firstRunContinue", file: file, line: line)
        if !cont.isHittable { swipeUp() }
        cont.tap()
    }

    /// Walk the mandatory weight baseline (Apple Health exempt → current → starting →
    /// goal) from the first weight step to the close screen, using each required
    /// field's one-tap satisfier. Shared by the onboarding-walking UI suites now that
    /// the combined numbers screen was split into one mandatory decision per screen
    /// (docs/onboarding-baseline-split-plan.html v1.3). Leaves the app on the close
    /// screen.
    func fillMandatoryOnboardingWeights(current: String, file: StaticString = #file, line: UInt = #line) {
        // Apple Health is its own exempt screen on a HealthKit-capable simulator.
        if buttons["firstRunHealthConnect"].waitForExistence(timeout: 5) {
            tapOnboardingContinue(file: file, line: line) // Apple Health → current
        }
        let currentField = textFields["firstRunCurrentWeight"]
        XCTAssertTrue(currentField.waitForExistence(timeout: 5), "missing firstRunCurrentWeight", file: file, line: line)
        currentField.tap()
        currentField.typeText(current)
        // Dismiss the keyboard by identifier — the "Done" label localizes.
        if buttons["firstRunKeyboardDone"].exists { buttons["firstRunKeyboardDone"].tap() }
        tapOnboardingContinue(file: file, line: line) // current → starting
        let sameAsToday = buttons["firstRunStartingSameAsToday"]
        XCTAssertTrue(sameAsToday.waitForExistence(timeout: 5), "missing firstRunStartingSameAsToday", file: file, line: line)
        if !sameAsToday.isHittable { swipeUp() }
        sameAsToday.tap()
        tapOnboardingContinue(file: file, line: line) // starting → goal (seeds the ruler)
        tapOnboardingContinue(file: file, line: line) // goal (seeded) → close
    }
}
