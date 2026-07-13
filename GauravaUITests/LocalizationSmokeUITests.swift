import XCTest

@MainActor
final class LocalizationSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHindiTabShellUsesLocalizedLabels() throws {
        try assertTabShellUsesLocalizedLabels(
            LanguageSmoke(
                code: "hi",
                locale: "hi_IN",
                summary: "सारांश",
                jabs: "इंजेक्शन",
                results: "रुझान",
                log: "लॉग",
                care: "देखभाल"
            )
        )
    }

    func testTamilTabShellUsesLocalizedLabels() throws {
        try assertTabShellUsesLocalizedLabels(
            LanguageSmoke(
                code: "ta",
                locale: "ta_IN",
                summary: "சுருக்கம்",
                jabs: "ஊசிகள்",
                results: "போக்குகள்",
                log: "பதிவேடு",
                care: "கவனிப்பு"
            )
        )
    }

    func testTeluguTabShellUsesLocalizedLabels() throws {
        try assertTabShellUsesLocalizedLabels(
            LanguageSmoke(
                code: "te",
                locale: "te_IN",
                summary: "సారాంశం",
                jabs: "ఇంజెక్షన్లు",
                results: "ధోరణులు",
                log: "లాగ్",
                care: "జాగ్రత్త"
            )
        )
    }

    func testHindiOnboardingDeltaUsesLocalizedCopy() throws {
        try assertOnboardingDeltaUsesLocalizedCopy(.hindi)
    }

    func testTamilOnboardingDeltaUsesLocalizedCopy() throws {
        try assertOnboardingDeltaUsesLocalizedCopy(.tamil)
    }

    func testTeluguOnboardingDeltaUsesLocalizedCopy() throws {
        try assertOnboardingDeltaUsesLocalizedCopy(.telugu)
    }

    func testHindiLogDeltaUsesLocalizedCopy() throws {
        try assertLogDeltaUsesLocalizedCopy(.hindi)
    }

    func testTamilLogDeltaUsesLocalizedCopy() throws {
        try assertLogDeltaUsesLocalizedCopy(.tamil)
    }

    func testTeluguLogDeltaUsesLocalizedCopy() throws {
        try assertLogDeltaUsesLocalizedCopy(.telugu)
    }

    func testHindiJabsEmptyStateUsesLocalizedCopy() throws {
        try assertJabsEmptyStateUsesLocalizedCopy(.hindi)
    }

    func testTamilJabsEmptyStateUsesLocalizedCopy() throws {
        try assertJabsEmptyStateUsesLocalizedCopy(.tamil)
    }

    func testTeluguJabsEmptyStateUsesLocalizedCopy() throws {
        try assertJabsEmptyStateUsesLocalizedCopy(.telugu)
    }

    private func assertTabShellUsesLocalizedLabels(_ language: LanguageSmoke) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "-AppleLanguages",
            "(\(language.code))",
            "-AppleLocale",
            language.locale
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))

        let expectations: [(GauravaUITestTab, String)] = [
            (.summary, language.summary),
            (.jabs, language.jabs),
            (.results, language.results),
            (.log, language.log),
            (.care, language.care)
        ]

        for (tab, expectedLabel) in expectations {
            let button = app.tabBars.buttons[expectedLabel]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(tab.identifier)")
            XCTAssertTrue(
                button.label.contains(expectedLabel),
                "Expected \(tab.identifier) to contain \(expectedLabel), got \(button.label)"
            )
        }

    }

    private func assertOnboardingDeltaUsesLocalizedCopy(_ language: LocalizationDeltaLanguage) throws {
        let app = XCUIApplication()
        app.launchArguments = localizedArguments(language, extra: [
            "--gaurava-show-first-run",
            "--gaurava-show-first-run-welcome"
        ])
        app.launch()

        XCTAssertTrue(app.buttons["firstRunBegin"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[language.welcomeHeadline].waitForExistence(timeout: 5))

        app.buttons["firstRunBegin"].tap()
        XCTAssertTrue(app.staticTexts[language.statusQuestion].waitForExistence(timeout: 5))

        app.buttons["firstRunTreatmentStatus-startingNow"].tap()
        app.buttons["firstRunContinue"].tap()
        XCTAssertTrue(app.staticTexts[language.medicineHeading].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[language.changeLaterInCare].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Change later in Care."].exists)

        app.buttons["firstRunContinue"].tap()
        let mondayChip = app.buttons["firstRunInjectionDay-1"]
        XCTAssertTrue(mondayChip.waitForExistence(timeout: 5))
        mondayChip.tap()

        let expectedPlan = language.weeklyPlan(weekdayName(for: language))
        XCTAssertTrue(app.staticTexts[expectedPlan].waitForExistence(timeout: 5), "Missing weekly plan: \(expectedPlan)")

        app.buttons["firstRunContinue"].tap()   // weekly-plan → reminders
        XCTAssertTrue(app.buttons["firstRunContinue"].waitForExistence(timeout: 5))
        app.buttons["firstRunContinue"].tap()   // reminders → Apple Health
        app.fillMandatoryOnboardingWeights(current: "90") // Apple Health → … → close

        XCTAssertTrue(app.descendants(matching: .any)["firstRunClose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[language.closeTitle].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[language.closeCardTitle].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[expectedPlan].waitForExistence(timeout: 5), "Missing close plan: \(expectedPlan)")
        XCTAssertFalse(app.staticTexts["You're set."].exists)
        XCTAssertFalse(app.staticTexts["What happens next"].exists)
        XCTAssertFalse(app.buttons["Open Gaurava"].exists)

        let open = app.buttons["firstRunContinue"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(open.label.contains(language.openAction), "Expected open label \(language.openAction), got \(open.label)")
        open.tap()
    }

    private func assertLogDeltaUsesLocalizedCopy(_ language: LocalizationDeltaLanguage) throws {
        let app = XCUIApplication()
        app.launchArguments = localizedArguments(language)
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        let logTab = app.tabBars.buttons[language.logTab]
        XCTAssertTrue(logTab.waitForExistence(timeout: 5), "Missing localized log tab: \(language.logTab)")
        logTab.tap()

        XCTAssertTrue(app.staticTexts[language.moodPrompt].waitForExistence(timeout: 10))

        app.buttons["mood-face-good"].tap()
        XCTAssertTrue(app.buttons["mood-confirmation-pill"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[language.tapToChange].waitForExistence(timeout: 5))

        let sideEffects = button(containingLabel: language.sideEffectEntry, in: app)
        XCTAssertTrue(sideEffects.waitForExistence(timeout: 5))
        XCTAssertTrue(sideEffects.label.contains(language.sideEffectEntry), "Expected side-effect label \(language.sideEffectEntry), got \(sideEffects.label)")

        let noteEntry = button(containingLabel: language.addNote, in: app)
        if !noteEntry.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(noteEntry.waitForExistence(timeout: 5))
        XCTAssertTrue(noteEntry.label.contains(language.addNote), "Expected note label \(language.addNote), got \(noteEntry.label)")

        if !sideEffects.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(sideEffects.waitForExistence(timeout: 5))
        sideEffects.tap()

        let picker = app.descendants(matching: .any)["side-effect-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[language.noSideEffects].waitForExistence(timeout: 5))
    }

    private func assertJabsEmptyStateUsesLocalizedCopy(_ language: LocalizationDeltaLanguage) throws {
        let app = XCUIApplication()
        app.launchArguments = localizedArguments(language)
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        let jabsTab = app.tabBars.buttons[language.jabsTab]
        XCTAssertTrue(jabsTab.waitForExistence(timeout: 5), "Missing localized Jabs tab: \(language.jabsTab)")
        jabsTab.tap()

        XCTAssertTrue(app.staticTexts[language.jabsEmptyTitle].waitForExistence(timeout: 10), "Missing localized Jabs title: \(language.jabsEmptyTitle)")
        XCTAssertTrue(app.staticTexts[language.jabsEmptyBody].waitForExistence(timeout: 5), "Missing localized Jabs body: \(language.jabsEmptyBody)")
        XCTAssertFalse(app.staticTexts["No jabs logged yet"].exists)
        XCTAssertFalse(app.staticTexts["Log each injection after it happens to build your treatment timeline."].exists)

        let logFirstInjection = app.buttons["jabsLogFirstInjection"]
        XCTAssertTrue(logFirstInjection.waitForExistence(timeout: 5))
        logFirstInjection.tap()

        XCTAssertTrue(app.descendants(matching: .any)["add-injection-sheet"].waitForExistence(timeout: 5))
        let navigationTitle = app.navigationBars[language.addInjectionTitle]
        let staticTitle = app.staticTexts[language.addInjectionTitle]
        XCTAssertTrue(
            navigationTitle.waitForExistence(timeout: 3) || staticTitle.waitForExistence(timeout: 3),
            "Missing localized Add Injection sheet title: \(language.addInjectionTitle)"
        )
        XCTAssertFalse(app.navigationBars["Add Injection"].exists)
        XCTAssertFalse(app.staticTexts["Add Injection"].exists)
    }

    private func button(containingLabel label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    private func localizedArguments(_ language: LocalizationDeltaLanguage, extra: [String] = []) -> [String] {
        [
            "--gaurava-reset-local-data-for-testing",
            "-AppleLanguages",
            "(\(language.code))",
            "-AppleLocale",
            language.locale
        ] + extra
    }

    private func weekdayName(for language: LocalizationDeltaLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.locale)
        return formatter.weekdaySymbols[1]
    }
}

private struct LanguageSmoke {
    let code: String
    let locale: String
    let summary: String
    let jabs: String
    let results: String
    let log: String
    let care: String
}

private struct LocalizationDeltaLanguage: Sendable {
    let code: String
    let locale: String
    let welcomeHeadline: String
    let logTab: String
    let jabsTab: String
    let statusQuestion: String
    let medicineHeading: String
    let changeLaterInCare: String
    let closeTitle: String
    let closeCardTitle: String
    let openAction: String
    let moodPrompt: String
    let tapToChange: String
    let sideEffectEntry: String
    let addNote: String
    let noSideEffects: String
    let jabsEmptyTitle: String
    let jabsEmptyBody: String
    let addInjectionTitle: String
    let weeklyPlan: @Sendable (String) -> String

    static let hindi = LocalizationDeltaLanguage(
        code: "hi",
        locale: "hi_IN",
        welcomeHeadline: "निजी GLP-1 ट्रैकिंग।",
        logTab: "लॉग",
        jabsTab: "इंजेक्शन",
        statusQuestion: "क्या GLP-1 शुरू कर दिया है?",
        medicineHeading: "दवा",
        changeLaterInCare: "बाद में देखभाल में बदलें।",
        closeTitle: "आप तैयार हैं।",
        closeCardTitle: "आगे क्या होगा",
        openAction: "Gaurava खोलें",
        moodPrompt: "आज का दिन कैसा है?",
        tapToChange: "बदलने के लिए टैप करें",
        sideEffectEntry: "कुछ और? दुष्प्रभाव",
        addNote: "नोट जोड़ें",
        noSideEffects: "कोई दुष्प्रभाव नहीं",
        jabsEmptyTitle: "अभी तक कोई इंजेक्शन दर्ज नहीं किया गया है",
        jabsEmptyBody: "अपने उपचार की समयरेखा बनाने के लिए प्रत्येक इंजेक्शन लगने के बाद उसे दर्ज करें।",
        addInjectionTitle: "इंजेक्शन जोड़ें",
        weeklyPlan: { "हर \($0) के लिए योजना बनाई गई है। अभी कोई उलटी गिनती नहीं है।" }
    )

    static let tamil = LocalizationDeltaLanguage(
        code: "ta",
        locale: "ta_IN",
        welcomeHeadline: "தனிப்பட்ட GLP-1 கண்காணிப்பு.",
        logTab: "பதிவேடு",
        jabsTab: "ஊசிகள்",
        statusQuestion: "GLP-1 ஐத் தொடங்கிவிட்டீர்களா?",
        medicineHeading: "மருந்து",
        changeLaterInCare: "பின்னர் கவனிப்பு பிரிவில் மாற்றிக்கொள்ளலாம்.",
        closeTitle: "அனைத்தும் தயார்.",
        closeCardTitle: "அடுத்து என்ன நடக்கும்",
        openAction: "Gaurava-ஐத் திறக்கவும்",
        moodPrompt: "இன்றைய நாள் எப்படி இருக்கிறது?",
        tapToChange: "மாற்ற தட்டவும்",
        sideEffectEntry: "வேறு ஏதேனும்? பக்கவிளைவுகள்",
        addNote: "குறிப்பைச் சேர்க்கவும்",
        noSideEffects: "பக்கவிளைவுகள் இல்லை",
        jabsEmptyTitle: "இதுவரை எந்த ஊசிகளும் பதிவு செய்யப்படவில்லை",
        jabsEmptyBody: "உங்கள் சிகிச்சை காலவரிசையை உருவாக்க, ஒவ்வொரு முறை ஊசி செலுத்திய பிறகும் அதை பதிவு செய்யவும்.",
        addInjectionTitle: "ஊசியைச் சேர்க்கவும்",
        weeklyPlan: { "ஒவ்வொரு \($0) அன்றும் திட்டமிடப்பட்டுள்ளது. இன்னும் கவுண்ட்டவுன் இல்லை." }
    )

    static let telugu = LocalizationDeltaLanguage(
        code: "te",
        locale: "te_IN",
        welcomeHeadline: "వ్యక్తిగత GLP-1 ట్రాకింగ్.",
        logTab: "లాగ్",
        jabsTab: "ఇంజెక్షన్లు",
        statusQuestion: "GLP-1 ప్రారంభించారా?",
        medicineHeading: "మందు",
        changeLaterInCare: "తర్వాత జాగ్రత్తలో మార్చుకోండి.",
        closeTitle: "మీరు సిద్ధంగా ఉన్నారు.",
        closeCardTitle: "తర్వాత ఏమి జరుగుతుంది",
        openAction: "Gaurava తెరవండి",
        moodPrompt: "ఈరోజు ఎలా ఉంది?",
        tapToChange: "మార్చడానికి ట్యాప్ చేయండి",
        sideEffectEntry: "ఇంకేదైనా ఉందా? దుష్ప్రభావాలు",
        addNote: "గమనికను జోడించండి",
        noSideEffects: "దుష్ప్రభావాలు లేవు",
        jabsEmptyTitle: "ఇంకా ఎలాంటి ఇంజెక్షన్లు నమోదు చేయలేదు",
        jabsEmptyBody: "మీ చికిత్స కాలక్రమాన్ని రూపొందించడానికి ప్రతి ఇంజెక్షన్ తీసుకున్న తర్వాత దానిని నమోదు చేయండి.",
        addInjectionTitle: "ఇంజెక్షన్‌ను జోడించండి",
        weeklyPlan: { "ప్రతి \($0) కోసం ప్రణాళిక చేయబడింది. ఇంకా కౌంట్‌డౌన్ లేదు." }
    )
}
