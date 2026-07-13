import CryptoKit
import Foundation
import SwiftData

struct SeedImporter {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func importSeed(data: Data) throws -> SeedImportSummary {
        let envelope = try JSONDecoder().decode(SeedImportEnvelope.self, from: data)
        let summary = SeedImportSummary(data: envelope.data)

        try envelope.data.profiles.forEach(upsertProfile)
        try envelope.data.userPreferences.forEach(upsertPreference)
        try envelope.data.weightEntries.forEach(upsertWeightEntry)
        try envelope.data.injections.forEach(upsertInjection)
        try envelope.data.treatmentPauses.forEach(upsertTreatmentPause)
        try envelope.data.dailyLogs.forEach(upsertDailyLog)
        try envelope.data.dailyLogEntries.forEach(upsertDailyLogEntry)
        try envelope.data.sideEffects.forEach(upsertSideEffect)
        try envelope.data.checkIns.forEach(upsertCheckIn)
        try upsertReceipt(envelope: envelope, summary: summary, sourceData: data)
        try ModelWriteService.saveOrThrow(context)

        return summary
    }

    private func upsertProfile(_ seed: SeedProfile) throws {
        let profile = try existingProfile(legacyServerId: seed.id) ?? TrackerProfile(legacyServerId: seed.id)
        profile.legacyServerId = seed.id
        profile.sourceUserId = seed.userId
        profile.age = seed.age ?? 0
        profile.gender = seed.gender ?? ""
        profile.heightCm = double(seed.heightCm)
        profile.startingWeightKg = double(seed.startingWeightKg)
        profile.goalWeightKg = double(seed.goalWeightKg)
        profile.treatmentStartDate = date(seed.treatmentStartDate) ?? Date()
        // Honor the "unknown stays unknown" contract (TrackerProfile.medicationIfKnown,
        // SampleData line ~290): a seed without a medication field must keep medicationRaw
        // nil so honest surfaces show "unknown", never a synthesized tirzepatide. Assign
        // through medicationRaw — the `medication` setter would coerce nil to tirzepatide.
        profile.medicationRaw = seed.medication.flatMap(Medication.init(rawValue:))?.rawValue
        profile.plannedDoseMg = optionalDouble(seed.plannedDoseMg)
        profile.plannedDoseUpdatedAt = date(seed.plannedDoseUpdatedAt)
        profile.preferredInjectionDay = seed.preferredInjectionDay
        profile.reminderDaysBefore = seed.reminderDaysBefore ?? 1
        profile.createdAt = date(seed.createdAt) ?? profile.createdAt
        profile.updatedAt = date(seed.updatedAt) ?? Date()
        context.insert(profile)
    }

    private func upsertPreference(_ seed: SeedPreference) throws {
        let preference = try existingPreference(legacyServerId: seed.id) ?? UserPreference(legacyServerId: seed.id)
        preference.legacyServerId = seed.id
        preference.sourceUserId = seed.userId
        preference.weightUnit = seed.weightUnit ?? "kg"
        preference.heightUnit = seed.heightUnit ?? "cm"
        preference.dateFormat = seed.dateFormat ?? "DD/MM/YYYY"
        preference.weekStartsOn = seed.weekStartsOn ?? 1
        preference.theme = seed.theme ?? "system"
        if let preferredInjectionSites = seed.preferredInjectionSites {
            preference.preferredInjectionSites = preferredInjectionSites
        }
        preference.createdAt = date(seed.createdAt) ?? preference.createdAt
        preference.updatedAt = date(seed.updatedAt) ?? Date()
        context.insert(preference)
    }

    private func upsertWeightEntry(_ seed: SeedWeightEntry) throws {
        let entry = try existingWeight(legacyServerId: seed.id) ?? WeightEntry(legacyServerId: seed.id)
        entry.legacyServerId = seed.id
        entry.sourceUserId = seed.userId
        entry.weightKg = double(seed.weightKg)
        entry.recordedAt = date(seed.recordedAt) ?? Date()
        entry.timeZoneIdentifier = seed.timeZoneIdentifier
        entry.notes = seed.notes
        entry.clientMutationId = seed.clientMutationId
        entry.sourceDailyLogEntryId = seed.sourceDailyLogEntryId
        entry.sourceChatMessageId = seed.sourceChatMessageId
        entry.createdAt = date(seed.createdAt) ?? entry.createdAt
        entry.updatedAt = date(seed.updatedAt) ?? Date()
        context.insert(entry)
    }

