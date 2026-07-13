import Foundation
import WatchConnectivity
import WidgetKit

// Watch-side WatchConnectivity receiver. Activates the session and, whenever the
// phone publishes a fresh application context, decodes the shared
// `GauravaGlanceSnapshot`, persists it to the on-device App Group file (so the
// watch app and its complication share one source of truth, exactly as the iOS
// app and its widgets do — App Groups bridge on-device, never iPhone↔Watch),
// reloads the complication timelines, and refreshes the observable store.
//
// `WCSessionDelegate` is `NSObjectProtocol`-based and delivers on a background
// thread with non-`Sendable` `[String: Any]` payloads. We decode on that thread
// into the `Sendable` snapshot and only that snapshot crosses the single
// `@MainActor` hop — the same isolation discipline the Live Activity controller
// used. No writes anywhere here; the watch is a read-only mirror in v1.
//
// watchOS only requires `session(_:activationDidCompleteWith:error:)`; the
// iOS-only inactive/deactivate callbacks do not exist on watchOS, so they are
// absent here by design.
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    private let store: WatchGlanceStore
    private let fileStore: SurfaceSnapshotStore

    init(store: WatchGlanceStore, fileStore: SurfaceSnapshotStore = AppGroupFileSnapshotStore()) {
        self.store = store
        self.fileStore = fileStore
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // A context delivered while we were not yet listening is retained by the
        // session; pick it up on activation so a cold launch syncs immediately.
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        if !context.isEmpty { ingest(context) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingest(applicationContext)
    }

    // Decode on the delivery (background) thread, persist + reload off the main
    // actor, then hop once to the main actor with the Sendable snapshot.
    private func ingest(_ context: [String: Any]) {
        guard let snapshot = WatchSnapshotPayload.decode(context) else { return }
        try? fileStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: GauravaSurface.watchGlanceWidgetKind)
        // Capture the (Sendable, @MainActor) store directly so the @Sendable Task
        // does not capture `self` (a non-Sendable NSObject delegate).
        let store = store
        Task { @MainActor in store.apply(snapshot) }
    }
}
