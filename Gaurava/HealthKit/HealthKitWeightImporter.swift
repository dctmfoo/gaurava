import Foundation
import HealthKit
import SwiftData

// Read-only Apple Health → Gaurava weight import.
//
// Scope (owner-locked, see docs/healthkit-weight-import.html):
//   - READ ONLY. We never write to Apple Health, so only
//     `NSHealthShareUsageDescription` + the HealthKit entitlement are required.
//   - FOREGROUND ANCHORED SYNC. Connect pulls full history; each later foreground
//     re-pulls only what changed, using a persisted `HKQueryAnchor`.
//
// Design split, kept deliberate so the part that matters is testable and the
// concurrency stays honest:
//   - `HealthKitWeightSource` (actor): all HKHealthStore traffic. Returns Sendable
//     value structs — never HealthKit reference types — across the boundary.
//   - `HealthKitWeightImport.apply` (nonisolated, pure): dedup + insert into a
//     SwiftData context. No HealthKit, no UserDefaults → unit-testable in memory.
//   - `HealthKitWeightSync` (@MainActor): the coordinator the UI + AppRootView
//     call. Owns the per-device opt-in flag, the anchor, and last-synced stamp.

// MARK: - Per-device storage keys

/// UserDefaults keys for the HealthKit weight import. All per-device: the opt-in
/// mirrors iOS per-app settings, and the anchor is tied to THIS device's HealthKit
/// store, so none of these may ride CloudKit. (`sourceHealthKitUUID` on
/// `WeightEntry` is the one piece that does sync, for cross-device dedup.)
enum HealthKitWeightKeys {
    /// Per-device opt-in. Mirrored by `@AppStorage` in Settings + AppRootView.
    static let enabled = "healthKitWeightSyncEnabled"
    /// Archived `HKQueryAnchor` (NSSecureCoding) for incremental fetches.
    static let anchor = "healthKitWeightAnchor"
    /// `Date.timeIntervalSinceReferenceDate` of the last successful sync.
    static let lastSyncedAt = "healthKitWeightLastSyncedAt"
}

// MARK: - Sendable transfer types

/// One Apple Health body-mass reading, normalized to Gaurava's canonical unit
/// (kilograms) and stripped of all HealthKit reference types so it crosses the
/// actor boundary cleanly.
struct ImportedWeightSample: Sendable, Equatable {
    let healthKitUUID: UUID
    let weightKg: Double
    let recordedAt: Date
    let timeZoneIdentifier: String?
}

/// Result of one anchored fetch: new readings, the UUIDs Health reported deleted
/// (ignored in v1 — see `HealthKitWeightSync.pull`), and the next anchor as Data.
struct HealthKitWeightFetch: Sendable {
    let added: [ImportedWeightSample]
    let deletedUUIDs: [UUID]
    let newAnchorData: Data?
}

/// Outcome surfaced to the Settings UI.
enum HealthKitWeightOutcome: Sendable, Equatable {
    case unavailable
    case imported(new: Int)
    case failed(String)
}

// MARK: - HealthKit access (actor)

/// All HKHealthStore traffic lives here. Async methods suspend on HealthKit's own
/// queues and resume on the actor; everything returned is Sendable.
actor HealthKitWeightSource {
    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)

    /// HealthKit is unavailable on some devices (e.g. older iPads pre-iPadOS 17).
    /// Always gate on this before touching the store.
    static var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Request READ access to body mass. Read-only: `toShare` is empty. iOS hides
    /// whether the user granted read, so this never tells us yes/no — we just query.
    func requestReadAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [bodyMass])
    }

    /// One-shot anchored fetch. `anchorData == nil` ⇒ full history; otherwise only
    /// objects saved/deleted since the anchor. Maps to Sendable value structs and
    /// archives the next anchor before returning.
    func fetch(anchorData: Data?) async throws -> HealthKitWeightFetch {
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)

        let kilograms = HKUnit.gramUnit(with: .kilo)
        let added: [ImportedWeightSample] = result.addedSamples.compactMap { sample in
            let kg = sample.quantity.doubleValue(for: kilograms)
            guard kg > 0 else { return nil }
            return ImportedWeightSample(
                healthKitUUID: sample.uuid,
                weightKg: kg,
                recordedAt: sample.startDate,
                timeZoneIdentifier: sample.metadata?[HKMetadataKeyTimeZone] as? String
            )
        }
        let deleted = result.deletedObjects.map(\.uuid)
        let newAnchorData = try? NSKeyedArchiver.archivedData(
            withRootObject: result.newAnchor, requiringSecureCoding: true
        )
        return HealthKitWeightFetch(added: added, deletedUUIDs: deleted, newAnchorData: newAnchorData)
    }
}

// MARK: - Dedup + insert (pure, testable)

