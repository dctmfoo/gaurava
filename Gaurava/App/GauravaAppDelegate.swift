import UIKit
import UserNotifications

// Notification-center delegate for injection reminders (see
// docs/injection-reminders-plan.html, Component 4).
//
// Installed via @UIApplicationDelegateAdaptor so it exists at launch — Apple
// requires the UNUserNotificationCenter delegate be set before anything
// interacts with it, which is the only way to catch a COLD launch from a
// reminder tap. The delegate is intentionally tiny and does no clinical work:
//
//   • A tap routes to the prefilled Add Injection sheet by reusing the existing
//     `gaurava://jab-confirm` deep-link queue — the same mechanism the Open App
//     Intents (AppIntents/OpenScreenIntents.swift) and the Live Activity use.
//     AppRootView already drains that App Group slot on `.active`, on the
//     UserDefaults change notification, and in `.task`, so both cold and warm
//     taps route with no change to AppRootView. Nothing is written until the
//     user taps Save in-app.
//   • A reminder that fires while the app is already foregrounded is suppressed
//     (empty presentation options) — Summary already shows the live countdown,
//     so a banner would be redundant noise.
final class GauravaAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// A tap on the reminder opens the prefilled Add Injection sheet. One line,
    /// no write — identical to the Open intents' routing. `nonisolated` because the
    /// UN delegate callbacks arrive off the main actor with non-Sendable arguments;
    /// `SurfaceNavigation` is a Sendable value type so the App Group write is safe
    /// from here.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        SurfaceNavigation().setPendingDeepLink(GauravaScreen.jabConfirm.url)
    }

    /// A reminder firing while the app is open stays silent — Summary already
    /// shows the countdown.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
