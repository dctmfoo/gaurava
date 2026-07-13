import Foundation

// Surface privacy preference, stored in App Group UserDefaults.
//
// Deliberately separate from the health payload and NOT CloudKit-synced: it is
// a per-device display choice, shared with the widget extension, and must never
// live alongside treatment data. Defaults to .minimal so the first run shows
// private detail until the owner opts into richer widgets.
struct SurfacePreferences: Sendable {
    private let appGroupIdentifier: String
    private static let privacyModeKey = "surface.privacyMode"
    private static let liveActivityEnabledKey = "surface.liveActivityEnabled"
    private static let injectionRemindersEnabledKey = "surface.injectionRemindersEnabled"

    init(appGroupIdentifier: String = GauravaSurface.appGroupIdentifier) {
        self.appGroupIdentifier = appGroupIdentifier
    }

    // UserDefaults is not Sendable, so resolve it per access rather than storing it.
    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroupIdentifier) }

    var privacyMode: SurfacePrivacyMode {
        get {
            guard let raw = defaults?.string(forKey: Self.privacyModeKey),
                  let mode = SurfacePrivacyMode(rawValue: raw) else { return .minimal }
            return mode
        }
        nonmutating set {
            defaults?.set(newValue.rawValue, forKey: Self.privacyModeKey)
        }
    }

    /// Raw in-app language override mirrored from `AppLocalization.storageKey`.
    /// Empty / missing means the surface follows the system locale.
    var languageCode: String {
        get { defaults?.string(forKey: GauravaSurface.surfaceLanguageCodeKey) ?? "" }
        nonmutating set {
            defaults?.set(newValue, forKey: GauravaSurface.surfaceLanguageCodeKey)
        }
    }

    var surfaceLocaleIdentifier: String {
        GauravaSurface.resolvedSurfaceLocaleIdentifier(languageCode: languageCode)
    }

    /// Whether the injection-day Live Activity may be started (Build 4). Opt-in:
    /// defaults to false so the surface only appears once the owner asks for it.
    /// Per-device, App Group UserDefaults — never CloudKit-synced clinical data.
    var liveActivityEnabled: Bool {
        get { defaults?.bool(forKey: Self.liveActivityEnabledKey) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Self.liveActivityEnabledKey) }
    }

    /// Whether local injection reminders may be scheduled on THIS device (see
    /// docs/injection-reminders-plan.html). Opt-in: defaults to false so nothing is
    /// ever scheduled until the user turns it on. Per-device and App Group only —
    /// deliberately NOT CloudKit-synced, so an opted-in iPhone and iPad don't both
    /// fire for the same dose (the user chooses which device reminds). Same model as
    /// `liveActivityEnabled`.
    var injectionRemindersEnabled: Bool {
        get { defaults?.bool(forKey: Self.injectionRemindersEnabledKey) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Self.injectionRemindersEnabledKey) }
    }
}
