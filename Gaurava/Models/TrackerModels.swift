import Foundation
import SwiftData

enum CloudKitConfiguration {
    #if GAURAVA_ONBOARDING_SANDBOX
    static let isEnabled = false
    static let containerIdentifier = "local-only-onboarding-sandbox"
    #else
    static let isEnabled = true
    static let containerIdentifier = "iCloud.com.nags.gaurava"
    #endif
}

@Model
final class TrackerProfile {
    var id: UUID = UUID()
    var legacyServerId: String?
    var sourceUserId: String?
    var age: Int = 0
    var gender: String = ""
    var heightCm: Double = 0
    var startingWeightKg: Double = 0
    var goalWeightKg: Double = 0
    var treatmentStartDate: Date = Date()
    var plannedDoseMg: Double?
    var medicationRaw: String?
    var plannedDoseUpdatedAt: Date?
    var preferredInjectionDay: Int?
    var reminderDaysBefore: Int = 1
    // Phase 0 treatment contract (onboarding honesty). All CloudKit-safe:
    // optional or defaulted, no uniqueness constraint. A nil raw status/anchor
    // reads as `.unknown`, so existing records migrate by safe default and are
    // never reset. See docs/onboarding-issues-and-fixes.html "Phase 0 Data Contract".
    var treatmentStatusRaw: String?
    var scheduleAnchorStateRaw: String?
    /// True only when the user actually confirmed a treatment-start date (or seed
    /// data supplied a real one). The nonoptional `treatmentStartDate` default must
    /// not be read as user-provided history when this is false.
    var treatmentStartProvided: Bool = false
    /// The most recent CONFIRMED dose that anchors the schedule, set from an
    /// onboarding "last injection" date without necessarily fabricating an
    /// InjectionEntry. A logged injection still wins when more recent.
    var scheduleAnchorDate: Date?
    var scheduleAnchorDoseMg: Double?
    var scheduleAnchorSite: String?
    var scheduleAnchorUpdatedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        legacyServerId: String? = nil,
        sourceUserId: String? = nil,
        age: Int = 0,
        gender: String = "",
        heightCm: Double = 0,
        startingWeightKg: Double = 0,
        goalWeightKg: Double = 0,
        treatmentStartDate: Date = Date(),
        plannedDoseMg: Double? = nil,
        medicationRaw: String? = nil,
        plannedDoseUpdatedAt: Date? = nil,
        preferredInjectionDay: Int? = nil,
        reminderDaysBefore: Int = 1,
        treatmentStatusRaw: String? = nil,
        scheduleAnchorStateRaw: String? = nil,
        treatmentStartProvided: Bool = false,
        scheduleAnchorDate: Date? = nil,
        scheduleAnchorDoseMg: Double? = nil,
        scheduleAnchorSite: String? = nil,
        scheduleAnchorUpdatedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.legacyServerId = legacyServerId
        self.sourceUserId = sourceUserId
        self.age = age
        self.gender = gender
        self.heightCm = heightCm
        self.startingWeightKg = startingWeightKg
        self.goalWeightKg = goalWeightKg
        self.treatmentStartDate = treatmentStartDate
        self.plannedDoseMg = plannedDoseMg
        self.medicationRaw = medicationRaw
        self.plannedDoseUpdatedAt = plannedDoseUpdatedAt
        self.preferredInjectionDay = preferredInjectionDay
        self.reminderDaysBefore = reminderDaysBefore
        self.treatmentStatusRaw = treatmentStatusRaw
        self.scheduleAnchorStateRaw = scheduleAnchorStateRaw
        self.treatmentStartProvided = treatmentStartProvided
        self.scheduleAnchorDate = scheduleAnchorDate
        self.scheduleAnchorDoseMg = scheduleAnchorDoseMg
        self.scheduleAnchorSite = scheduleAnchorSite
        self.scheduleAnchorUpdatedAt = scheduleAnchorUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Display-safe medication: nil when the user never told us, so no surface can
    /// present the computed tirzepatide default as fact. Use `medication` only for
    /// form editing defaults.
    var medicationIfKnown: Medication? {
        medicationRaw.flatMap(Medication.init(rawValue:))
    }

