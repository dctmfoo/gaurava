import ActivityKit
import Foundation

// Owns the ActivityKit lifecycle for the injection-day Live Activity (Build 4).
//
// App-side only. Given a projection decision, it starts / updates / ends the
// (at most one) running activity. It performs ZERO clinical writes: it reads no
// SwiftData and creates no InjectionEntry. The only thing it touches is the
// system's ActivityKit state. Completion is driven by the user logging the jab
// in the app (which re-runs the projection and ends the activity), never by the
// activity or the extension writing a record.
//
// `apply` is a nonisolated `async` function: it awaits `update`/`end` directly
// (the Activity reference stays in one isolation region, so nothing is "sent"
// across actors under SWIFT_STRICT_CONCURRENCY=complete). The producer spawns it
// in a Task that captures only the Sendable decision. `Activity.request` must be
// called while the app is foreground; every caller satisfies that.
enum InjectionLiveActivityController {
    static func apply(_ decision: InjectionActivityDecision) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // The person disabled Live Activities for the app. Nothing to manage.
            return
        }

        let running = Activity<GauravaInjectionActivityAttributes>.activities

        switch decision {
        case .inactive:
            // End anything still on screen immediately.
            for activity in running {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

        case .active(let state):
            let content = ActivityContent(state: state, staleDate: state.windowEnd)
            if let activity = running.first {
                await activity.update(content)
            } else {
                start(content: content)
            }

        case .completed(let state):
            // Only confirm-and-end an activity that already exists; never start a
            // fresh activity just to mark it complete.
            let content = ActivityContent(state: state, staleDate: state.windowEnd)
            for activity in running {
                await activity.update(content)
                await activity.end(content, dismissalPolicy: .after(state.windowEnd))
            }
        }
    }

    private static func start(content: ActivityContent<GauravaInjectionActivityAttributes.ContentState>) {
        do {
            _ = try Activity.request(
                attributes: GauravaInjectionActivityAttributes(title: GauravaInjectionActivityAttributes.defaultTitle),
                content: content,
                pushType: nil
            )
        } catch {
            // Unsupported device, disabled, or over the limit: leave it unstarted.
        }
    }
}
