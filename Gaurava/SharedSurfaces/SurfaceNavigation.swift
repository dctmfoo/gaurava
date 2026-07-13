import Foundation

// Cross-process navigation handoff between the system-facing layer and the app.
//
// A foreground App Intent (e.g. `OpenLogIntent`, run from a Control Center
// control) cannot reference the app's SwiftUI navigation state directly — its
// type is also compiled into the widget extension. So the intent writes a
// pending `gaurava://` deep link here (App Group, Foundation only) and the app
// consumes it on launch / activation, routing through the SAME
// `DeepLinkRoute.tab(for:)` parser used by `.onOpenURL`.
//
// Deliberately mirrors `SurfacePreferences`: store the suite identifier string
// (not a `UserDefaults` instance) so the struct stays `Sendable`. Stores nothing
// clinical — only a transient route token that is cleared as soon as it is read.
struct SurfaceNavigation: Sendable {
    private let appGroupIdentifier: String
    private static let pendingDeepLinkKey = "surface.pendingDeepLink"

    init(appGroupIdentifier: String = GauravaSurface.appGroupIdentifier) {
        self.appGroupIdentifier = appGroupIdentifier
    }

    // UserDefaults is not Sendable, so resolve it per access rather than storing it.
    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroupIdentifier) }

    /// Record where the app should route the next time it becomes active.
    func setPendingDeepLink(_ url: URL) {
        defaults?.set(url.absoluteString, forKey: Self.pendingDeepLinkKey)
    }

    /// Read and clear the pending deep link. Returns nil when nothing is queued
    /// or the stored value is not a valid URL.
    func consumePendingDeepLink() -> URL? {
        guard let raw = defaults?.string(forKey: Self.pendingDeepLinkKey) else { return nil }
        defaults?.removeObject(forKey: Self.pendingDeepLinkKey)
        return URL(string: raw)
    }
}
