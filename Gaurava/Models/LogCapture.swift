import Foundation
import SwiftData

// Canonical vocabularies + the write path for Log-tab capture (v1).
//
// The enums are the single source of truth for the four curated side effects,
// the optional three-tier severity, and the five-point mood valence. The
// `LogCapture` store performs every write as an UPSERT keyed by day (and, for
// symptoms, by symptom) so an accidental double-tap can never create a second
// row — the idempotency the design treats as load-bearing. Every mutator routes
// through `ModelWriteService.save`, which republishes the glance/Live-Activity
// surfaces, so a capture made anywhere reaches every surface from one write.

/// The four curated GLP-1 side effects that gate dose decisions.
enum SideEffectKind: String, CaseIterable, Identifiable, Sendable {
    case nausea, vomiting, constipation, diarrhea

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nausea: return appLocalizedResource(.sideEffectNauseaLabel)
        case .vomiting: return appLocalizedResource(.sideEffectVomitingLabel)
        case .constipation: return appLocalizedResource(.sideEffectConstipationLabel)
        case .diarrhea: return appLocalizedResource(.sideEffectDiarrheaLabel)
        }
    }
}

/// Optional severity — never required, never pre-filled.
enum SeverityLevel: String, CaseIterable, Identifiable, Sendable {
    case mild, moderate, severe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mild: return appLocalizedResource(.severityMildLabel)
        case .moderate: return appLocalizedResource(.severityModerateLabel)
        case .severe: return appLocalizedResource(.severitySevereLabel)
        }
    }

    /// Compact label for chips ("Mild" / "Mod" / "Severe").
    var short: String {
        self == .moderate ? appLocalizedResource(.severityModerateShortLabel) : label
    }

    /// Cycle order for legacy callers: nil → mild → moderate → severe → nil.
    static func next(after current: SeverityLevel?) -> SeverityLevel? {
        switch current {
        case .none: return .mild
        case .mild: return .moderate
        case .moderate: return .severe
        case .severe: return nil
        }
    }
}

/// One-tap sense of the day. A five-point valence (the State of Mind idiom),
/// neutral wording, no numbers. `fillFraction` drives the abstract dial.
enum MoodValence: String, CaseIterable, Identifiable, Sendable {
    case rough, low, okay, good, great

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rough: return appLocalizedResource(.moodRoughLabel)
        case .low: return appLocalizedResource(.moodLowLabel)
        case .okay: return appLocalizedResource(.moodOkayLabel)
        case .good: return appLocalizedResource(.moodGoodLabel)
        case .great: return appLocalizedResource(.moodGreatLabel)
        }
    }

    /// 0...1 fill for the monochrome valence dial.
    var fillFraction: Double {
        switch self {
        case .rough: return 0.14
        case .low: return 0.32
        case .okay: return 0.52
        case .good: return 0.74
        case .great: return 0.96
        }
    }
}

/// The upsert write path. Pure with respect to time/calendar (both injectable)
/// so it is unit-testable; every mutator persists through `ModelWriteService`.
enum LogCapture {
    // MARK: Reads

