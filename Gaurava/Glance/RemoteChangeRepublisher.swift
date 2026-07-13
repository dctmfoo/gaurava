import CoreData
import Foundation
import SwiftData

// Build 2 spike: CloudKit remote-change-driven republish.
//
// SwiftData's CloudKit mirroring posts `NSPersistentStoreRemoteChange` on the
// underlying Core Data coordinator when it imports changes synced from another
// device. Observing it lets us republish the glance snapshot (and reload widget
// timelines) shortly after an iPhone edit lands on the iPad, narrowing the
// stale-iPad window that the `expiresAt` gate otherwise bounds at the TTL.
//
// This is intentionally gated behind one observer and is fully reversible:
// remove the `start(container:)` call to disable it. It is additive and cannot
// regress local writes — `GlancePublisher.publish` already swallows failures.
//
// Verification note: the actual cross-device wake cannot be exercised in the
// simulator (it needs two iCloud-signed devices). What is proven here is that
// the observer installs, debounces, and republishes without crashing; the
// cross-device timing is a device-only check recorded in the run report.
@MainActor
enum RemoteChangeRepublisher {
    private static var observer: NSObjectProtocol?
    private static var pending: Task<Void, Never>?

    /// Coalescing window: CloudKit import can post several notifications in a
    /// burst; one republish per burst is enough.
    private static let debounce: Duration = .milliseconds(400)

    static func start(container: ModelContainer) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            // `queue: .main` guarantees main-thread delivery; assert the actor
            // so we can touch the main-actor container without hopping.
            MainActor.assumeIsolated {
                scheduleRepublish(container: container)
            }
        }
    }

    static func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        pending?.cancel()
        pending = nil
    }

    private static func scheduleRepublish(container: ModelContainer) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            SurfaceProducers.publish(from: container.mainContext)
        }
    }
}
