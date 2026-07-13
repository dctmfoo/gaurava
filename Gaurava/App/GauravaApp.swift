import SwiftData
import SwiftUI

@main
struct GauravaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    // Installed at launch so the UNUserNotificationCenter delegate exists before
    // anything touches it — required to catch a cold launch from a reminder tap
    // (see GauravaAppDelegate / injection-reminders-plan.html Component 4).
    @UIApplicationDelegateAdaptor(GauravaAppDelegate.self) private var appDelegate
    // Watched so a live in-app language switch re-renders any pending reminder in
    // the new language (the reminder copy is language-dependent and the scheduler
    // fingerprints the rendered title/body).
    @AppStorage(AppLocalization.storageKey) private var appLanguageCode = ""
    private let modelContainer = GauravaModelContainer.make()
    private let watchCoordinator: WatchConnectivityCoordinator

    init() {
        AppThemeSelection.applyLaunchOverrideIfPresent()

        // Install the single republish hook on the save choke point so every
        // persisted write refreshes every system-facing surface (glance widgets
        // + the watch mirror + the injection Live Activity) from one place.
        ModelWriteService.afterSave = { context in
            SurfaceProducers.publish(from: context)
        }

        // Activate the phone side of WatchConnectivity. On (re)activation, push
        // the current snapshot so a freshly-paired/relaunched watch syncs at once
        // (the closure hops to the main actor before touching the context).
        let container = modelContainer
        let coordinator = WatchConnectivityCoordinator {
            Task { @MainActor in
                SurfaceProducers.publish(from: container.mainContext)
            }
        }
        watchCoordinator = coordinator
        coordinator.start()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modelContainer(modelContainer)
                .onAppear {
                    SurfaceProducers.mirrorLanguagePreference(appLanguageCode)
                    SurfaceProducers.publish(from: modelContainer.mainContext)
                    // Spike: republish when CloudKit imports remote changes,
                    // narrowing the stale-iPad window (Build 2).
                    if CloudKitConfiguration.isEnabled {
                        RemoteChangeRepublisher.start(container: modelContainer)
                    }
                }
                .onChange(of: appLanguageCode) { _, newCode in
                    SurfaceProducers.mirrorLanguagePreference(newCode)
                    // Re-render the single pending reminder in the chosen language.
                    InjectionReminderScheduler.reconcile(from: modelContainer.mainContext)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                SurfaceProducers.mirrorLanguagePreference(appLanguageCode)
                SurfaceProducers.publish(from: modelContainer.mainContext)
            }
        }
    }
}