    static func sideEffects(
        on day: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> [SideEffectEntry] {
        let target = calendar.startOfDay(for: day)
        let all = (try? context.fetch(FetchDescriptor<SideEffectEntry>())) ?? []
        return all.filter { calendar.isDate($0.logDate, inSameDayAs: target) }
    }

    static func sideEffect(
        _ symptom: SideEffectKind,
        on day: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> SideEffectEntry? {
        sideEffects(on: day, in: context, calendar: calendar).first { $0.symptom == symptom.rawValue }
    }

    static func checkIn(
        on day: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> DailyCheckIn? {
        let target = calendar.startOfDay(for: day)
        let all = (try? context.fetch(FetchDescriptor<DailyCheckIn>())) ?? []
        return all.first { calendar.isDate($0.logDate, inSameDayAs: target) }
    }

    // MARK: Side-effect writes

    /// Toggle a symptom for the day. Returns the new on/off state. Noting any
    /// symptom clears the day's "all clear" flag (they are mutually exclusive).
    @discardableResult
    static func toggleSideEffect(
        _ symptom: SideEffectKind,
        on day: Date,
        source: String = "app",
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let target = calendar.startOfDay(for: day)
        if let existing = sideEffect(symptom, on: target, in: context, calendar: calendar) {
            context.delete(existing)
            ModelWriteService.save(context)
            return false
        }
        let entry = SideEffectEntry(
            logDate: target,
            symptom: symptom.rawValue,
            source: source,
            timeZoneIdentifier: TimeZone.current.identifier,
            clientMutationId: mutationId(symptom.rawValue, target),
            createdAt: now,
            updatedAt: now
        )
        context.insert(entry)
        clearAllClear(on: target, in: context, now: now, calendar: calendar)
        ModelWriteService.save(context)
        return true
    }

    /// Legacy severity cycle: nil → mild → moderate → severe → nil. No-op if the
    /// symptom is not currently noted.
    static func cycleSeverity(
        for symptom: SideEffectKind,
        on day: Date,
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard let entry = sideEffect(symptom, on: day, in: context, calendar: calendar) else { return }
        entry.severity = SeverityLevel.next(after: entry.severity.flatMap(SeverityLevel.init))?.rawValue
        entry.updatedAt = now
        ModelWriteService.save(context)
    }

    /// Set optional severity directly from the visible severity control. This
    /// preserves the same stored value as `cycleSeverity`, but avoids hidden
    /// gesture dependence in the Log UI.
    static func setSeverity(
        _ severity: SeverityLevel?,
        for symptom: SideEffectKind,
        on day: Date,
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard let entry = sideEffect(symptom, on: day, in: context, calendar: calendar) else { return }
        entry.severity = severity?.rawValue
        entry.updatedAt = now
        ModelWriteService.save(context)
    }

    /// Record a symptom and optional severity in one visible action. This keeps
    /// the data model unchanged while supporting direct severity buttons in the
    /// Log UI.
    static func recordSideEffect(
        _ symptom: SideEffectKind,
        severity: SeverityLevel?,
        on day: Date,
        source: String = "app",
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let target = calendar.startOfDay(for: day)
        let entry: SideEffectEntry
        if let existing = sideEffect(symptom, on: target, in: context, calendar: calendar) {
            entry = existing
        } else {
            entry = SideEffectEntry(
                logDate: target,
                symptom: symptom.rawValue,
                source: source,
                timeZoneIdentifier: TimeZone.current.identifier,
                clientMutationId: mutationId(symptom.rawValue, target),
                createdAt: now,
                updatedAt: now
            )
            context.insert(entry)
            clearAllClear(on: target, in: context, now: now, calendar: calendar)
        }
        entry.severity = severity?.rawValue
        entry.updatedAt = now
        ModelWriteService.save(context)
    }

    // MARK: Day check-in writes

    static func setMood(
        _ mood: MoodValence?,
        on day: Date,
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let checkIn = upsertCheckIn(on: day, in: context, now: now, calendar: calendar)
        checkIn.moodValence = mood?.rawValue
        checkIn.updatedAt = now
        ModelWriteService.save(context)
    }

    /// Record (or clear) "nothing today". Setting it removes any noted symptoms
    /// for the day — "all clear" and "had a symptom" cannot both be true.
    static func setAllClear(
        _ on: Bool,
        day: Date,
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let checkIn = upsertCheckIn(on: day, in: context, now: now, calendar: calendar)
        checkIn.allClear = on
        checkIn.updatedAt = now
        if on {
            for entry in sideEffects(on: day, in: context, calendar: calendar) {
                context.delete(entry)
            }
        }
        ModelWriteService.save(context)
    }

    static func setNote(
        _ text: String?,
        on day: Date,
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkIn = upsertCheckIn(on: day, in: context, now: now, calendar: calendar)
        checkIn.note = (trimmed?.isEmpty == false) ? trimmed : nil
        checkIn.updatedAt = now
        ModelWriteService.save(context)
    }

    static func appendNote(
        _ text: String?,
        on day: Date,
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let incoming = trimmed, !incoming.isEmpty else { return }

        let checkIn = upsertCheckIn(on: day, in: context, now: now, calendar: calendar)
        let existing = checkIn.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing, !existing.isEmpty {
            checkIn.note = noteByPreserving(existing: existing, incoming: incoming)
        } else {
            checkIn.note = incoming
        }
        checkIn.updatedAt = now
        ModelWriteService.save(context)
    }

    // MARK: Helpers

    private static func upsertCheckIn(
        on day: Date,
        in context: ModelContext,
        now: Date,
        calendar: Calendar
    ) -> DailyCheckIn {
        let target = calendar.startOfDay(for: day)
        if let existing = checkIn(on: target, in: context, calendar: calendar) {
            return existing
        }
        let created = DailyCheckIn(
            logDate: target,
            timeZoneIdentifier: TimeZone.current.identifier,
            clientMutationId: mutationId("checkin", target),
            createdAt: now,
            updatedAt: now
        )
        context.insert(created)
        return created
    }

    private static func clearAllClear(
        on day: Date,
        in context: ModelContext,
        now: Date,
        calendar: Calendar
    ) {
        guard let checkIn = checkIn(on: day, in: context, calendar: calendar), checkIn.allClear else { return }
        checkIn.allClear = false
        checkIn.updatedAt = now
    }

    private static func mutationId(_ key: String, _ day: Date) -> String {
        "log-\(key)-\(Int(day.timeIntervalSince1970))"
    }

    private static func noteByPreserving(existing: String, incoming: String) -> String {
        if incoming == existing || incoming.contains(existing) { return incoming }
        return "\(existing)\n\n\(incoming)"
    }
}
