import Foundation

// The small set of in-app destinations the system-facing layer can route to.
//
// Foundation only: compiled into BOTH the app and the widget extension so the
// App Intents (controls) and the interactive widget's `Link`s share one mapping
// from "screen" to a `gaurava://` deep link. The hosts intentionally match
// `AppTab.rawValue`; the app parses these URLs back to tabs with the existing
// `DeepLinkRoute.tab(for:)`. A unit test in the app target binds each
// `GauravaScreen.url` to the tab it must resolve to, so the two cannot drift.
//
// Weight has no tab of its own — it lives on Summary (current-weight hero + the
// Add Weight action), so it routes there.
enum GauravaScreen: String, CaseIterable, Sendable {
    case log
    case jabs
    case weight
    /// Opens the app to Summary and presents the Add Weight sheet. Pure route:
    /// the widget never writes the record; the user saves in-app.
    case addWeight
    /// Opens the app to Jabs and presents the Add Injection sheet. Pure route:
    /// the widget never writes the record; the user saves in-app.
    case addInjection
    /// Opens the app to Summary and presents the Daily Note sheet. Pure route:
    /// the widget never writes the note; the user saves in-app.
    case dailyNote
    /// Build 4: the injection-day Live Activity completion action. Opens the app
    /// to the Jabs tab AND presents the prefilled Add Injection confirmation
    /// (the form already defaults to planned dose / suggested site / now). It is
    /// a pure route — the user still taps Save to write the record in-app.
    case jabConfirm
    /// Log v1.1: the single system capture entry point (Action button / Control
    /// Center / Lock Screen). Opens the app to the Log tab AND presents the
    /// capture sheet where the full chip grid lives. A pure route — the user taps
    /// the symptom in-app, which writes the record (the widget never does).
    case logSymptom

    /// Deep-link host the app's `DeepLinkRoute` parser understands. Weight maps
    /// onto the Summary tab where weight is shown and logged; jab confirmation
    /// resolves to the Jabs tab (and additionally triggers the confirmation
    /// sheet via `DeepLinkRoute.isInjectionConfirmation`); symptom capture
    /// resolves to the Log tab (and triggers the capture sheet via
    /// `DeepLinkRoute.isLogSymptom`).
    var deepLinkHost: String {
        switch self {
        case .log: return "log"
        case .jabs: return "jabs"
        case .weight: return "summary"
        case .addWeight: return "add-weight"
        case .addInjection: return "add-injection"
        case .dailyNote: return "daily-note"
        case .jabConfirm: return "jab-confirm"
        case .logSymptom: return "log-symptom"
        }
    }

    /// The `gaurava://<host>` deep link that opens this screen.
    var url: URL {
        // Force-unwrap is safe: the scheme + host are static, valid components.
        URL(string: "gaurava://\(deepLinkHost)")!
    }
}
