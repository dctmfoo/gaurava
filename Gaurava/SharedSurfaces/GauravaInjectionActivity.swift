import ActivityKit
import Foundation

// The Live Activity contract for an injection-day surface (Build 4).
//
// Shared, like the rest of SharedSurfaces: compiled into BOTH the app (which
// starts / updates / ends the activity via ActivityKit) and the widget
// extension (which renders the Lock Screen + Dynamic Island presentations via
// WidgetKit's ActivityConfiguration). It imports ActivityKit only — no
// persistence, SwiftUI, WidgetKit, or the app's view model — so the surface
// boundary holds: clinical state stays app-owned and the extension only renders
// what the app projected.
//
// The dynamic ContentState is intentionally tiny (well under ActivityKit's 4KB
// limit) and already privacy-shaped by the producer: under a restrictive widget
// privacy mode the app omits the dose and site before the activity is started or
// updated, so the extension never holds raw values it must hide.
struct GauravaInjectionActivityAttributes: ActivityAttributes {
    enum StatusKind: String, Codable, Hashable, Sendable {
        case dueToday
        case overdue
        case logged
    }

    /// Dynamic content of the Live Activity. Codable + Hashable per ActivityKit;
    /// Sendable so it can cross the producer's concurrency boundary cleanly.
    struct ContentState: Codable, Hashable, Sendable {
        /// The day the injection is due (start-of-day in the user's calendar).
        var dueDate: Date
        /// When the due window closes. The activity must not remain past this —
        /// it is the ActivityContent `staleDate` and the projection ends the
        /// activity once `now >= windowEnd`.
        var windowEnd: Date
        /// Semantic low-detail status. The widget extension resolves this in
        /// its own bundle and locale instead of rendering app-produced prose.
        var statusKind: StatusKind?
        /// Legacy fallback only. New producers leave this nil.
        var statusPhrase: String?
        /// Planned dose in mg, or nil when hidden by privacy mode.
        var doseMg: Double?
        /// Suggested rotation site, or nil when hidden by privacy mode.
        var suggestedSite: String?
        /// True once today's injection has been logged; the activity shows a
        /// brief confirmation and then ends.
        var isCompleted: Bool

        var localizedStatusPhrase: String {
            switch statusKind {
            case .dueToday: return String(localized: .liveActivityStatusDueToday)
            case .overdue: return String(localized: .liveActivityStatusOverdue)
            case .logged: return String(localized: .liveActivityStatusLogged)
            case .none: return statusPhrase ?? String(localized: .liveActivityStatusDueToday)
            }
        }
    }

    /// Static (non-changing) label for the activity.
    var title: String

    /// Default static title used when the app starts an activity.
    static let defaultTitle = String(localized: .liveActivityInjectionDayTitle)
}