    /// Durable treatment status. Nil raw reads as `.unknown`; setting `.unknown`
    /// clears the raw value so it stays the natural CloudKit default.
    var treatmentStatus: TreatmentStatus {
        get { treatmentStatusRaw.flatMap(TreatmentStatus.init(rawValue:)) ?? .unknown }
        set { treatmentStatusRaw = newValue == .unknown ? nil : newValue.rawValue }
    }

    var scheduleAnchorState: ScheduleAnchorState {
        get { scheduleAnchorStateRaw.flatMap(ScheduleAnchorState.init(rawValue:)) ?? .unknown }
        set { scheduleAnchorStateRaw = newValue == .unknown ? nil : newValue.rawValue }
    }

    /// Editing default for medication forms (never a display claim). Preserves the
    /// historical default: unknown → tirzepatide. For honest display, read
    /// `medicationIfKnown` (nil when the user never told us).
    var medication: Medication {
        get { medicationIfKnown ?? .tirzepatide }
        set { medicationRaw = newValue.rawValue }
    }

    func applyMedication(_ medication: Medication, now: Date = Date()) {
        self.medication = medication
        if let plannedDoseMg,
           !medication.dosePresets.contains(where: { abs($0 - plannedDoseMg) < 0.001 }) {
            self.plannedDoseMg = nil
            plannedDoseUpdatedAt = now
        }
        updatedAt = now
    }
}

