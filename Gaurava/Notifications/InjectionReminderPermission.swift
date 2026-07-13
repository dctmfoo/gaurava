import UserNotifications

// Shared permission flow for injection reminders (see
// docs/injection-reminders-plan.html, Component 3).
//
// iOS shows the system authorization alert EXACTLY ONCE; a "Don't Allow" can never
// be re-prompted programmatically (the user must go to Settings). So
// requestAuthorization must only ever run from an explicit user opt-in ("Turn on"),
// never as a launch side effect. Both opt-in surfaces — the Care toggle and the
// onboarding discovery step — funnel through this one helper.
@MainActor
enum InjectionReminderPermission {
    /// Request `.alert` + `.sound` authorization in response to an explicit opt-in.
    /// Returns whether reminders may now be delivered. Calling when already granted
    /// returns true without re-prompting; calling when denied returns false without
    /// a prompt (iOS only prompts from `.notDetermined`).
    static func request() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Whether reminders are currently authorized, so a surface can reflect the real
    /// status (off + a "Settings" hint) rather than a stale "on" after the user
    /// revoked notifications in Settings.
    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
