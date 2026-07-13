#if DEBUG
import Foundation
import SwiftData

/// Test-only launch hook that seeds a specific post-onboarding SwiftData state so the
/// adaptive-states UI suite can exercise the Summary/Jabs layouts directly, instead of
/// driving them through onboarding.
///
/// Why this exists: the mandatory hard gate means a fresh install now always commits a
/// complete weight baseline, so partial/legacy data shapes (profile-only, current-only,
/// goal-only, injection-day-only) are no longer onboarding-reachable. They are still
/// real for legacy installs, Apple Health imports, and CloudKit-synced devices with
/// gaps, so they keep their regression coverage here — and these data-driven surface
/// tests are better decoupled from onboarding anyway.
///
/// Runs AFTER `OwnerSeedImportLaunchHandler.runIfRequested`, so a
/// `--gaurava-reset-local-data-for-testing` has already cleared the store and marked
/// first-run complete; this lands records on a clean slate. Compiled out of release and
/// a no-op unless a `--gaurava-seed-*` argument is present.
enum TestStateSeedLaunchHandler {
    private static let profileArg = "--gaurava-seed-profile"
    private static let statusArg = "--gaurava-seed-status"
    private static let startingArg = "--gaurava-seed-starting"
    private static let goalArg = "--gaurava-seed-goal"
    private static let currentArg = "--gaurava-seed-current"
    private static let injectionDayArg = "--gaurava-seed-injection-day"

    @MainActor
    static func seedIfRequested(
        context: ModelContext,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        let seedArgs = [profileArg, statusArg, startingArg, goalArg, currentArg, injectionDayArg]
        guard arguments.contains(where: seedArgs.contains) else { return }

        // The reset handler already set this; set it defensively so the gate still
        // lands in the tab shell even if a test seeds without the reset arg.
        UserDefaults.standard.set(true, forKey: FirstRunFlag.key)

        func value(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: name), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        func number(_ name: String) -> Double? { value(name).flatMap(Double.init) }

        if arguments.contains(profileArg) {
            let profile = TrackerProfile()
            if let starting = number(startingArg) { profile.startingWeightKg = starting }
            if let goal = number(goalArg) { profile.goalWeightKg = goal }
            if let dayString = value(injectionDayArg), let day = Int(dayString) {
                profile.preferredInjectionDay = day
                profile.scheduleAnchorState = .plannedWeekday
            }
            profile.treatmentStatus = treatmentStatus(value(statusArg)) ?? .startingNow
            profile.updatedAt = Date()
            context.insert(profile)
        }

        if let current = number(currentArg) {
            context.insert(WeightEntry(
                weightKg: current,
                recordedAt: Date(),
                timeZoneIdentifier: TimeZone.current.identifier,
                clientMutationId: "test-seed-current-weight"
            ))
        }

        _ = ModelWriteService.save(context)
    }

    private static func treatmentStatus(_ token: String?) -> TreatmentStatus? {
        switch token {
        case "startingNow": return .startingNow
        case "active": return .active
        case "paused": return .paused
        case "unknown": return .unknown
        default: return nil
        }
    }
}
#endif
