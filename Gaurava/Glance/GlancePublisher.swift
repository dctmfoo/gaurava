import Foundation
import SwiftData
import WidgetKit

// App-side producer: reads the live model context, builds a privacy-shaped
// glance snapshot via the import-clean projection, writes it through the
// surface store, and reloads the widget timelines.
//
// Intentionally nonisolated and synchronous: it is invoked from the single
// save choke point (ModelWriteService.afterSave) and from launch/foreground,
// all on the main thread, so the ModelContext never crosses an isolation
// boundary. Failures (e.g. App Group unavailable in a unit-test host) are
// swallowed so writes never fail because of the surface.
enum GlancePublisher {
    static func publish(
        from context: ModelContext,
        store: SurfaceSnapshotStore = AppGroupFileSnapshotStore(),
        now: Date = Date()
    ) {
        do {
            let snapshot = try makeSnapshot(from: context, now: now)
            try store.write(snapshot)
            reloadWidgets()
        } catch {
            // No surface available (or fetch failed): leave the last snapshot in place.
        }
    }

    /// The single place that turns the live model context into a privacy-shaped
    /// glance snapshot. Reused by every surface producer (the App Group glance
    /// store here, and the WatchConnectivity transport in `WatchSnapshotPublisher`)
    /// so the watch and the widgets always consume the byte-identical snapshot.
    static func makeSnapshot(from context: ModelContext, now: Date = Date()) throws -> GauravaGlanceSnapshot {
        let input = try makeInput(from: context)
        return GlanceProjectionBuilder.makeSnapshot(from: input, now: now)
    }

    static func publishTombstone(
        store: SurfaceSnapshotStore = AppGroupFileSnapshotStore(),
        now: Date = Date()
    ) {
        try? store.writeTombstone(producerBuild: producerBuild, now: now)
        reloadWidgets()
    }

    private static func makeInput(from context: ModelContext) throws -> GlanceProjectionInput {
        let profile = try context.fetch(FetchDescriptor<TrackerProfile>())
            .sorted { $0.updatedAt > $1.updatedAt }.first
        let preference = try context.fetch(FetchDescriptor<UserPreference>())
            .sorted { $0.updatedAt > $1.updatedAt }.first
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        let injections = try context.fetch(FetchDescriptor<InjectionEntry>())
        let pauses = try context.fetch(FetchDescriptor<TreatmentPause>())

        let startingWeight = profile?.startingWeightKg
            ?? weights.sorted { $0.recordedAt < $1.recordedAt }.first?.weightKg
            ?? 0

        // Suppress the next-due math when there is no honest countdown — paused, or
        // an active user whose latest dose is stale and needs confirmation.
        let isPaused = pauses.contains { $0.isActive() } || profile?.treatmentStatus == .paused
        let scheduleState = TreatmentScheduleEngine.state(
            status: profile?.treatmentStatus ?? .unknown,
            anchorDate: profile?.scheduleAnchorDate,
            newestInjectionDate: injections.map(\.injectionDate).max(),
            preferredInjectionDay: profile?.preferredInjectionDay,
            isPaused: isPaused
        )
        let scheduleSuppressed = scheduleState == .paused || scheduleState == .needsConfirmation

        return GlanceProjectionInput(
            startingWeightKg: startingWeight,
            goalWeightKg: profile?.goalWeightKg ?? 0,
            weightUnit: preference?.weightUnit ?? "kg",
            weights: weights.map { .init(weightKg: $0.weightKg, recordedAt: $0.recordedAt) },
            injections: injections.map { .init(doseMg: $0.doseMg, site: $0.injectionSite, date: $0.injectionDate) },
            plannedDoseMg: profile?.plannedDoseMg,
            preferredSites: preference?.preferredInjectionSites ?? InjectionSiteRotation.allSites,
            privacyMode: SurfacePreferences().privacyMode,
            producerBuild: producerBuild,
            sourceWatermark: watermark(weights: weights, injections: injections),
            scheduleSuppressed: scheduleSuppressed
        )
    }

    private static var producerBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private static func watermark(weights: [WeightEntry], injections: [InjectionEntry]) -> String {
        let latest = (weights.map(\.updatedAt) + injections.map(\.updatedAt)).max()
        return latest.map { ISO8601DateFormatter().string(from: $0) } ?? "empty"
    }

    static func reloadWidgets() {
        for kind in GauravaSurface.iOSWidgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
