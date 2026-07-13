import Foundation
import SwiftData
import UserNotifications

// App-side producer for the local injection reminder (see
// docs/injection-reminders-plan.html, Component 2).
//
// Mirrors GlancePublisher / InjectionActivityPublisher: reads the live
// ModelContext on the caller's (main) thread, builds an import-clean Sendable
// input, then hops to a Task for the async UserNotifications work so the
// synchronous producer path (save choke point / launch / foreground / remote
// import / Care toggle) is never blocked on the notification center. The pure
// InjectionReminderPlan makes the decision; this layer only delivers it.
//
// A FIXED request identifier guarantees a single pending reminder by
// construction: reconcile always replaces or removes "injection-reminder".
enum InjectionReminderScheduler {
    /// The one identifier every reminder uses, so there is never more than one
    /// pending (Apple's documented cancel-then-add pattern).
    static let requestIdentifier = "injection-reminder"

    /// Synchronous entry point joined into `SurfaceProducers.publish`. Reads the
    /// context on the main thread, then reconciles asynchronously. Failures are
    /// swallowed so a write never fails because of the reminder surface.
    static func reconcile(from context: ModelContext, now: Date = Date()) {
        #if GAURAVA_ONBOARDING_SANDBOX
        return
        #else
        guard let input = try? makeInput(from: context, now: now) else { return }
        let scheduler = SystemNotificationScheduler()
        Task { await reconcile(input: input, scheduler: scheduler, now: now) }
        #endif
    }

    /// Testable core: query authorization, run the pure decision, apply it. Injected
    /// `scheduler` lets tests assert the reconcile against a fake (the same way
    /// `SurfaceSnapshotStore` is injected into `GlancePublisher`).
    static func reconcile(
        input: Input,
        scheduler: NotificationScheduling,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let authorized = await scheduler.isAuthorized()
        let decision = InjectionReminderPlan.decide(
            scheduleState: input.scheduleState,
            reminderDaysBefore: input.reminderDaysBefore,
            optedIn: input.optedIn,
            authorized: authorized,
            privacy: input.privacy,
            doseMg: input.doseMg,
            medication: input.medication,
            now: now,
            calendar: calendar
        )
        await scheduler.apply(decision)
    }

    /// The import-clean, Sendable snapshot the decision needs — all primitives, no
    /// model objects, so it can cross into the async Task. Reads the SAME fields the
    /// glance publisher reads, through the SAME schedule engine, so every surface
    /// agrees on "next dose".
    struct Input: Sendable {
        var scheduleState: TreatmentScheduleState
        var reminderDaysBefore: Int
        var optedIn: Bool
        var privacy: SurfacePrivacyMode
        var doseMg: Double?
        var medication: Medication?
    }

    static func makeInput(from context: ModelContext, now: Date = Date()) throws -> Input {
        let profile = try context.fetch(FetchDescriptor<TrackerProfile>())
            .sorted { $0.updatedAt > $1.updatedAt }.first
        let injections = try context.fetch(FetchDescriptor<InjectionEntry>())
            .sorted { $0.injectionDate > $1.injectionDate }
        let pauses = try context.fetch(FetchDescriptor<TreatmentPause>())
        let isPaused = pauses.contains { $0.isActive(asOf: now) } || profile?.treatmentStatus == .paused

        let scheduleState = TreatmentScheduleEngine.state(
            status: profile?.treatmentStatus ?? .unknown,
            anchorDate: profile?.scheduleAnchorDate,
            newestInjectionDate: injections.first?.injectionDate,
            preferredInjectionDay: profile?.preferredInjectionDay,
            isPaused: isPaused,
            now: now
        )

        let prefs = SurfacePreferences()
        return Input(
            scheduleState: scheduleState,
            reminderDaysBefore: profile?.reminderDaysBefore ?? 1,
            optedIn: prefs.injectionRemindersEnabled,
            privacy: prefs.privacyMode,
            doseMg: profile?.plannedDoseMg ?? injections.first?.doseMg,
            medication: profile?.medicationIfKnown
        )
    }
}

/// Abstracts the notification-center operations the reconcile needs, so tests
/// inject a fake. The real adapter wraps `UNUserNotificationCenter`.
protocol NotificationScheduling: Sendable {
    /// Whether the user has granted notification authorization right now.
    func isAuthorized() async -> Bool
    /// Apply the decision to the single pending reminder: replace it on `.schedule`,
    /// remove it on `.none`.
    func apply(_ decision: InjectionReminderPlan.Decision) async
}