enum HealthKitWeightImport {
    /// Insert the new readings as `WeightEntry` rows, skipping any whose HealthKit
    /// UUID already exists (whether typed-here, previously imported, or arrived via
    /// CloudKit). Saves through `ModelWriteService` so the glance snapshot republishes
    /// and CloudKit mirrors. Returns the number of rows actually created.
    ///
    /// Pure: depends only on the passed context + samples. No HealthKit, no
    /// UserDefaults — this is the seam the unit tests exercise.
    @discardableResult
    static func apply(samples: [ImportedWeightSample], into context: ModelContext, now: Date = Date()) throws -> Int {
        guard !samples.isEmpty else { return 0 }

        // One fetch → a Set of known HealthKit UUIDs, instead of the seed importer's
        // per-item full scan (which would be O(n²) over a long weight history).
        let existing = try context.fetch(FetchDescriptor<WeightEntry>())
        var seen = Set(existing.compactMap { $0.sourceHealthKitUUID?.lowercased() })

        var inserted = 0
        for sample in samples {
            let key = sample.healthKitUUID.uuidString.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let entry = WeightEntry(
                weightKg: sample.weightKg,
                recordedAt: sample.recordedAt,
                timeZoneIdentifier: sample.timeZoneIdentifier ?? TimeZone.current.identifier,
                sourceHealthKitUUID: sample.healthKitUUID.uuidString,
                createdAt: now,
                updatedAt: now
            )
            context.insert(entry)
            inserted += 1
        }

        if inserted > 0 {
            try ModelWriteService.saveOrThrow(context)
        }
        return inserted
    }
}

// MARK: - Coordinator (@MainActor)

@MainActor
enum HealthKitWeightSync {
    private static let source = HealthKitWeightSource()
    private static var defaults: UserDefaults { .standard }

    static var isAvailable: Bool { HealthKitWeightSource.isHealthDataAvailable }

    /// Per-device opt-in. The UI also reads this via `@AppStorage`.
    static var isEnabled: Bool {
        get { defaults.bool(forKey: HealthKitWeightKeys.enabled) }
        set { defaults.set(newValue, forKey: HealthKitWeightKeys.enabled) }
    }

    static var lastSyncedAt: Date? {
        let stamp = defaults.double(forKey: HealthKitWeightKeys.lastSyncedAt)
        return stamp > 0 ? Date(timeIntervalSinceReferenceDate: stamp) : nil
    }

    /// User tapped "Connect Apple Health": request authorization, pull, and flip the
    /// opt-in on. A fresh connect has no saved anchor, so this imports full history.
    static func connect(context: ModelContext) async -> HealthKitWeightOutcome {
        guard isAvailable else { return .unavailable }
        do {
            try await source.requestReadAuthorization()
            let outcome = try await pull(context: context)
            isEnabled = true
            return outcome
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Onboarding opt-in: request read authorization and flip the per-device opt-in
    /// on WITHOUT pulling. A mid-onboarding pull would insert `WeightEntry` rows,
    /// which flips `AppRootView.hasAnyData` and ejects the first-run gate — so the
    /// history import is deferred to the post-commit `syncIfEnabled` (and every later
    /// foreground). iOS hides read-grant status, so this returns whether we could ASK
    /// (available + no throw), not whether access was granted; a denied user simply
    /// imports nothing on the later pull.
    @discardableResult
    static func enableFromOnboarding() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await source.requestReadAuthorization()
            isEnabled = true
            return true
        } catch {
            return false
        }
    }

    /// User tapped "Sync Now": incremental pull against the saved anchor.
    static func syncNow(context: ModelContext) async -> HealthKitWeightOutcome {
        guard isAvailable else { return .unavailable }
        do {
            return try await pull(context: context)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Foreground hook (AppRootView, scenePhase == .active). Silent: self-gates on
    /// the opt-in + availability and swallows errors so a transient HealthKit hiccup
    /// never interrupts launch.
    static func syncIfEnabled(context: ModelContext) async {
        guard isEnabled, isAvailable else { return }
        _ = try? await pull(context: context)
    }

    /// Stop future syncs. Imported weights stay — they are Gaurava's data now — but
    /// the anchor is cleared so a later reconnect re-imports full history cleanly.
    static func disconnect() {
        isEnabled = false
        defaults.removeObject(forKey: HealthKitWeightKeys.anchor)
        defaults.removeObject(forKey: HealthKitWeightKeys.lastSyncedAt)
    }

    private static func pull(context: ModelContext) async throws -> HealthKitWeightOutcome {
        let anchorData = defaults.data(forKey: HealthKitWeightKeys.anchor)
        let fetch = try await source.fetch(anchorData: anchorData)
        // v1 intentionally ignores `fetch.deletedUUIDs`: once imported, a reading is
        // Gaurava's record and we don't silently delete what the user sees.
        let new = try HealthKitWeightImport.apply(samples: fetch.added, into: context)
        if let newAnchorData = fetch.newAnchorData {
            defaults.set(newAnchorData, forKey: HealthKitWeightKeys.anchor)
        }
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: HealthKitWeightKeys.lastSyncedAt)
        return .imported(new: new)
    }
}
