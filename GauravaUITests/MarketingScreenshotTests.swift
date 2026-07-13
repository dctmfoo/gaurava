import XCTest

enum MarketingSeedVariant: String {
    case tirzepatide
    case semaglutide
    case mixed

    static func requested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MarketingSeedVariant {
        if let argumentIndex = arguments.firstIndex(of: "--seed-medication"),
           arguments.indices.contains(argumentIndex + 1),
           let variant = MarketingSeedVariant(rawValue: arguments[argumentIndex + 1]) {
            return variant
        }

        if let rawValue = environment["GAURAVA_SEED_MEDICATION"],
           let variant = MarketingSeedVariant(rawValue: rawValue) {
            return variant
        }

        // Compile-flag fallback (host env/args don't cross into the sim test
        // runner, same as the theme's GAURAVA_MARKETING_DARK). capture.sh sets
        // this via SWIFT_ACTIVE_COMPILATION_CONDITIONS for the semaglutide deck.
        #if GAURAVA_MARKETING_SEMAGLUTIDE
        return .semaglutide
        #else
        return .tirzepatide
        #endif
    }
}

enum MarketingSeedTheme: String {
    case system
    case light
    case dark

    static func requested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MarketingSeedTheme {
        if let argumentIndex = arguments.firstIndex(of: "--seed-theme"),
           arguments.indices.contains(argumentIndex + 1),
           let theme = MarketingSeedTheme(rawValue: arguments[argumentIndex + 1]) {
            return theme
        }

        if let rawValue = environment["GAURAVA_SEED_THEME"],
           let theme = MarketingSeedTheme(rawValue: rawValue) {
            return theme
        }

        #if GAURAVA_MARKETING_DARK
        return .dark
        #else
        return .light
        #endif
    }
}

enum MarketingAppTheme {
    static func requested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        for flag in ["--app-theme-id", "--gaurava-theme-id"] {
            if let argumentIndex = arguments.firstIndex(of: flag),
               arguments.indices.contains(argumentIndex + 1) {
                let value = arguments[argumentIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }

        for key in ["GAURAVA_THEME_ID", "GAURAVA_APP_THEME_ID"] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        #if GAURAVA_MARKETING_THEME_MIDNIGHT_FOCUS
        return "midnight-focus"
        #else
        return nil
        #endif
    }
}

/// Captures clean, device-resolution App Store marketing screenshots from a
/// fully-seeded "5 month journey" data set. Not a regression test in spirit —
/// it exists so the marketing deck is sourced from the REAL running app with
/// realistic data, never hand-mocked. The journey is synthesised relative to
/// "now" (see `MarketingSeed`) and injected through the owner-seed import launch
/// path (base64 env var), so the captures stay fresh whenever the suite runs.
///
/// Run only this class for marketing:
///   xcodebuild test -only-testing:GauravaUITests/MarketingScreenshotTests ...
/// then export the attachments from the .xcresult.
@MainActor
final class MarketingScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The in-app UI language is driven by xcodebuild's `-testLanguage` /
    /// `-testRegion` flags (host env vars do NOT cross into the simulator test
    /// runner, so an env-var approach silently captures English). Attachments are
    /// named generically; the exporter routes them into captures/<locale>/ based
    /// on the locale the run was launched with.
    private func launchSeeded() -> XCUIApplication {
        let seedVariant = MarketingSeedVariant.requested()
        let seedTheme = MarketingSeedTheme.requested()
        let appThemeID = MarketingAppTheme.requested()
        let app = XCUIApplication()
        var launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-owner-seed-import",
            "--gaurava-appearance",
            seedTheme.rawValue,
            "--seed-medication",
            seedVariant.rawValue,
            "--seed-theme",
            seedTheme.rawValue
        ]
        if let appThemeID {
            launchArguments += ["--gaurava-theme-id", appThemeID]
        }
        app.launchArguments = launchArguments
        app.launchEnvironment["GAURAVA_OWNER_SEED_JSON_B64"] = MarketingSeed.base64JSON(variant: seedVariant, theme: seedTheme)
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Brief settle for SwiftUI animations / async card loads. Locale-independent.
    private func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Tab-bar button by index (locale-independent navigation).
    private func tab(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        let tabBarButton = app.tabBars.buttons.element(boundBy: index)
        if tabBarButton.exists {
            return tabBarButton
        }

        let firstButton = app.tabBars.buttons.element(boundBy: 0)
        if firstButton.exists && !app.tabBars.buttons.element(boundBy: 1).exists {
            firstButton.tap()
            _ = app.tabBars.buttons.element(boundBy: 1).waitForExistence(timeout: 1)
        }
        app.swipeDown()
        _ = app.tabBars.buttons.element(boundBy: index).waitForExistence(timeout: 1)

        let expandedTabBarButton = app.tabBars.buttons.element(boundBy: index)
        if expandedTabBarButton.exists {
            return expandedTabBarButton
        }

        let identifiers = [
            "square.grid.2x2",
            "syringe.fill",
            "chart.line.uptrend.xyaxis",
            "note.text",
            "person.crop.circle"
        ]
        guard identifiers.indices.contains(index) else {
            return tabBarButton
        }

        return app.buttons.matching(identifier: identifiers[index]).firstMatch
    }

