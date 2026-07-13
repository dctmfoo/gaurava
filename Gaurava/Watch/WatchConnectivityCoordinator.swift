import Foundation
import WatchConnectivity

// Phone-side owner of the shared `WCSession`: it activates the session, keeps it
// alive across the iOS-only inactive/deactivate lifecycle (so it survives the
// user switching paired watches), and triggers a republish the moment the
// session becomes usable so a freshly-activated watch immediately receives the
// current snapshot. Snapshots flow out through `WatchConnectivitySnapshotStore`;
// this type only manages the session and (Phase 1) ignores inbound traffic.
//
// `WCSessionDelegate` is `NSObjectProtocol`-based and its callbacks arrive on a
// background thread. The only thing that crosses the isolation boundary is the
// `@Sendable` `onActivated` hook, which itself hops to the main actor before
// touching the model context. Phase 2 fills in `didReceiveUserInfo` for
// watch-originated writes.
//
// Lives in the iOS app target only; never compiled into a watch target (the
// iOS-only `sessionDidBecomeInactive` / `sessionDidDeactivate` would not exist
// on watchOS).
final class WatchConnectivityCoordinator: NSObject, WCSessionDelegate {
    /// Called when the session (re)activates, so the just-activated session can
    /// push the current snapshot. Invoked on a background thread; the closure is
    /// responsible for hopping to the main actor.
    private let onActivated: @Sendable () -> Void

    init(onActivated: @escaping @Sendable () -> Void) {
        self.onActivated = onActivated
        super.init()
    }

    /// Activate the shared session if the platform supports it. Safe to call once
    /// at launch; the delegate must be set before `activate()`.
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
        guard activationState == .activated, error == nil else { return }
        onActivated()
    }

    // iOS-only: the watch availability changed (paired/unpaired, or the companion
    // app was installed/removed). Republish so a just-installed watch app receives
    // the current snapshot without waiting for the next save/foreground.
    func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.isWatchAppInstalled else { return }
        onActivated()
    }

    // iOS-only: when the user switches to a different paired watch the session is
    // torn down and must be reactivated to talk to the new device.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