    private func upsertInjection(_ seed: SeedInjection) throws {
        let entry = try existingInjection(legacyServerId: seed.id) ?? InjectionEntry(legacyServerId: seed.id)
        entry.legacyServerId = seed.id
        entry.sourceUserId = seed.userId
        entry.doseMg = double(seed.doseMg)
        entry.injectionSite = seed.injectionSite ?? ""
        entry.injectionDate = date(seed.injectionDate) ?? Date()
        entry.timeZoneIdentifier = seed.timeZoneIdentifier
        entry.batchNumber = seed.batchNumber
        entry.notes = seed.notes
        entry.clientMutationId = seed.clientMutationId
        entry.sourceChatMessageId = seed.sourceChatMessageId
        entry.createdAt = date(seed.createdAt) ?? entry.createdAt
        entry.updatedAt = date(seed.updatedAt) ?? Date()
        context.insert(entry)
    }

    private func upsertTreatmentPause(_ seed: SeedTreatmentPause) throws {
        let pause = try existingTreatmentPause(legacyServerId: seed.id) ?? TreatmentPause(legacyServerId: seed.id)
        pause.legacyServerId = seed.id
        pause.sourceUserId = seed.userId
        pause.startedAt = date(seed.startedAt) ?? Date()
        pause.endedAt = date(seed.endedAt)
        pause.reason = seed.reason
        pause.resumedOnDate = date(seed.resumedOnDate)
        pause.createdAt = date(seed.createdAt) ?? pause.createdAt
        context.insert(pause)
    }

    private func upsertDailyLog(_ seed: SeedDailyLog) throws {
        let log = try existingDailyLog(legacyServerId: seed.id) ?? DailyLog(legacyServerId: seed.id)
        log.legacyServerId = seed.id
        log.sourceUserId = seed.userId
        log.logDate = date(seed.logDate) ?? Date()
        log.sideEffectsJSON = seed.sideEffectsJSON
        log.activityJSON = seed.activityJSON
        log.mentalJSON = seed.mentalJSON
        log.dietJSON = seed.dietJSON
        log.notes = seed.notes
        log.createdAt = date(seed.createdAt) ?? log.createdAt
        log.updatedAt = date(seed.updatedAt) ?? Date()
        context.insert(log)
    }

    private func upsertDailyLogEntry(_ seed: SeedDailyLogEntry) throws {
        let entry = try existingDailyLogEntry(legacyServerId: seed.id) ?? DailyLogEntry(legacyServerId: seed.id)
        entry.legacyServerId = seed.id
        entry.sourceUserId = seed.userId
        entry.logDate = date(seed.logDate) ?? date(seed.recordedAt) ?? Date()
        entry.recordedAt = date(seed.recordedAt)
        entry.timeZoneIdentifier = seed.timeZoneIdentifier
        entry.source = seed.source ?? "typed"
        entry.entryText = seed.rawText ?? seed.entryText ?? ""
        entry.parsedDraftJSON = seed.parsedDraftJSON ?? seed.aiDraft?.jsonString
        entry.deletedAt = date(seed.deletedAt)
        entry.sourceDailyLogId = seed.sourceDailyLogId
        entry.clientMutationId = seed.clientMutationId
        entry.sourceChatMessageId = seed.sourceChatMessageId
        entry.createdAt = date(seed.createdAt) ?? entry.createdAt
        entry.updatedAt = date(seed.updatedAt) ?? Date()
        context.insert(entry)
    }

    private func upsertSideEffect(_ seed: SeedSideEffect) throws {
        let entry = try existingSideEffect(clientMutationId: seed.clientMutationId)
            ?? SideEffectEntry()
        entry.logDate = date(seed.logDate) ?? entry.logDate
        entry.symptom = seed.symptom ?? entry.symptom
        entry.severity = seed.severity
        entry.source = seed.source ?? "app"
        entry.timeZoneIdentifier = seed.timeZoneIdentifier
        entry.clientMutationId = seed.clientMutationId
        entry.createdAt = date(seed.createdAt) ?? entry.createdAt
        entry.updatedAt = date(seed.updatedAt) ?? Date()
        context.insert(entry)
    }

