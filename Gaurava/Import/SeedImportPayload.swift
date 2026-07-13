import Foundation

struct SeedImportEnvelope: Decodable {
    var meta: SeedImportMeta
    var account: SeedAccount?
    var data: SeedImportData
}

struct SeedImportMeta: Decodable {
    var sourceProduct: String?
    var targetProduct: String?
    var subjectEmail: String
    var exportedAt: String?
    var version: String
    var sha256: String?
}

struct SeedAccount: Decodable {
    var id: String?
    var email: String?
}

struct SeedImportData: Decodable {
    var profiles: [SeedProfile] = []
    var userPreferences: [SeedPreference] = []
    var weightEntries: [SeedWeightEntry] = []
    var injections: [SeedInjection] = []
    var treatmentPauses: [SeedTreatmentPause] = []
    var dailyLogs: [SeedDailyLog] = []
    var dailyLogEntries: [SeedDailyLogEntry] = []
    var sideEffects: [SeedSideEffect] = []
    var checkIns: [SeedCheckIn] = []

    enum CodingKeys: String, CodingKey {
        case profiles
        case userPreferences
        case weightEntries
        case injections
        case treatmentPauses
        case dailyLogs
        case dailyLogEntries
        case sideEffects
        case checkIns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decodeIfPresent([SeedProfile].self, forKey: .profiles) ?? []
        userPreferences = try container.decodeIfPresent([SeedPreference].self, forKey: .userPreferences) ?? []
        weightEntries = try container.decodeIfPresent([SeedWeightEntry].self, forKey: .weightEntries) ?? []
        injections = try container.decodeIfPresent([SeedInjection].self, forKey: .injections) ?? []
        treatmentPauses = try container.decodeIfPresent([SeedTreatmentPause].self, forKey: .treatmentPauses) ?? []
        dailyLogs = try container.decodeIfPresent([SeedDailyLog].self, forKey: .dailyLogs) ?? []
        dailyLogEntries = try container.decodeIfPresent([SeedDailyLogEntry].self, forKey: .dailyLogEntries) ?? []
        sideEffects = try container.decodeIfPresent([SeedSideEffect].self, forKey: .sideEffects) ?? []
        checkIns = try container.decodeIfPresent([SeedCheckIn].self, forKey: .checkIns) ?? []
    }
}

