import AppIntents

// Open-the-app App Intents that power the Control Center controls (and are
// discoverable in Shortcuts / Spotlight). Compiled into BOTH the app and the
// widget extension (the controls in the extension reference these types).
//
// They are pure ROUTERS: each foregrounds the app and records a pending
// `gaurava://` deep link via `SurfaceNavigation`; the app consumes it and routes
// through the same `DeepLinkRoute` parser as `.onOpenURL`. No clinical data is
// read or written here.
//
// `supportedModes = .foreground(.immediate)` is the iOS 26 replacement for the
// deprecated `openAppWhenRun = true`: it foregrounds the app, then runs
// `perform()` in the APP's process. `perform()` finishes its write before
// returning, per the App Intents contract.

struct OpenLogIntent: AppIntent {
    static let title = LocalizedStringResource(
        "appIntent.openLog.title",
        defaultValue: "Open Log",
        table: "Localizable"
    )
    static let description = IntentDescription(LocalizedStringResource(
        "appIntent.openLog.description",
        defaultValue: "Open Gaurava to the daily log.",
        table: "Localizable"
    ))
    static var supportedModes: IntentModes { .foreground(.immediate) }

    /// The screen this intent routes to — exposed so routing is unit-testable
    /// without the App Group; `perform()` is thin glue over it.
    var screen: GauravaScreen { .log }

    func perform() async throws -> some IntentResult {
        SurfaceNavigation().setPendingDeepLink(screen.url)
        return .result()
    }
}

struct OpenJabsIntent: AppIntent {
    static let title = LocalizedStringResource(
        "appIntent.openJabs.title",
        defaultValue: "Open Jabs",
        table: "Localizable"
    )
    static let description = IntentDescription(LocalizedStringResource(
        "appIntent.openJabs.description",
        defaultValue: "Open Gaurava to your injections.",
        table: "Localizable"
    ))
    static var supportedModes: IntentModes { .foreground(.immediate) }

    var screen: GauravaScreen { .jabs }

    func perform() async throws -> some IntentResult {
        SurfaceNavigation().setPendingDeepLink(screen.url)
        return .result()
    }
}

struct OpenWeightIntent: AppIntent {
    static let title = LocalizedStringResource(
        "appIntent.openWeight.title",
        defaultValue: "Open Weight",
        table: "Localizable"
    )
    static let description = IntentDescription(LocalizedStringResource(
        "appIntent.openWeight.description",
        defaultValue: "Open Gaurava to your weight summary.",
        table: "Localizable"
    ))
    static var supportedModes: IntentModes { .foreground(.immediate) }

    var screen: GauravaScreen { .weight }

    func perform() async throws -> some IntentResult {
        SurfaceNavigation().setPendingDeepLink(screen.url)
        return .result()
    }
}

// Log v1.1: the single system capture entry point. Like the Open intents this is
// a pure foreground ROUTER — it records `gaurava://log-symptom` and returns; the
// app opens the Log tab and presents the capture sheet, and the symptom is
// written only when the user taps a chip in-app. No clinical write happens here
// or in the extension process.
struct LogSideEffectIntent: AppIntent {
    static let title = LocalizedStringResource(
        "appIntent.logSideEffect.title",
        defaultValue: "Log a Side Effect",
        table: "Localizable"
    )
    static let description = IntentDescription(LocalizedStringResource(
        "appIntent.logSideEffect.description",
        defaultValue: "Open Gaurava to note a side effect for today.",
        table: "Localizable"
    ))
    static var supportedModes: IntentModes { .foreground(.immediate) }

    var screen: GauravaScreen { .logSymptom }

    func perform() async throws -> some IntentResult {
        SurfaceNavigation().setPendingDeepLink(screen.url)
        return .result()
    }
}
