import Foundation

// The app's top-level tabs, addressable by deep link.
//
// Lifted to file scope (it was private to AppRootView) so the deep-link parser
// and tests can name it. Backed by a stable raw value that matches the URL host
// in `gaurava://<tab>` links surfaced from widgets, controls, and App Intents.
enum AppTab: String, Hashable, CaseIterable {
    case summary
    case jabs
    case results
    case log
    case care
}

enum DeepLinkPresentation: Equatable {
    case addWeight
    case addInjection
    case dailyNote
    case logSymptom
}

// Pure, Foundation-only parser for `gaurava://` deep links. Kept import-clean
// and side-effect-free so it is unit-testable and reusable from `.onOpenURL`,
// launch arguments, App Intents (Build 3), and controls.
enum DeepLinkRoute {
    /// The scheme registered in Info.plist (CFBundleURLTypes).
    static let scheme = "gaurava"

    /// Resolve a deep-link URL to a tab, or nil if it is not a recognized
    /// `gaurava://<tab>` link. The tab name may arrive as the URL host
    /// (`gaurava://jabs`) or, defensively, as the first path component
    /// (`gaurava:///jabs`).
    static func tab(for url: URL) -> AppTab? {
        guard let token = token(for: url) else { return nil }
        // Entry deep links land on their owning tab; presentation is triggered
        // separately by `presentation(for:)`.
        if token == GauravaScreen.addWeight.deepLinkHost { return .summary }
        if token == GauravaScreen.dailyNote.deepLinkHost { return .summary }
        if token == GauravaScreen.addInjection.deepLinkHost { return .jabs }
        // The Live Activity confirmation deep link lands on Jabs and presents
        // the same Add Injection sheet as the generic add-injection route.
        if token == GauravaScreen.jabConfirm.deepLinkHost { return .jabs }
        // The symptom-capture deep link lands on the Log tab; the capture sheet
        // is triggered separately (isLogSymptom).
        if token == GauravaScreen.logSymptom.deepLinkHost { return .log }
        return AppTab(rawValue: token)
    }

    static func presentation(for url: URL) -> DeepLinkPresentation? {
        guard let token = token(for: url) else { return nil }
        switch token {
        case GauravaScreen.addWeight.deepLinkHost:
            return .addWeight
        case GauravaScreen.addInjection.deepLinkHost,
             GauravaScreen.jabConfirm.deepLinkHost:
            return .addInjection
        case GauravaScreen.dailyNote.deepLinkHost:
            return .dailyNote
        case GauravaScreen.logSymptom.deepLinkHost:
            return .logSymptom
        default:
            return nil
        }
    }

    /// True for both generic and Live Activity entry routes that should present
    /// the in-app Add Injection sheet.
    static func isAddInjectionRequest(_ url: URL) -> Bool {
        presentation(for: url) == .addInjection
    }

    /// True for `gaurava://jab-confirm` — the Live Activity completion action.
    /// The app selects Jabs and presents the prefilled Add Injection sheet; it
    /// performs no clinical write on its own (the user taps Save).
    static func isInjectionConfirmation(_ url: URL) -> Bool {
        token(for: url) == GauravaScreen.jabConfirm.deepLinkHost
    }

    /// True for `gaurava://log-symptom` — the single system capture entry point.
    /// The app selects Log and presents the capture sheet; the symptom is written
    /// only when the user taps a chip in-app (the widget never writes).
    static func isLogSymptom(_ url: URL) -> Bool {
        presentation(for: url) == .logSymptom
    }

    private static func token(for url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        return (url.host ?? url.pathComponents.first { $0 != "/" })?.lowercased()
    }
}