struct SeedProfile: Decodable {
    var id: String
    var userId: String?
    var age: Int?
    var gender: String?
    var heightCm: String?
    var startingWeightKg: String?
    var goalWeightKg: String?
    var treatmentStartDate: String?
    var medication: String?
    var plannedDoseMg: String?
    var plannedDoseUpdatedAt: String?
    var preferredInjectionDay: Int?
    var reminderDaysBefore: Int?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case age
        case gender
        case heightCm = "height_cm"
        case startingWeightKg = "starting_weight_kg"
        case goalWeightKg = "goal_weight_kg"
        case treatmentStartDate = "treatment_start_date"
        case medication
        case plannedDoseMg = "planned_dose_mg"
        case plannedDoseUpdatedAt = "planned_dose_updated_at"
        case preferredInjectionDay = "preferred_injection_day"
        case reminderDaysBefore = "reminder_days_before"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SeedPreference: Decodable {
    var id: String
    var userId: String?
    var weightUnit: String?
    var heightUnit: String?
    var dateFormat: String?
    var weekStartsOn: Int?
    var theme: String?
    var preferredInjectionSites: [String]?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weightUnit = "weight_unit"
        case heightUnit = "height_unit"
        case dateFormat = "date_format"
        case weekStartsOn = "week_starts_on"
        case theme
        case preferredInjectionSites = "preferred_injection_sites"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SeedWeightEntry: Decodable {
    var id: String
    var userId: String?
    var weightKg: String?
    var recordedAt: String?
    var timeZoneIdentifier: String?
    var notes: String?
    var clientMutationId: String?
    var sourceDailyLogEntryId: String?
    var sourceChatMessageId: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weightKg = "weight_kg"
        case recordedAt = "recorded_at"
        case timeZoneIdentifier = "time_zone_identifier"
        case notes
        case clientMutationId = "client_mutation_id"
        case sourceDailyLogEntryId = "source_daily_log_entry_id"
        case sourceChatMessageId = "source_chat_message_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SeedInjection: Decodable {
    var id: String
    var userId: String?
    var doseMg: String?
    var injectionSite: String?
    var injectionDate: String?
    var timeZoneIdentifier: String?
    var batchNumber: String?
    var notes: String?
    var clientMutationId: String?
    var sourceChatMessageId: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case doseMg = "dose_mg"
        case injectionSite = "injection_site"
        case injectionDate = "injection_date"
        case timeZoneIdentifier = "time_zone_identifier"
        case batchNumber = "batch_number"
        case notes
        case clientMutationId = "client_mutation_id"
        case sourceChatMessageId = "source_chat_message_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SeedTreatmentPause: Decodable {
    var id: String
    var userId: String?
    var startedAt: String?
    var endedAt: String?
    var reason: String?
    var resumedOnDate: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case reason
        case resumedOnDate = "resumed_on_date"
        case createdAt = "created_at"
    }
}

struct SeedDailyLog: Decodable {
    var id: String
    var userId: String?
    var logDate: String?
    var sideEffectsJSON: String?
    var activityJSON: String?
    var mentalJSON: String?
    var dietJSON: String?
    var notes: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case logDate = "log_date"
        case sideEffectsJSON = "side_effects_json"
        case activityJSON = "activity_json"
        case mentalJSON = "mental_json"
        case dietJSON = "diet_json"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SeedDailyLogEntry: Decodable {
    var id: String
    var userId: String?
    var logDate: String?
    var recordedAt: String?
    var timeZoneIdentifier: String?
    var source: String?
    var rawText: String?
    var entryText: String?
    var aiDraft: JSONValue?
    var parsedDraftJSON: String?
    var deletedAt: String?
    var sourceDailyLogId: String?
    var clientMutationId: String?
    var sourceChatMessageId: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case logDate = "log_date"
        case recordedAt = "recorded_at"
        case timeZoneIdentifier = "time_zone_identifier"
        case source
        case rawText = "raw_text"
        case entryText = "entry_text"
        case aiDraft = "ai_draft"
        case parsedDraftJSON = "parsed_draft_json"
        case deletedAt = "deleted_at"
        case sourceDailyLogId = "source_daily_log_id"
        case clientMutationId = "client_mutation_id"
        case sourceChatMessageId = "source_chat_message_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// Structured Log-tab capture (v1). These models carry no `legacyServerId`; the
// importer dedupes by `clientMutationId` so re-importing the same seed is
// idempotent. Optional throughout for forward/backward compatibility.
struct SeedSideEffect: Decodable {
    var id: String?
    var logDate: String?
    var symptom: String?
    var severity: String?
    var source: String?
    var timeZoneIdentifier: String?
    var clientMutationId: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case logDate = "log_date"
        case symptom
        case severity
        case source
        case timeZoneIdentifier = "time_zone_identifier"
        case clientMutationId = "client_mutation_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SeedCheckIn: Decodable {
    var id: String?
    var logDate: String?
    var moodValence: String?
    var allClear: Bool?
    var note: String?
    var source: String?
    var timeZoneIdentifier: String?
    var clientMutationId: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case logDate = "log_date"
        case moodValence = "mood_valence"
        case allClear = "all_clear"
        case note
        case source
        case timeZoneIdentifier = "time_zone_identifier"
        case clientMutationId = "client_mutation_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum JSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var jsonString: String? {
        guard let object = foundationValue,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private var foundationValue: Any? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.compactMapValues(\.foundationValue)
        case .array(let value):
            return value.compactMap(\.foundationValue)
        case .null:
            return NSNull()
        }
    }
}

struct SeedImportSummary: Codable, Equatable {
    var profiles: Int
    var preferences: Int
    var weightEntries: Int
    var injections: Int
    var treatmentPauses: Int
    var dailyLogs: Int
    var dailyLogEntries: Int

    init(
        profiles: Int,
        preferences: Int,
        weightEntries: Int,
        injections: Int,
        treatmentPauses: Int,
        dailyLogs: Int,
        dailyLogEntries: Int
    ) {
        self.profiles = profiles
        self.preferences = preferences
        self.weightEntries = weightEntries
        self.injections = injections
        self.treatmentPauses = treatmentPauses
        self.dailyLogs = dailyLogs
        self.dailyLogEntries = dailyLogEntries
    }

    init(data: SeedImportData) {
        self.init(
            profiles: data.profiles.count,
            preferences: data.userPreferences.count,
            weightEntries: data.weightEntries.count,
            injections: data.injections.count,
            treatmentPauses: data.treatmentPauses.count,
            dailyLogs: data.dailyLogs.count,
            dailyLogEntries: data.dailyLogEntries.count
        )
    }

    var totalRecords: Int {
        profiles + preferences + weightEntries + injections + treatmentPauses + dailyLogs + dailyLogEntries
    }

    var displayText: String {
        [
            "\(profiles) profile",
            "\(preferences) preference",
            "\(weightEntries) weights",
            "\(injections) jabs",
            "\(treatmentPauses) pauses",
            "\(dailyLogs) daily logs",
            "\(dailyLogEntries) log entries"
        ].joined(separator: ", ")
    }

    var countsJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
