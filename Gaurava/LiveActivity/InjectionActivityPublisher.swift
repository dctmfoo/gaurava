import Foundation
import SwiftData

// App-side producer for the injection-day Live Activity (Build 4).
//
// Mirrors GlancePublisher: reads the live ModelContext, builds an import-clean
// projection input, derives a decision via the pure InjectionActivityProjection,
// and applies it through the controller. Intentionally nonisolated + synchronous
// — invoked from the same main-thread sites as the glance publisher (the single
// save choke point, launch, foreground, and the Care opt-in toggle) so the
// ModelContext never crosses an isolation boundary. Failures are swallowed.
enum InjectionActivityPublisher {
    static func refresh(from context: ModelContext, now: Date = Date()) {
        let decision: InjectionActivityDecision
        if let input = try? makeInput(from: context) {
            decision = InjectionActivityProjection.decide(input: input, now: now)
        } else {
            // No readable store (e.g. a unit-test host without a container): make
            // sure nothing lingers on screen.
            decision = .inactive
        }
        // The decision is Sendable; hand it to the async controller in a Task so
        // the synchronous producer path (save choke point / launch / foreground /
        // Care toggle) is never blocked on ActivityKit.
        Task { await InjectionLiveActivityController.apply(decision) }
    }

    private static func makeInput(from context: ModelContext) throws -> InjectionActivityInput {
        let profile = try context.fetch(FetchDescriptor<TrackerProfile>())
            .sorted { $0.updatedAt > $1.updatedAt }.first
        let preference = try context.fetch(FetchDescriptor<UserPreference>())
            .sorted { $0.updatedAt > $1.updatedAt }.first
        let injections = try context.fetch(FetchDescriptor<InjectionEntry>())
            .sorted { $0.injectionDate > $1.injectionDate }
        let pauses = try context.fetch(FetchDescriptor<TreatmentPause>())
        let isPaused = pauses.contains { $0.isActive() } || profile?.treatmentStatus == .paused

        let prefs = SurfacePreferences()
        return InjectionActivityInput(
            optedIn: prefs.liveActivityEnabled,
            privacyMode: prefs.privacyMode,
            lastInjectionDate: injections.first?.injectionDate,
            lastInjectionSite: injections.first?.injectionSite,
            plannedDoseMg: profile?.plannedDoseMg,
            lastDoseMg: injections.first?.doseMg,
            preferredSites: preference?.preferredInjectionSites ?? InjectionSiteRotation.allSites,
            isPaused: isPaused
        )
    }
}

// One entry point that refreshes every system-facing surface from a single
// write, so callers can't forget one. Glance widgets + the injection Live
// Activity are both republished from the live context.
enum SurfaceProducers {
    static func mirrorLanguagePreference(_ languageCode: String) {
        #if GAURAVA_ONBOARDING_SANDBOX
        return
        #else
        SurfacePreferences().languageCode = languageCode
        GlancePublisher.reloadWidgets()
        #endif
    }

    static func publish(from context: ModelContext, now: Date = Date()) {
        #if GAURAVA_ONBOARDING_SANDBOX
        return
        #else
        GlancePublisher.publish(from: context, now: now)
        WatchSnapshotPublisher.publish(from: context, now: now)
        InjectionActivityPublisher.refresh(from: context, now: now)
        InjectionReminderScheduler.reconcile(from: context, now: now)
        #endif
    }
}
