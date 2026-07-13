import XCTest

@MainActor
final class LocalizedScreenshotAuditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHindiMainTabsScreenshotAudit() throws {
        try auditMainTabs(
            LanguageAudit(
                code: "hi",
                locale: "hi_IN",
                summary: "सारांश",
                jabs: "इंजेक्शन",
                results: "परिणाम",
                log: "लॉग",
                care: "देखभाल"
            )
        )
    }

    func testTamilMainTabsScreenshotAudit() throws {
        try auditMainTabs(
            LanguageAudit(
                code: "ta",
                locale: "ta_IN",
                summary: "சுருக்கம்",
                jabs: "ஊசிகள்",
                results: "முடிவுகள்",
                log: "பதிவேடு",
                care: "கவனிப்பு"
            )
        )
    }

    func testTeluguMainTabsScreenshotAudit() throws {
        try auditMainTabs(
            LanguageAudit(
                code: "te",
                locale: "te_IN",
                summary: "సారాంశం",
                jabs: "ఇంజెక్షన్లు",
                results: "ఫలితాలు",
                log: "లాగ్",
                care: "జాగ్రత్త"
            )
        )
    }

    private func auditMainTabs(_ language: LanguageAudit) throws {
        let app = try launchSeededApp(language)
        let tabs: [(name: String, buttonTitle: String)] = [
            ("summary", language.summary),
            ("jabs", language.jabs),
            ("results", language.results),
            ("log", language.log),
            ("care", language.care)
        ]

        for tab in tabs {
            let button = app.tabBars.buttons[tab.buttonTitle]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(tab.name) tab for \(language.code)")
            button.tap()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            emitVisibleLabels(app, language: language.code, screen: tab.name)
            attach(app, "\(language.code)-\(tab.name)")

            if tab.name == "care" {
                scrollCarePrivacySectionIntoView(app)
                emitVisibleLabels(app, language: language.code, screen: "care-privacy")
                attach(app, "\(language.code)-care-privacy")
            }
        }
    }

    private func launchSeededApp(_ language: LanguageAudit) throws -> XCUIApplication {
        let seedURL = URL(fileURLWithPath: Self.privateOwnerSeedPath)
        guard FileManager.default.fileExists(atPath: seedURL.path) else {
            throw XCTSkip("Private owner seed JSON is not available on this machine.")
        }

        let seedData = try Data(contentsOf: seedURL)
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-owner-seed-import",
            seedURL.path,
            "-AppleLanguages",
            "(\(language.code))",
            "-AppleLocale",
            language.locale
        ]
        app.launchEnvironment["GAURAVA_OWNER_SEED_JSON_B64"] = seedData.base64EncodedString()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15), "Tab shell did not appear for \(language.code)")
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "localized-audit-\(name)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func scrollCarePrivacySectionIntoView(_ app: XCUIApplication) {
        let row = app.descendants(matching: .any)["care-privacy-statement-row"]
        for _ in 0..<8 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing Care privacy section")
    }

    private func emitVisibleLabels(_ app: XCUIApplication, language: String, screen: String) {
        var seen = Set<String>()
        let queries: [(String, XCUIElementQuery)] = [
            ("navigationBar", app.navigationBars),
            ("staticText", app.staticTexts),
            ("button", app.buttons),
            ("textField", app.textFields),
            ("switch", app.switches)
        ]

        for (kind, query) in queries {
            for element in query.allElementsBoundByIndex where element.exists {
                let label = normalized(element.label)
                guard !label.isEmpty else { continue }
                let key = "\(kind)|\(label)"
                guard seen.insert(key).inserted else { continue }
                print("LOCALIZATION_AUDIT\t\(language)\t\(screen)\t\(kind)\t\(label)")
            }
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let privateOwnerSeedPath = PrivateOwnerSeed.path
}

private struct LanguageAudit {
    let code: String
    let locale: String
    let summary: String
    let jabs: String
    let results: String
    let log: String
    let care: String
}