    private func waitForNavigationShell(_ app: XCUIApplication) -> Bool {
        if app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 2) {
            return true
        }
        return app.buttons
            .matching(identifier: "square.grid.2x2")
            .firstMatch
            .waitForExistence(timeout: 10)
    }

    func testCaptureMarketingDeck() throws {
        let app = launchSeeded()

        // Summary "Journey": wait for the seeded hero to materialise (the import
        // runs async in `.task`, so give it room) before capturing anything.
        // hi/ta/te default to Latin digits, so the seeded current weight (84.x)
        // appears in every locale — match on the digits, not a localised label.
        let hero = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "84")
        ).firstMatch
        XCTAssertTrue(
            hero.waitForExistence(timeout: 40),
            "seeded Summary hero (current weight 84.x) never appeared"
        )
        // Navigate tabs by INDEX — the "tab-*" accessibility id sits on the tab
        // CONTENT, not the tab-bar button, and the English titles don't match
        // under hi/ta/te. Index order: 0 summary · 1 jabs · 2 results · 3 log · 4 care.
        XCTAssertTrue(waitForNavigationShell(app))
        settle()
        attach(app, "01-summary-journey")

        // Jabs: injection timeline + next-due + rotation.
        tab(app, 1).tap()
        settle()
        attach(app, "02-jabs-timeline")

        // Results: three crops of the rich Trends screen — (a) the totals
        // overview, (b) the full dose-coloured trend chart (previously cut off
        // under the tab bar), and (c) the "By dose" weight-loss ledger. Scroll by
        // FLICKS only: a held drag would scrub the chart's chartXSelection gesture
        // instead of scrolling. Framing anchors on the By-dose section so it stays
        // correct across locales and seed shapes.
        tab(app, 2).tap()
        settle()
        attach(app, "03-results-overview")

        let resultsHeight = app.frame.height
        let byDose = app.descendants(matching: .any)
            .matching(identifier: "results-dose-phases").firstMatch
        // (b) Full chart: flick until the By-dose section first rises into the
        // lower part of the screen — the whole 440pt chart then sits above it.
        for _ in 0..<16 {
            if byDose.exists, byDose.frame.minY <= resultsHeight * 0.30 { break }
            if byDose.exists, byDose.frame.minY <= resultsHeight * 0.90,
               byDose.frame.minY >= resultsHeight * 0.30 { break }
            app.swipeUp(velocity: 320)
            settle(0.35)
        }
        settle(0.6)
        attach(app, "03b-results-chart")
        // (c) By dose: bring the section header up near the top.
        for _ in 0..<10 {
            if byDose.exists, byDose.frame.minY <= resultsHeight * 0.20 { break }
            app.swipeUp(velocity: 320)
            settle(0.35)
        }
        settle(0.6)
        attach(app, "03c-results-bydose")

        // Log: today's capture card + recent symptom/mood timeline.
        tab(app, 3).tap()
        settle()
        attach(app, "04-log-capture")
        app.swipeUp()
        settle()
        attach(app, "04b-log-recent")

        // Care: privacy + clinician export surface.
        tab(app, 4).tap()
        settle()
        attach(app, "05-care")

        // Care, part 2: the top of Care shows profile/goals, not the privacy
        // story — scroll to the "Privacy & Sync" section (Privacy Statement,
        // Data Controls, Widget Privacy, iCloud Sync) for the privacy slide.
        // Anchor two sections below (About Gaurava): scrolling until it's hittable
        // lifts the whole Privacy & Sync card into the upper third — the part the
        // top-aligned deck crop actually shows — in every locale.
        let careAnchorRow = app.descendants(matching: .any)
            .matching(identifier: "care-about-row").firstMatch
        var careScrolls = 0
        while !careAnchorRow.isHittable && careScrolls < 14 {
            app.swipeUp()
            settle(0.4)
            careScrolls += 1
        }
        settle()
        attach(app, "05b-care-privacy")
        // Back to the top of Care so the share-journey entry is easy to reach.
        for _ in 0..<careScrolls { app.swipeDown() }
        settle()

        // Share composer: open the "Share your journey" entry, wait for the
        // rendered card preview, capture it (locale-independent: nav by a11y id).
        let shareEntry = app.descendants(matching: .any)
            .matching(identifier: "share-journey-entry").firstMatch
        if shareEntry.waitForExistence(timeout: 8) {
            shareEntry.tap()
            let preview = app.descendants(matching: .any)
                .matching(identifier: "share-card-preview").firstMatch
            _ = preview.waitForExistence(timeout: 10)
            settle(1.6)   // let the ImageRenderer card settle
            attach(app, "06-share-composer")

            // The standalone SHARE CARD output (what people post) — capture each
            // template's rendered card on its own via the preview element's own
            // screenshot, switching templates by their a11y id. These become the
            // hero of the "share" slide instead of the composer chrome.
            for tpl in ["story", "milestone", "dataSheet"] {
                let btn = app.descendants(matching: .any)
                    .matching(identifier: "share-card-template-\(tpl)").firstMatch
                if btn.exists {
                    btn.tap()
                    settle(1.4)
                }
                guard preview.exists else { continue }
                let shot = XCTAttachment(screenshot: preview.screenshot())
                shot.name = "06-card-\(tpl)"
                shot.lifetime = .keepAlways
                add(shot)
            }
        }
    }
}

