import Foundation
import OSLog
import SwiftData

// Single choke point for persisting SwiftData changes.
//
// Every model write in the app flows through here instead of calling
// `modelContext.save()` directly. This gives the glance-surface snapshot a
// single place to republish after a successful write (added in Build 1) and
// stops write errors from being silently swallowed by `try?`.
//
// Two entry points, same seam:
//   - save(_:)        fire-and-forget UI saves; logs failures, never throws.
//   - saveOrThrow(_:) flows that must surface the error to the caller
//                     (reset, seed import).
//
// See docs/widget-options-deep-dive.html (Build 0 / Build 1).
enum ModelWriteService {
    private static let logger = Logger(subsystem: CloudKitConfiguration.containerIdentifier, category: "persistence")

    /// Republish hook, installed once at app launch (GauravaApp). Kept as an
    /// injected closure so the Persistence layer stays free of WidgetKit and so
    /// unit tests (where it is nil) are unaffected. nonisolated(unsafe) is safe
    /// here: it is set once on the main thread before any write occurs.
    nonisolated(unsafe) static var afterSave: ((ModelContext) -> Void)?

    /// Persist pending changes. Logs and returns false on failure; never throws.
    @discardableResult
    static func save(_ context: ModelContext) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            afterSave?(context)
            return true
        } catch {
            logger.error("Model save failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Persist pending changes, propagating any error to the caller.
    static func saveOrThrow(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        try context.save()
        afterSave?(context)
    }
}
