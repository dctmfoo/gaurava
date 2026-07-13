import Foundation
import SwiftData

enum OwnerSeedImportLaunchHandler {
    private static let importArgument = "--gaurava-owner-seed-import"
    private static let resetArgument = "--gaurava-reset-local-data-for-testing"
    private static let appearanceArgument = "--gaurava-appearance"
    /// Opt-in for UI tests that want the first-run gate after a reset. Without
    /// it, a reset lands in the tab shell so the rest of the suite is unaffected.
    /// `FirstRunSetupView` uses `--gaurava-show-first-run-welcome` when a test
    /// needs the production welcome step; otherwise this opens the setup anchors.
    private static let showFirstRunArgument = "--gaurava-show-first-run"
    private static let seedDataEnvironmentKey = "GAURAVA_OWNER_SEED_JSON_B64"

    @MainActor
    static func runIfRequested(context: ModelContext) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(importArgument) || arguments.contains(resetArgument) || arguments.contains(appearanceArgument) else {
            return
        }

        do {
            if arguments.contains(resetArgument) {
                try deleteLocalData(context: context)
                // Default to the tab shell after a reset so the existing UI suite
                // keeps landing there; an onboarding test opts in explicitly.
                let showFirstRun = arguments.contains(showFirstRunArgument)
                UserDefaults.standard.set(!showFirstRun, forKey: FirstRunFlag.key)
            }

            if arguments.contains(importArgument) {
                let data = try seedData(arguments: arguments)
                let summary = try SeedImporter(context: context).importSeed(data: data)
                // The owner now has data; never show them the first-run screen.
                UserDefaults.standard.set(true, forKey: FirstRunFlag.key)
                NSLog("Gaurava owner seed import completed: %@", summary.countsJSON)
            }

            try applyAppearanceOverrideIfRequested(context: context, arguments: arguments)
            try ModelWriteService.saveOrThrow(context)
        } catch {
            NSLog("Gaurava owner seed import failed: %@", String(describing: error))
        }
    }

    @MainActor
    private static func applyAppearanceOverrideIfRequested(context: ModelContext, arguments: [String]) throws {
        guard let argumentIndex = arguments.firstIndex(of: appearanceArgument),
              arguments.indices.contains(argumentIndex + 1)
        else { return }

        let theme = arguments[argumentIndex + 1].lowercased()
        guard ["system", "light", "dark"].contains(theme) else { return }

        let existing = try context.fetch(FetchDescriptor<UserPreference>())
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
        let preference: UserPreference
        if let existing {
            preference = existing
        } else {
            let created = UserPreference()
            context.insert(created)
            preference = created
        }
        preference.theme = theme
        preference.updatedAt = Date()
    }

    private static func seedData(arguments: [String]) throws -> Data {
        if let encoded = ProcessInfo.processInfo.environment[seedDataEnvironmentKey],
           let data = Data(base64Encoded: encoded) {
            return data
        }

        guard let argumentIndex = arguments.firstIndex(of: importArgument),
              arguments.indices.contains(argumentIndex + 1)
        else {
            throw OwnerSeedImportError.missingSeedPath
        }

        return try Data(contentsOf: URL(fileURLWithPath: arguments[argumentIndex + 1]))
    }

    @MainActor
    private static func deleteLocalData(context: ModelContext) throws {
        // Must clear EVERY model in `gauravaModelTypes`, or a leftover row keeps
        // the reset from being hermetic. The Log-v1 capture models
        // (SideEffectEntry / DailyCheckIn) were previously missed; because they
        // feed `DashboardSnapshot.hasLogData`, a stale capture left `hasAnyData`
        // true and suppressed the first-run screen for later onboarding tests.
        try deleteAll(SeedImportReceipt.self, context: context)
        try deleteAll(DailyLogEntry.self, context: context)
        try deleteAll(DailyLog.self, context: context)
        try deleteAll(SideEffectEntry.self, context: context)
        try deleteAll(DailyCheckIn.self, context: context)
        try deleteAll(TreatmentPause.self, context: context)
        try deleteAll(InjectionEntry.self, context: context)
        try deleteAll(WeightEntry.self, context: context)
        try deleteAll(UserPreference.self, context: context)
        try deleteAll(TrackerProfile.self, context: context)
        try ModelWriteService.saveOrThrow(context)
    }

    @MainActor
    private static func deleteAll<Model: PersistentModel>(_ modelType: Model.Type, context: ModelContext) throws {
        let models = try context.fetch(FetchDescriptor<Model>())
        models.forEach(context.delete)
    }
}

enum OwnerImportGate {
    private static let uiArgument = "--gaurava-owner-import-ui"
    private static let uiEnvironmentKey = "GAURAVA_OWNER_IMPORT_UI"

    static func isUserInterfaceEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains(uiArgument) || environment[uiEnvironmentKey].isTruthy
    }
}

enum OwnerSeedImportError: Error {
    case missingSeedPath
}

private extension Optional where Wrapped == String {
    var isTruthy: Bool {
        switch self?.lowercased() {
        case "1", "true", "yes", "on":
            true
        default:
            false
        }
    }
}