    private func upsertCheckIn(_ seed: SeedCheckIn) throws {
        let entry = try existingCheckIn(clientMutationId: seed.clientMutationId)
            ?? DailyCheckIn()
        entry.logDate = date(seed.logDate) ?? entry.logDate
        entry.moodValence = seed.moodValence
        entry.allClear = seed.allClear ?? false
        entry.note = seed.note
        entry.source = seed.source ?? "app"
        entry.timeZoneIdentifier = seed.timeZoneIdentifier
        entry.clientMutationId = seed.clientMutationId
        entry.createdAt = date(seed.createdAt) ?? entry.createdAt
        entry.updatedAt = date(seed.updatedAt) ?? Date()
        context.insert(entry)
    }

    private func upsertReceipt(envelope: SeedImportEnvelope, summary: SeedImportSummary, sourceData: Data) throws {
        let checksum = envelope.meta.sha256 ?? sha256Hex(sourceData)
        let receipt = try existingReceipt(checksum: checksum) ?? SeedImportReceipt(checksum: checksum)
        receipt.sourceEmail = envelope.meta.subjectEmail
        receipt.importedAt = Date()
        receipt.sourceExportVersion = envelope.meta.version
        receipt.countsJSON = summary.countsJSON
        receipt.checksum = checksum
        receipt.status = "imported"
        receipt.updatedAt = Date()
        context.insert(receipt)
    }

    private func existingProfile(legacyServerId: String) throws -> TrackerProfile? {
        try context.fetch(FetchDescriptor<TrackerProfile>()).first { $0.legacyServerId == legacyServerId }
    }

    private func existingPreference(legacyServerId: String) throws -> UserPreference? {
        try context.fetch(FetchDescriptor<UserPreference>()).first { $0.legacyServerId == legacyServerId }
    }

    private func existingWeight(legacyServerId: String) throws -> WeightEntry? {
        try context.fetch(FetchDescriptor<WeightEntry>()).first { $0.legacyServerId == legacyServerId }
    }

    private func existingInjection(legacyServerId: String) throws -> InjectionEntry? {
        try context.fetch(FetchDescriptor<InjectionEntry>()).first { $0.legacyServerId == legacyServerId }
    }

    private func existingTreatmentPause(legacyServerId: String) throws -> TreatmentPause? {
        try context.fetch(FetchDescriptor<TreatmentPause>()).first { $0.legacyServerId == legacyServerId }
    }

    private func existingDailyLog(legacyServerId: String) throws -> DailyLog? {
        try context.fetch(FetchDescriptor<DailyLog>()).first { $0.legacyServerId == legacyServerId }
    }

    private func existingDailyLogEntry(legacyServerId: String) throws -> DailyLogEntry? {
        try context.fetch(FetchDescriptor<DailyLogEntry>()).first { $0.legacyServerId == legacyServerId }
    }

    private func existingReceipt(checksum: String) throws -> SeedImportReceipt? {
        try context.fetch(FetchDescriptor<SeedImportReceipt>()).first { $0.checksum == checksum }
    }

    private func existingSideEffect(clientMutationId: String?) throws -> SideEffectEntry? {
        guard let clientMutationId else { return nil }
        return try context.fetch(FetchDescriptor<SideEffectEntry>()).first { $0.clientMutationId == clientMutationId }
    }

    private func existingCheckIn(clientMutationId: String?) throws -> DailyCheckIn? {
        guard let clientMutationId else { return nil }
        return try context.fetch(FetchDescriptor<DailyCheckIn>()).first { $0.clientMutationId == clientMutationId }
    }

    private func double(_ raw: String?) -> Double {
        optionalDouble(raw) ?? 0
    }

    private func optionalDouble(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return nil }
        return Double(raw)
    }

    private func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return SeedDateParser.parse(raw)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum SeedDateParser {
    static func parse(_ raw: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: raw) {
            return date
        }

        let internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime]
        if let date = internetFormatter.date(from: raw) {
            return date
        }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return dayFormatter.date(from: raw)
    }
}
