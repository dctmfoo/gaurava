import Foundation
import Observation

// The watch app's observable view-model. Holds the latest `GauravaGlanceSnapshot`
// the watch has received (over WatchConnectivity) or persisted (to its on-device
// App Group file). The watch is a read-only mirror in v1 — this never writes
// clinical data, only reflects what the phone produced.
//
// On launch it seeds from the on-device App Group file so the wrist shows the
// last-known state instantly (before the phone's WCSession has even activated);
// the receiver then refreshes it as fresh snapshots arrive.
//
// `@MainActor` so the receiver's background-thread decode can hand the (Sendable)
// snapshot across one isolation hop and SwiftUI observes mutations safely.
@MainActor
@Observable
final class WatchGlanceStore {
    private(set) var snapshot: GauravaGlanceSnapshot?

    private let store: SurfaceSnapshotStore

    init(store: SurfaceSnapshotStore = AppGroupFileSnapshotStore()) {
        self.store = store
        self.snapshot = store.read()
    }

    /// Apply a freshly-received snapshot (the receiver already persisted it to the
    /// shared file and reloaded the complications).
    func apply(_ snapshot: GauravaGlanceSnapshot) {
        self.snapshot = snapshot
    }

    /// Re-read the on-device file — used on foreground/activation to recover after
    /// the system reclaimed the watch app (e.g. the privacy-permission SIGKILL).
    func reloadFromDisk() {
        snapshot = store.read()
    }
}