@Model
final class UserPreference {
    var id: UUID = UUID()
    var legacyServerId: String?
    var sourceUserId: String?
    var weightUnit: String = "kg"
    var heightUnit: String = "cm"
    var dateFormat: String = "DD/MM/YYYY"
    var weekStartsOn: Int = 1
    var theme: String = "system"
    var preferredInjectionSitesJSON: String = "[]"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        legacyServerId: String? = nil,
        sourceUserId: String? = nil,
        weightUnit: String = "kg",
        heightUnit: String = "cm",
        dateFormat: String = "DD/MM/YYYY",
        weekStartsOn: Int = 1,
        theme: String = "system",
        preferredInjectionSitesJSON: String = "[]",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.legacyServerId = legacyServerId
        self.sourceUserId = sourceUserId
        self.weightUnit = weightUnit
        self.heightUnit = heightUnit
        self.dateFormat = dateFormat
        self.weekStartsOn = weekStartsOn
        self.theme = theme
        self.preferredInjectionSitesJSON = preferredInjectionSitesJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var legacyServerId: String?
    var sourceUserId: String?
    var weightKg: Double = 0
    var recordedAt: Date = Date()
    var timeZoneIdentifier: String?
    var notes: String?
    var clientMutationId: String?
    var sourceDailyLogEntryId: String?
    var sourceChatMessageId: String?
    /// Stable UUID of the originating Apple Health `HKSample` when this entry was
    /// imported from HealthKit; nil for hand-typed or seeded entries. The
    /// HealthKit weight importer dedups on this so an existing reading is never
    /// imported twice. CloudKit-safe: optional, no uniqueness constraint, so the
    /// field also rides the CloudKit mirror to keep cross-device dedup honest.
    var sourceHealthKitUUID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        legacyServerId: String? = nil,
        sourceUserId: String? = nil,
        weightKg: Double = 0,
        recordedAt: Date = Date(),
        timeZoneIdentifier: String? = nil,
        notes: String? = nil,
        clientMutationId: String? = nil,
        sourceDailyLogEntryId: String? = nil,
        sourceChatMessageId: String? = nil,
        sourceHealthKitUUID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.legacyServerId = legacyServerId
        self.sourceUserId = sourceUserId
        self.weightKg = weightKg
        self.recordedAt = recordedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.notes = notes
        self.clientMutationId = clientMutationId
        self.sourceDailyLogEntryId = sourceDailyLogEntryId
        self.sourceChatMessageId = sourceChatMessageId
        self.sourceHealthKitUUID = sourceHealthKitUUID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class InjectionEntry {
    var id: UUID = UUID()
    var legacyServerId: String?
    var sourceUserId: String?
    var doseMg: Double = 0
    var injectionSite: String = ""
    var injectionDate: Date = Date()
    var timeZoneIdentifier: String?
    var batchNumber: String?
    var notes: String?
    var clientMutationId: String?
    var sourceChatMessageId: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        legacyServerId: String? = nil,
        sourceUserId: String? = nil,
        doseMg: Double = 0,
        injectionSite: String = "",
        injectionDate: Date = Date(),
        timeZoneIdentifier: String? = nil,
        batchNumber: String? = nil,
        notes: String? = nil,
        clientMutationId: String? = nil,
        sourceChatMessageId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.legacyServerId = legacyServerId
        self.sourceUserId = sourceUserId
        self.doseMg = doseMg
        self.injectionSite = injectionSite
        self.injectionDate = injectionDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.batchNumber = batchNumber
        self.notes = notes
        self.clientMutationId = clientMutationId
        self.sourceChatMessageId = sourceChatMessageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TreatmentPause {
    var id: UUID = UUID()
    var legacyServerId: String?
    var sourceUserId: String?
    var startedAt: Date = Date()
    var endedAt: Date?
    var reason: String?
    var resumedOnDate: Date?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        legacyServerId: String? = nil,
        sourceUserId: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        reason: String? = nil,
        resumedOnDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.legacyServerId = legacyServerId
        self.sourceUserId = sourceUserId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.reason = reason
        self.resumedOnDate = resumedOnDate
        self.createdAt = createdAt
    }
}

@Model
final class DailyLog {
    var id: UUID = UUID()
    var legacyServerId: String?
    var sourceUserId: String?
    var logDate: Date = Date()
    var sideEffectsJSON: String?
    var activityJSON: String?
    var mentalJSON: String?
    var dietJSON: String?
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        legacyServerId: String? = nil,
        sourceUserId: String? = nil,
        logDate: Date = Date(),
        sideEffectsJSON: String? = nil,
        activityJSON: String? = nil,
        mentalJSON: String? = nil,
        dietJSON: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.legacyServerId = legacyServerId
        self.sourceUserId = sourceUserId
        self.logDate = logDate
        self.sideEffectsJSON = sideEffectsJSON
        self.activityJSON = activityJSON
        self.mentalJSON = mentalJSON
        self.dietJSON = dietJSON
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class DailyLogEntry {
    var id: UUID = UUID()
    var legacyServerId: String?
    var sourceUserId: String?
    var logDate: Date = Date()
    var recordedAt: Date?
    var timeZoneIdentifier: String?
    var source: String = "typed"
    var entryText: String = ""
    var parsedDraftJSON: String?
    var deletedAt: Date?
    var sourceDailyLogId: String?
    var sourceChatMessageId: String?
    var clientMutationId: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        legacyServerId: String? = nil,
        sourceUserId: String? = nil,
        logDate: Date = Date(),
        recordedAt: Date? = nil,
        timeZoneIdentifier: String? = nil,
        source: String = "typed",
        entryText: String = "",
        parsedDraftJSON: String? = nil,
        deletedAt: Date? = nil,
        sourceDailyLogId: String? = nil,
        sourceChatMessageId: String? = nil,
        clientMutationId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.legacyServerId = legacyServerId
        self.sourceUserId = sourceUserId
        self.logDate = logDate
        self.recordedAt = recordedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.source = source
        self.entryText = entryText
        self.parsedDraftJSON = parsedDraftJSON
        self.deletedAt = deletedAt
        self.sourceDailyLogId = sourceDailyLogId
        self.sourceChatMessageId = sourceChatMessageId
        self.clientMutationId = clientMutationId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SeedImportReceipt {
    var id: UUID = UUID()
    var sourceEmail: String = ""
    var importedAt: Date = Date()
    var sourceExportVersion: String = ""
    var countsJSON: String = "{}"
    var checksum: String = ""
    var status: String = "pending"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        sourceEmail: String = "",
        importedAt: Date = Date(),
        sourceExportVersion: String = "",
        countsJSON: String = "{}",
        checksum: String = "",
        status: String = "pending",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceEmail = sourceEmail
        self.importedAt = importedAt
        self.sourceExportVersion = sourceExportVersion
        self.countsJSON = countsJSON
        self.checksum = checksum
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// Structured side-effect capture (Log tab v1). One row per (symptom, logDate):
// a tap notes the symptom for the day; an optional severity refines it. Writes
// upsert by (symptom, logDate) via `LogCapture` so an accidental double-tap can
// never double-count. CloudKit-safe: every field has a default or is optional,
// no uniqueness constraint, no required relationship.
@Model
final class SideEffectEntry {
    var id: UUID = UUID()
    /// Start-of-day in the user's calendar — the upsert key alongside `symptom`.
    var logDate: Date = Date()
    /// Canonical key: see `SideEffectKind` ("nausea" | "vomiting" | "constipation" | "diarrhea").
    var symptom: String = ""
    /// nil | "mild" | "moderate" | "severe" — optional, never pre-filled.
    var severity: String?
    /// "app" (in-app capture) | "system" (Lock Screen / control deep link).
    var source: String = "app"
    var timeZoneIdentifier: String?
    var clientMutationId: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        logDate: Date = Date(),
        symptom: String = "",
        severity: String? = nil,
        source: String = "app",
        timeZoneIdentifier: String? = nil,
        clientMutationId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.logDate = logDate
        self.symptom = symptom
        self.severity = severity
        self.source = source
        self.timeZoneIdentifier = timeZoneIdentifier
        self.clientMutationId = clientMutationId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// Per-day check-in (Log tab v1): the one-tap mood valence, the explicit
// "nothing today" all-clear flag (distinct from "untracked"), and the freeform
// note escape hatch. One row per day, upserted by `logDate` via `LogCapture`.
// CloudKit-safe like the rest of the schema.
@Model
final class DailyCheckIn {
    var id: UUID = UUID()
    /// Start-of-day in the user's calendar — the upsert key.
    var logDate: Date = Date()
    /// nil | "rough" | "low" | "okay" | "good" | "great" (see `MoodValence`).
    var moodValence: String?
    /// True when the user explicitly recorded "nothing today" — tracked-absent,
    /// which is clinically distinct from no record at all.
    var allClear: Bool = false
    /// The freeform "+ note" escape hatch.
    var note: String?
    var source: String = "app"
    var timeZoneIdentifier: String?
    var clientMutationId: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        logDate: Date = Date(),
        moodValence: String? = nil,
        allClear: Bool = false,
        note: String? = nil,
        source: String = "app",
        timeZoneIdentifier: String? = nil,
        clientMutationId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.logDate = logDate
        self.moodValence = moodValence
        self.allClear = allClear
        self.note = note
        self.source = source
        self.timeZoneIdentifier = timeZoneIdentifier
        self.clientMutationId = clientMutationId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// InjectionSiteRotation moved to InjectionSiteRotation.swift (Foundation-only)
// so it can be shared with the import-clean glance-surface projection.

extension UserPreference {
    var preferredInjectionSites: [String] {
        get {
            InjectionSiteRotation.preferredSites(from: preferredInjectionSitesJSON)
        }
        set {
            preferredInjectionSitesJSON = InjectionSiteRotation.encodedPreferredSites(newValue)
        }
    }
}

let gauravaModelTypes: [any PersistentModel.Type] = [
    TrackerProfile.self,
    UserPreference.self,
    WeightEntry.self,
    InjectionEntry.self,
    TreatmentPause.self,
    DailyLog.self,
    DailyLogEntry.self,
    SideEffectEntry.self,
    DailyCheckIn.self,
    SeedImportReceipt.self
]
