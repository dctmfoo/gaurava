import Foundation
import WatchConnectivity

// Phone-side surface sink that mirrors the glance snapshot to the paired Apple
// Watch over WatchConnectivity. It is just another `SurfaceSnapshotStore`
// adapter (the App Group file store is the other), so the producer path treats
// the watch like any other surface — one snapshot contract, no watch-specific
// schema.
//
// `updateApplicationContext` is the right transport for a read-only mirror: it
// keeps only the *latest* state (overwrites prior context, ≈262 KB ceiling — our
// snapshot is a few KB), is delivered opportunistically in the background, and
// survives suspension so the watch sees the current snapshot the moment it next
// activates. The payload must be property-list types, so the Codable snapshot
// crosses as a single `Data` value via `WatchSnapshotPayload`.
//
// Lives in the iOS app target only (imports WatchConnectivity); never compiled
// into a watch target.
struct WatchConnectivitySnapshotStore: SurfaceSnapshotStore {
    func write(_ snapshot: GauravaGlanceSnapshot) throws {
        // Stateless: reach the thread-safe shared session at call time. (Holding a
        // `WCSession` would make the store non-Sendable; the protocol is Sendable.)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        // `updateApplicationContext` throws unless the session is activated, and
        // there is no point pushing when the companion watch app is not installed
        // (it would only fail with WatchAppNotInstalled). The coordinator
        // republishes on activation and on watch-state changes, so a later install
        // syncs at once. Producers swallow throws, so a transient WC error never
        // blocks a clinical write.
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        try session.updateApplicationContext(WatchSnapshotPayload.encode(snapshot))
    }

    /// The phone is the producer; it never reads a snapshot back from the watch.
    func read() -> GauravaGlanceSnapshot? { nil }
}
