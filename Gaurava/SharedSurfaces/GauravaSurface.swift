import Foundation

// Shared, import-clean constants for the glance surface.
// Foundation only: this file compiles into both the app and the widget
// extension. No SwiftData, SwiftUI, or WidgetKit here.
enum GauravaSurface {
    /// App Group shared between the app and the widget extension.
    static let appGroupIdentifier = "group.com.nags.gaurava"

    /// Per-device in-app language override mirrored into the App Group for
    /// surfaces running outside the app process. Empty / missing = follow system.
    static let surfaceLanguageCodeKey = "surface.languageCode"

    /// File name for the glance snapshot inside the App Group container.
    static let snapshotFileName = "glance-snapshot.json"

    /// WidgetKit `kind` for the Care Glance widget. Shared so the app's
    /// reload call and the widget's declaration cannot drift apart.
    static let careGlanceWidgetKind = "CareGlance"

    /// WidgetKit `kind` for the interactive Care Actions widget (Build 3).
    static let careActionsWidgetKind = "CareActions"

    /// iOS WidgetKit timelines that consume the shared glance snapshot.
    static let iOSWidgetKinds = [careGlanceWidgetKind, careActionsWidgetKind]

    /// WidgetKit `kind` for the watchOS glance complication (Phase 1). Shared so
    /// the watch's WCSession receiver (which reloads on a fresh snapshot) and the
    /// watch widget's declaration cannot drift apart — mirrors `careGlanceWidgetKind`.
    static let watchGlanceWidgetKind = "GauravaWatchGlance"

    /// Current snapshot schema version. Bump when the payload shape changes,
    /// and add a golden fixture for the prior version under GauravaTests/Fixtures.
    static let schemaVersion = 2

    /// Default time-to-live for a published snapshot. Past this, surfaces show
    /// a refresh state instead of stale clinical numbers.
    static let defaultTTL: TimeInterval = 60 * 60 * 6

    static func surfaceLocaleIdentifier(
        appGroupIdentifier: String = appGroupIdentifier,
        availableLocalizations: [String] = Bundle.main.localizations,
        fallback: Locale = .current
    ) -> String {
        let code = UserDefaults(suiteName: appGroupIdentifier)?
            .string(forKey: surfaceLanguageCodeKey)
        return resolvedSurfaceLocaleIdentifier(
            languageCode: code,
            availableLocalizations: availableLocalizations,
            fallback: fallback
        )
    }

    static func resolvedSurfaceLocaleIdentifier(
        languageCode: String?,
        availableLocalizations: [String] = Bundle.main.localizations,
        fallback: Locale = .current
    ) -> String {
        guard let languageCode else { return fallback.identifier }
        let trimmed = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback.identifier }

        let supported = Set(availableLocalizations.filter { $0 != "Base" })
        guard supported.contains(trimmed) else { return fallback.identifier }
        return trimmed
    }
}
