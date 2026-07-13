import Foundation

// Transport seam between the app (producer) and a surface (consumer).
// The first adapter is an App Group file; future Watch / other surfaces add
// their own adapters without changing the projection or persistence.
protocol SurfaceSnapshotStore: Sendable {
    func write(_ snapshot: GauravaGlanceSnapshot) throws
    func read() -> GauravaGlanceSnapshot?
}

extension SurfaceSnapshotStore {
    /// Write a cleared snapshot immediately after reset / import-reset.
    func writeTombstone(producerBuild: String, now: Date) throws {
        try write(.tombstone(producerBuild: producerBuild, now: now))
    }
}

/// The single snapshot codec, shared by every transport (App Group file +
/// WatchConnectivity) so the on-disk bytes and the on-the-wire bytes can never
/// drift. Foundation only; dates as ISO-8601 to match the golden fixtures.
enum GlanceSnapshotCodec {
    static func encode(_ snapshot: GauravaGlanceSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    /// Defensive: missing / torn / corrupt / wrong-version all decode to nil so a
    /// surface falls back to a placeholder rather than crashing.
    static func decode(_ data: Data) -> GauravaGlanceSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GauravaGlanceSnapshot.self, from: data)
    }
}

/// The WatchConnectivity application-context envelope. `updateApplicationContext`
/// accepts only property-list types, so the Codable snapshot crosses as a single
/// `Data` value under a stable key. Pure + Foundation-only: the phone encodes,
/// the watch decodes, and a unit test round-trips it without a live `WCSession`.
enum WatchSnapshotPayload {
    static let key = "glanceSnapshot"

    static func encode(_ snapshot: GauravaGlanceSnapshot) throws -> [String: Any] {
        [key: try GlanceSnapshotCodec.encode(snapshot)]
    }

    static func decode(_ context: [String: Any]) -> GauravaGlanceSnapshot? {
        guard let data = context[key] as? Data else { return nil }
        return GlanceSnapshotCodec.decode(data)
    }
}

/// Core file-backed store. Directory-agnostic so it is unit-testable against a
/// temp directory; the App Group store below delegates to it. Foundation only.
struct FileSnapshotStore: SurfaceSnapshotStore {
    let fileURL: URL?

    init(fileURL: URL?) { self.fileURL = fileURL }

    func write(_ snapshot: GauravaGlanceSnapshot) throws {
        guard let fileURL else { throw SurfaceStoreError.appGroupUnavailable }
        let data = try GlanceSnapshotCodec.encode(snapshot)
        // Atomic so a reader never sees a torn file; protection class lets a
        // locked-surface widget read after first unlock without exposing the
        // file while the device is locked.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Defensive read: missing / torn / corrupt / wrong-version all return nil
    /// so the surface falls back to a placeholder rather than crashing.
    func read() -> GauravaGlanceSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return GlanceSnapshotCodec.decode(data)
    }
}

/// App Group file-backed store. Foundation only; compiled into both targets.
struct AppGroupFileSnapshotStore: SurfaceSnapshotStore {
    let appGroupIdentifier: String
    let fileName: String

    init(appGroupIdentifier: String = GauravaSurface.appGroupIdentifier,
         fileName: String = GauravaSurface.snapshotFileName) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fileName = fileName
    }

    private var backing: FileSnapshotStore {
        let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName, conformingTo: .json)
        return FileSnapshotStore(fileURL: url)
    }

    func write(_ snapshot: GauravaGlanceSnapshot) throws { try backing.write(snapshot) }
    func read() -> GauravaGlanceSnapshot? { backing.read() }
}

enum SurfaceStoreError: Error {
    case appGroupUnavailable
}
