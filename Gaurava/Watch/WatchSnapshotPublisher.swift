import Foundation
import SwiftData

// App-side producer that mirrors the current glance snapshot to the paired
// Apple Watch. Mirrors `GlancePublisher` exactly: it reuses the single
// context→snapshot factory (`GlancePublisher.makeSnapshot`) so the watch and the
// Home/Lock-Screen widgets always render the byte-identical, privacy-shaped
// snapshot, then hands it to the WatchConnectivity sink.
//
// Intentionally nonisolated and synchronous — invoked from the same single
// choke point as the other producers (`SurfaceProducers.publish`, on the main
// thread) so the `ModelContext` never crosses an isolation boundary. Failures
// (no paired watch, session not yet activated, WC unavailable) are swallowed so
// a clinical write never fails because of a surface.
enum WatchSnapshotPublisher {
    static func publish(
        from context: ModelContext,
        store: SurfaceSnapshotStore = WatchConnectivitySnapshotStore(),
        now: Date = Date()
    ) {
        do {
            let snapshot = try GlancePublisher.makeSnapshot(from: context, now: now)
            try store.write(snapshot)
        } catch {
            // No readable store / no paired watch / session not activated: the
            // next publish (activation or foreground) delivers the snapshot.
        }
    }
}
