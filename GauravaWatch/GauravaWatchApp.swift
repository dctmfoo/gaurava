import SwiftUI

// Gaurava on the wrist — Phase 1 read-only glance.
//
// Owns the observable glance store and the WatchConnectivity receiver. The
// receiver activates the session at launch and refreshes the store (and the
// complications) whenever the phone publishes a fresh snapshot. The watch reads
// and renders only; it never writes clinical data in v1 (that is Phase 2).
//
// `App.init()` is main-actor isolated, so creating the `@MainActor` store and
// retaining the receiver here is safe. On foreground we re-read the on-device
// file to recover after the system reclaimed the app (e.g. the iPhone-privacy
// SIGKILL). Keep the layout flat — never nest `TabView`.
@main
struct GauravaWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: WatchGlanceStore
    private let receiver: WatchConnectivityReceiver

    init() {
        let store = WatchGlanceStore()
        _store = State(initialValue: store)
        let receiver = WatchConnectivityReceiver(store: store)
        self.receiver = receiver
        receiver.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.reloadFromDisk() }
                }
        }
    }
}

#Preview {
    WatchRootView(store: WatchGlanceStore())
}