/// Builds the seed envelope (profile, weekly weights, weekly injections with a
/// standard titration, and a Log-tab side-effect/mood history) for a believable
/// ~5-month treatment journey. Everything is dated relative to `Date()` so the
/// "next injection" countdown and "today" capture stay realistic on every run.
enum MarketingSeed {
    static func base64JSON(variant: MarketingSeedVariant = .tirzepatide, theme: MarketingSeedTheme = .light) -> String {
        let data = try! JSONSerialization.data(withJSONObject: envelope(variant: variant, theme: theme), options: [])
        return data.base64EncodedString()
    }

    // MARK: Calendar helpers

    private static let cal = Calendar.current

    private static func at(_ daysFromNow: Int, hour: Int, minute: Int = 0) -> Date {
        let base = cal.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    // MARK: Journey shape

    /// Most recent injection: 7 days ago → next due today. This keeps the
    /// current demo pen cycle at a complete 4-week block in the by-dose ledger.
    private static var lastJabDay: Int { -7 }
    /// 24 weekly injections ending at `lastJabDay`.
    private static let injectionCount = 24

    private static let sites = [
        "Abdomen - Left", "Abdomen - Right",
        "Thigh - Left", "Thigh - Right",
        "Upper Arm - Left", "Upper Arm - Right"
    ]

    private static func doseSchedule(for variant: MarketingSeedVariant) -> [Double] {
        switch variant {
        case .tirzepatide:
            // QwikPen-aware titration: each visible phase is a whole 4-dose pen
            // cycle, or two cycles for 5 mg, so the by-dose ledger does not imply
            // partial pens like "3 weeks / 3 jabs".
            return (0..<injectionCount).map { i in
                switch i {
                case 0..<4: 2.5
                case 4..<12: 5
                case 12..<16: 7.5
                case 16..<20: 10
                default: 12.5
                }
            }
        case .semaglutide:
            return (0..<injectionCount).map { i in
                switch i {
                case 0..<4: 0.25
                case 4..<8: 0.5
                case 8..<12: 1
                case 12..<16: 1.7
                default: 2.4
                }
            }
        case .mixed:
            return (0..<injectionCount).map { i in
                switch i {
                case 0..<4: 0.25
                case 4..<8: 0.5
                case 8..<12: 1
                case 12..<16: 1.7
                case 16..<20: 2.4
                default: 10
                }
            }
        }
    }

    private static func currentMedication(for variant: MarketingSeedVariant) -> String {
        variant == .semaglutide ? "semaglutide" : "tirzepatide"
    }

    private static func doseText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func doseStepNote(forWeekIndex i: Int, schedule: [Double]) -> String? {
        guard schedule.indices.contains(i) else { return nil }
        if i == 0 { return "First dose - \(doseText(schedule[i])) mg start." }
        guard schedule[i] != schedule[i - 1] else { return nil }
        return "Stepped up to \(doseText(schedule[i])) mg."
    }

    /// 25 weekly weigh-ins, oldest → newest. Smooth, decelerating loss
    /// 98.0 → 84.2 kg (-13.8 kg, ~77% of the way to an 80 kg goal).
    private static let weeklyWeights: [Double] = [
        98.0, 97.4, 96.7, 96.0, 95.2, 94.5, 93.8, 93.1,
        92.4, 91.8, 91.2, 90.6, 90.0, 89.4, 88.8, 88.3,
        87.8, 87.3, 86.9, 86.5, 86.1, 85.6, 85.1, 84.6,
        84.2
    ]

    // MARK: Envelope

    private static func envelope(variant: MarketingSeedVariant, theme: MarketingSeedTheme) -> [String: Any] {
        // First weigh-in (oldest) anchors the treatment start.
        let startDay = -1 - (weeklyWeights.count - 1) * 7   // newest weigh-in is "yesterday"
        let startDate = at(startDay, hour: 7, minute: 30)
        let preferredWeekday = cal.component(.weekday, from: at(lastJabDay, hour: 9))
        let schedule = doseSchedule(for: variant)

        return [
            "meta": [
                "sourceProduct": "marketing-seed",
                "targetProduct": "gaurava",
                "subjectEmail": "gaurava.user@icloud.com",
                "exportedAt": stamp(Date()),
                "version": "marketing-\(variant.rawValue)-1"
            ],
            "account": ["email": "gaurava.user@icloud.com"],
            "data": [
                "profiles": [profile(startDate: startDate, preferredWeekday: preferredWeekday, variant: variant, schedule: schedule)],
                "userPreferences": [preference(theme: theme)],
                "weightEntries": weightEntries(),
                "injections": injections(schedule: schedule),
                "sideEffects": sideEffects(),
                "checkIns": checkIns()
            ]
        ]
    }

    private static func profile(
        startDate: Date,
        preferredWeekday: Int,
        variant: MarketingSeedVariant,
        schedule: [Double]
    ) -> [String: Any] {
        [
            "id": "marketing-profile",
            "age": 41,
            "gender": "",
            "height_cm": "178",
            "starting_weight_kg": "98.0",
            "goal_weight_kg": "80.0",
            "treatment_start_date": stamp(startDate),
            "medication": currentMedication(for: variant),
            "planned_dose_mg": doseText(schedule.last ?? 2.5),
            "preferred_injection_day": preferredWeekday,
            "reminder_days_before": 1,
            "created_at": stamp(startDate),
            "updated_at": stamp(Date())
        ]
    }

    private static func preference(theme: MarketingSeedTheme) -> [String: Any] {
        [
            "id": "marketing-pref",
            "weight_unit": "kg",
            "height_unit": "cm",
            "date_format": "DD/MM/YYYY",
            "week_starts_on": 1,
            "theme": theme.rawValue
        ]
    }

    private static func weightEntries() -> [[String: Any]] {
        // newest weigh-in = yesterday; one per week going back.
        weeklyWeights.enumerated().reversed().enumerated().map { (k, pair) in
            let (ascIndex, kg) = pair
            let day = -1 - k * 7
            let date = at(day, hour: 7, minute: 30)
            var entry: [String: Any] = [
                "id": "marketing-weight-\(ascIndex)",
                "weight_kg": String(format: "%.1f", kg),
                "recorded_at": stamp(date),
                "time_zone_identifier": TimeZone.current.identifier
            ]
            if ascIndex == 0 { entry["notes"] = "Treatment start" }
            return entry
        }
    }

    private static func injections(schedule: [Double]) -> [[String: Any]] {
        schedule.indices.map { i in
            let day = lastJabDay - (injectionCount - 1 - i) * 7
            let date = at(day, hour: 9)
            var entry: [String: Any] = [
                "id": "marketing-jab-\(i)",
                "dose_mg": doseText(schedule[i]),
                "injection_site": sites[i % sites.count],
                "injection_date": stamp(date),
                "time_zone_identifier": TimeZone.current.identifier
            ]
            if let note = doseStepNote(forWeekIndex: i, schedule: schedule) { entry["notes"] = note }
            if i % 4 == 0 { entry["batch_number"] = "LOT-\(7000 + i * 13)" }
            return entry
        }
    }

    // MARK: Log-tab history (side effects + daily check-ins)

    /// (dayFromNow, symptom, severity, mood, allClear, note)
    private static let captureDays: [(Int, String?, String?, String?, Bool, String?)] = [
        (0,   nil,            nil,        "good",  false, "Walked 40 min after dinner. Appetite easy."),
        (-1,  nil,            nil,        "good",  true,  nil),
        (-2,  "constipation", "mild",     "okay",  false, nil),
        (-4,  nil,            nil,        "great", true,  nil),
        (-6,  "nausea",       "mild",     "okay",  false, "Mild nausea in the morning, gone by noon."),
        (-9,  nil,            nil,        "good",  true,  nil),
        (-13, nil,            nil,        "good",  true,  nil),
        (-18, "nausea",       "mild",     "low",   false, nil),
        (-21, "constipation", "moderate", "okay",  false, "Plenty of water and fibre helped."),
        (-25, nil,            nil,        "good",  true,  nil),
        (-32, "nausea",       "moderate", "low",   false, "Rough day after the step-up. Settled by evening."),
        (-46, "nausea",       "mild",     "okay",  false, nil),
        (-60, nil,            nil,        "good",  true,  nil),
        (-95, "nausea",       "moderate", "low",   false, "First weeks — queasy but manageable.")
    ]

    private static func sideEffects() -> [[String: Any]] {
        captureDays.compactMap { (day, symptom, severity, _, _, _) in
            guard let symptom else { return nil }
            let date = at(day, hour: 12)
            var entry: [String: Any] = [
                "id": "marketing-se-\(symptom)-\(day)",
                "log_date": stamp(date),
                "symptom": symptom,
                "source": "app",
                "time_zone_identifier": TimeZone.current.identifier,
                "client_mutation_id": "seed-se-\(symptom)-\(day)"
            ]
            if let severity { entry["severity"] = severity }
            return entry
        }
    }

    private static func checkIns() -> [[String: Any]] {
        captureDays.map { (day, _, _, mood, allClear, note) in
            let date = at(day, hour: 12)
            var entry: [String: Any] = [
                "id": "marketing-ci-\(day)",
                "log_date": stamp(date),
                "all_clear": allClear,
                "source": "app",
                "time_zone_identifier": TimeZone.current.identifier,
                "client_mutation_id": "seed-ci-\(day)"
            ]
            if let mood { entry["mood_valence"] = mood }
            if let note { entry["note"] = note }
            return entry
        }
    }
}