/// The real adapter over `UNUserNotificationCenter`. Stateless → Sendable.
struct SystemNotificationScheduler: NotificationScheduling {
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    func apply(_ decision: InjectionReminderPlan.Decision) async {
        let center = UNUserNotificationCenter.current()
        let store = ReminderFingerprintStore()

        switch decision {
        case .none:
            center.removePendingNotificationRequests(withIdentifiers: [InjectionReminderScheduler.requestIdentifier])
            store.value = nil

        case let .schedule(fireDate, dueDate, content):
            let copy = ReminderCopy.make(content)
            let fingerprint = Self.fingerprint(dueDate: dueDate, title: copy.title, body: copy.body)
            // Idempotent reconcile: the fan-out fires on every foreground, so when
            // nothing changed leave the existing pending request intact rather than
            // resetting its timer — which matters for the short-fuse "due today" case
            // whose fireDate shifts every reconcile.
            guard store.value != fingerprint else { return }

            center.removePendingNotificationRequests(withIdentifiers: [InjectionReminderScheduler.requestIdentifier])

            let unContent = UNMutableNotificationContent()
            unContent.title = copy.title
            unContent.body = copy.body
            unContent.sound = .default

            let request = UNNotificationRequest(
                identifier: InjectionReminderScheduler.requestIdentifier,
                content: unContent,
                trigger: Self.trigger(for: fireDate)
            )
            do {
                try await center.add(request)
                store.value = fingerprint
            } catch {
                // Add failed (e.g. authorization revoked mid-flight): clear so the
                // next reconcile retries instead of believing a request is pending.
                store.value = nil
            }
        }
    }

    /// Stable identity of a scheduled reminder: the due day plus the exact rendered
    /// copy (which already encodes privacy, timing, and language). Anchored to the
    /// due day, NOT the fireDate, so a short-fuse reminder isn't perpetually
    /// rescheduled; changed when the dose, privacy mode, or language changes.
    private static func fingerprint(dueDate: Date, title: String, body: String) -> String {
        "\(dueDate.timeIntervalSince1970)|\(title)|\(body)"
    }

    private static func trigger(for fireDate: Date) -> UNNotificationTrigger {
        let interval = fireDate.timeIntervalSinceNow
        if interval < 60 {
            // Short-fuse: a calendar trigger with second precision is fragile this
            // close to now; a time-interval trigger is robust.
            return UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}

/// Per-device fingerprint of the last successfully scheduled reminder, stored in
/// App Group UserDefaults. Mirrors `SurfacePreferences`: holds the suite id string
/// (not the `UserDefaults` instance) so it stays `Sendable`.
struct ReminderFingerprintStore: Sendable {
    private let appGroupIdentifier: String
    private static let key = "surface.injectionReminderFingerprint"

    init(appGroupIdentifier: String = GauravaSurface.appGroupIdentifier) {
        self.appGroupIdentifier = appGroupIdentifier
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroupIdentifier) }

    var value: String? {
        get { defaults?.string(forKey: Self.key) }
        nonmutating set {
            if let newValue {
                defaults?.set(newValue, forKey: Self.key)
            } else {
                defaults?.removeObject(forKey: Self.key)
            }
        }
    }
}

/// Renders the privacy-shaped `Content` into a localized lock-screen title + body.
/// Impure (resolves against the in-app language bundle via `appLocalizedValue`), so
/// the text follows the in-app picker and self-heals on every foreground reconcile.
enum ReminderCopy {
    static func make(_ content: InjectionReminderPlan.Content) -> (title: String, body: String) {
        switch content.detail {
        case .generic:
            // Redacted: the brand name (not translated) + a non-clinical body.
            return ("Gaurava", appLocalizedValue("A gentle reminder from Gaurava"))
        case .timing:
            return (appLocalizedValue("Injection reminder"), timingBody(content.daysUntilDueAtFire))
        case let .detailed(medication, doseMg):
            return (detailedTitle(medication: medication, doseMg: doseMg), timingBody(content.daysUntilDueAtFire))
        }
    }

    private static func timingBody(_ days: Int) -> String {
        switch days {
        case 0: return appLocalizedValue("Your dose is due today")
        case 1: return appLocalizedValue("Your dose is due tomorrow")
        default: return appLocalizedValue("Your dose is due in \(days) days")
        }
    }

    private static func detailedTitle(medication: Medication?, doseMg: Double?) -> String {
        let dose = doseMg.map { doseText($0) }
        switch (medication, dose) {
        case let (medication?, dose?): return "\(medication.displayName) \(dose)"
        case let (medication?, nil): return medication.displayName
        case let (nil, dose?): return dose
        case (nil, nil): return appLocalizedValue("Injection reminder")
        }
    }
}
