import Foundation
import SwiftUI

enum MedicationSeedScenario: String, CaseIterable, Sendable {
    case tirzepatide
    case semaglutide
    case mixed
}

struct DashboardSnapshot {
    var profile: ProfileSnapshot
    var preferences: PreferenceSnapshot
    var weights: [WeightSnapshot]
    var injections: [InjectionSnapshot]
    var dailyLogs: [DailyLogSnapshot]
    /// Structured Log-tab capture, newest day first (Log v1).
    var dayCaptures: [DayCaptureSnapshot] = []

    /// Every recorded treatment pause as a plain interval, for math that must
    /// not count paused time as time on a dose (the By Dose ledger).
    var pauses: [PauseSnapshot] = []

    var hasProfile: Bool
    var receiptEmail: String?
    /// True when an active `TreatmentPause` covers today (see `TreatmentPause.isActive`).
    /// Suppresses due / overdue / needs-logging across every surface.
    var isTreatmentPaused: Bool = false
    /// When the active pause began, for calm "Paused since …" copy.
    var activePauseStartedAt: Date? = nil

    // Per-field availability predicates. Each card subscribes to the single
    // signal it depends on instead of the coarse `hasAnyData` gate, so a partial
    // onboarding lights up only the surfaces it actually populated. See
    // docs/post-onboarding-adaptive-states-plan.html.
    var hasWeights: Bool { !weights.isEmpty }
    var hasCurrentWeight: Bool { currentWeight != nil }
    var hasInjections: Bool { !injections.isEmpty }
    var hasGoal: Bool { profile.goalWeightKg > 0 }
    /// Log-tab data covers BOTH the legacy daily logs AND the structured Log-v1
    /// day captures (side-effects/mood). A user who only logged a side-effect must
    /// not be treated as having no data.
    var hasLogData: Bool { !dailyLogs.isEmpty || !dayCaptures.isEmpty }

    /// Screen-level "is there anything at all" gate. ORs in `hasLogData` so a
    /// Log-only user is not dumped back to the first-run empty state.
    var hasAnyData: Bool {
        hasProfile || hasWeights || hasInjections || hasLogData
    }

    /// Today's capture state, if anything has been recorded today.
    var todayCapture: DayCaptureSnapshot? {
        dayCaptures.first { Calendar.current.isDateInToday($0.logDate) }
    }

    var injectionCount: Int { injections.count }

    /// Most recent injection, for the literally-true dose context line.
    var lastInjection: InjectionSnapshot? {
        injections.max { $0.injectionDate < $1.injectionDate }
    }

    // Clinically meaningful derivations delegate to TreatmentMath so the
    // widget/glance projection can share one definition. Do not reinline this
    // math here. See Gaurava/Models/TreatmentMath.swift.
    var currentWeight: Double? {
        TreatmentMath.latestWeightKg(weights.map { ($0.weightKg, $0.recordedAt) })
    }

    var totalLost: Double? {
        TreatmentMath.totalLostKg(startingWeightKg: profile.startingWeightKg, currentWeightKg: currentWeight)
    }

    var progress: Double {
        TreatmentMath.progress(
            startingWeightKg: profile.startingWeightKg,
            goalWeightKg: profile.goalWeightKg,
            currentWeightKg: currentWeight
        )
    }

    /// Newest CONFIRMED dose date: the most recent logged injection.
    var newestInjectionDate: Date? { lastInjection?.injectionDate }

    /// Authoritative schedule state. Every due / overdue / paused / provisional
    /// decision derives from this single value so Summary, Jabs, glance, and the
    /// Live Activity always agree, and a historical or stale dose can never become
    /// a giant overdue count. See `TreatmentScheduleEngine`.
    var scheduleState: TreatmentScheduleState {
        TreatmentScheduleEngine.state(
            status: profile.treatmentStatus,
            anchorDate: profile.scheduleAnchorDate,
            newestInjectionDate: newestInjectionDate,
            preferredInjectionDay: profile.preferredInjectionDay,
            isPaused: isTreatmentPaused
        )
    }

    /// Confirmed next-due date — only when the schedule is anchored on a real dose.
    var nextInjectionDate: Date? { scheduleState.scheduledDate }

    var nextInjectionDayCount: Int? { scheduleState.scheduledDayCount }

    /// Form default for the Add Injection picker — always concrete. Not a clinical
    /// claim about where to inject; see `suggestedInjectionSiteDisplay` for the
    /// display-safe variant.
    var suggestedInjectionSite: String {
        let lastSite = injections.sorted(by: { $0.injectionDate > $1.injectionDate }).first?.injectionSite
        return InjectionSiteRotation.suggestedSite(
            after: lastSite,
            preferredSites: preferences.preferredInjectionSites
        )
    }

    /// Display-safe suggested site: nil when there is no injection history, so a
    /// brand-new user is never told where to inject before any jab exists.
    var suggestedInjectionSiteDisplay: String? {
        let lastSite = injections.sorted(by: { $0.injectionDate > $1.injectionDate }).first?.injectionSite
        return InjectionSiteRotation.displaySite(
            after: lastSite,
            preferredSites: preferences.preferredInjectionSites
        )
    }

    /// Provisional next-injection date used only before any jab is logged: the
    /// next future occurrence of the preferred injection weekday. Returns nil when
    /// there is no preferred weekday, or once real injections exist (the logged
    /// cadence in `nextInjectionDate` takes over). Always projects to the future —
    /// it can never read as "today" or "overdue".
    var projectedNextInjectionDate: Date? { scheduleState.plannedDate }
}

struct ProfileSnapshot {
    var displayName: String
    var email: String
    var age: Int
    var gender: String
    var heightCm: Double
    var startingWeightKg: Double
    var goalWeightKg: Double
    var treatmentStartDate: Date
    var plannedDoseMg: Double?
    /// Optional so "unknown stays unknown": nil means the user never told us their
    /// medication, and no surface may present the tirzepatide default as fact. Use
    /// `Medication.inferred(fromMg:)` only as an explicit form editing default.
    var medication: Medication?
    var preferredInjectionDay: Int?
    var reminderDaysBefore: Int
    // Phase 0 treatment contract, defaulted so existing constructors keep working.
    var treatmentStatus: TreatmentStatus = .unknown
    var scheduleAnchorState: ScheduleAnchorState = .unknown
    var treatmentStartProvided: Bool = false
    var scheduleAnchorDate: Date? = nil
    var scheduleAnchorDoseMg: Double? = nil
    var scheduleAnchorSite: String? = nil
}

struct PreferenceSnapshot {
    var weightUnit: String
    var heightUnit: String
    var dateFormat: String
    var weekStartsOn: Int
    var theme: String
    var preferredInjectionSites: [String]

    var colorScheme: ColorScheme? {
        switch theme.lowercased() {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}

struct WeightSnapshot: Identifiable {
    var id = UUID()
    var weightKg: Double
    var recordedAt: Date
    var notes: String?
    /// True when the underlying `WeightEntry` was imported from Apple Health
    /// (`sourceHealthKitUUID != nil`). Drives the provenance glyph in the weight
    /// history ledger so imported readings are distinguishable from typed ones.
    var isFromHealthKit: Bool = false
}

/// One recorded treatment pause. `endedAt` is when treatment actually
/// resumed (the explicit end stamp, falling back to a scheduled resume date);
/// nil while the pause is still open.
struct PauseSnapshot: Identifiable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
}

struct InjectionSnapshot: Identifiable {
    var id = UUID()
    var doseMg: Double
    var injectionSite: String
    var injectionDate: Date
    var batchNumber: String?
    var notes: String?
}

struct DailyLogSnapshot: Identifiable {
    var id = UUID()
    var logDate: Date
    var title: String
    var detail: String
    var tint: Color
    var systemImage: String
}

/// A single noted symptom within a day's capture.
struct SymptomCapture: Identifiable {
    var id: String { kind.rawValue }
    var kind: SideEffectKind
    var severity: SeverityLevel?
    var fromSystem: Bool
}

/// One day of Log-tab capture: noted symptoms, an optional mood, the explicit
/// all-clear flag, and the freeform note. Drives both "Today" and the timeline.
struct DayCaptureSnapshot: Identifiable {
    var id: Date { logDate }
    var logDate: Date
    var symptoms: [SymptomCapture]
    var mood: MoodValence?
    var allClear: Bool
    var note: String?

    var hasSystemSource: Bool { symptoms.contains { $0.fromSystem } }
    var isEmpty: Bool { symptoms.isEmpty && mood == nil && !allClear && (note?.isEmpty ?? true) }
}

extension DashboardSnapshot {
    static let empty = DashboardSnapshot(
        profile: ProfileSnapshot(
            displayName: "Gaurava",
            email: "Profile details",
            age: 0,
            gender: "",
            heightCm: 0,
            startingWeightKg: 0,
            goalWeightKg: 0,
            treatmentStartDate: Date(),
            plannedDoseMg: nil,
            medication: nil,
            preferredInjectionDay: nil,
            reminderDaysBefore: 1
        ),
        preferences: PreferenceSnapshot(
            weightUnit: "kg",
            heightUnit: "cm",
            dateFormat: "DD/MM/YYYY",
            weekStartsOn: 1,
            theme: "system",
            preferredInjectionSites: InjectionSiteRotation.allSites
        ),
        weights: [],
        injections: [],
        dailyLogs: [],
        hasProfile: false,
        receiptEmail: nil
    )

    static func fromModels(
        profiles: [TrackerProfile],
        preferences: [UserPreference],
        weights: [WeightEntry],
        injections: [InjectionEntry],
        dailyLogs: [DailyLog],
        dailyLogEntries: [DailyLogEntry],
        sideEffects: [SideEffectEntry],
        checkIns: [DailyCheckIn],
        receipts: [SeedImportReceipt],
        pauses: [TreatmentPause] = [],
        now: Date = Date()
    ) -> DashboardSnapshot {
        let latestProfile = profiles.sorted { $0.updatedAt > $1.updatedAt }.first
        let latestPreference = preferences.sorted { $0.updatedAt > $1.updatedAt }.first
        let latestReceipt = receipts.sorted { $0.importedAt > $1.importedAt }.first
        let receiptEmail = latestReceipt?.sourceEmail.isEmpty == false ? latestReceipt?.sourceEmail : nil
        // Newest active pause covering today; drives paused state everywhere.
        let activePause = pauses
            .filter { $0.isActive(asOf: now) }
            .max { $0.startedAt < $1.startedAt }

        return DashboardSnapshot(
            profile: ProfileSnapshot(
                displayName: displayName(from: receiptEmail, hasProfile: latestProfile != nil),
                email: receiptEmail ?? "Profile details",
                age: latestProfile?.age ?? 0,
                gender: latestProfile?.gender ?? "",
                heightCm: latestProfile?.heightCm ?? 0,
                // Weight-derived baseline kept: the earliest recorded weight is the
                // user's own honest history, not a fabricated treatment claim, and it
                // backs progress / total-lost math.
                startingWeightKg: latestProfile?.startingWeightKg ?? weights.sorted { $0.recordedAt < $1.recordedAt }.first?.weightKg ?? 0,
                goalWeightKg: latestProfile?.goalWeightKg ?? 0,
                treatmentStartDate: latestProfile?.treatmentStartDate ?? weights.sorted { $0.recordedAt < $1.recordedAt }.first?.recordedAt ?? Date(),
                // No synthesis: planned dose is only what the profile recorded. A
                // historical injection no longer silently becomes a standing plan
                // (readers fall back to the last logged dose themselves).
                plannedDoseMg: latestProfile?.plannedDoseMg,
                // Unknown stays unknown: nil medicationRaw → nil, never tirzepatide.
                medication: latestProfile?.medicationIfKnown,
                preferredInjectionDay: latestProfile?.preferredInjectionDay,
                reminderDaysBefore: latestProfile?.reminderDaysBefore ?? 1,
                treatmentStatus: latestProfile?.treatmentStatus ?? .unknown,
                scheduleAnchorState: latestProfile?.scheduleAnchorState ?? .unknown,
                treatmentStartProvided: latestProfile?.treatmentStartProvided ?? false,
                scheduleAnchorDate: latestProfile?.scheduleAnchorDate,
                scheduleAnchorDoseMg: latestProfile?.scheduleAnchorDoseMg,
                scheduleAnchorSite: latestProfile?.scheduleAnchorSite
            ),
            preferences: PreferenceSnapshot(
                weightUnit: latestPreference?.weightUnit ?? "kg",
                heightUnit: latestPreference?.heightUnit ?? "cm",
                dateFormat: latestPreference?.dateFormat ?? "DD/MM/YYYY",
                weekStartsOn: latestPreference?.weekStartsOn ?? 1,
                theme: latestPreference?.theme ?? "system",
                preferredInjectionSites: latestPreference?.preferredInjectionSites ?? InjectionSiteRotation.allSites
            ),
            weights: weights.map {
                WeightSnapshot(
                    id: $0.id,
                    weightKg: $0.weightKg,
                    recordedAt: $0.recordedAt,
                    notes: $0.notes,
                    isFromHealthKit: $0.sourceHealthKitUUID != nil
                )
            },
            injections: injections.map {
                InjectionSnapshot(
                    id: $0.id,
                    doseMg: $0.doseMg,
                    injectionSite: $0.injectionSite,
                    injectionDate: $0.injectionDate,
                    batchNumber: $0.batchNumber,
                    notes: $0.notes
                )
            },
            dailyLogs: logSnapshots(from: dailyLogs, entries: dailyLogEntries),
            dayCaptures: dayCaptureSnapshots(sideEffects: sideEffects, checkIns: checkIns),
            pauses: pauses.map {
                PauseSnapshot(id: $0.id, startedAt: $0.startedAt, endedAt: $0.endedAt ?? $0.resumedOnDate)
            },
            hasProfile: latestProfile != nil,
            receiptEmail: receiptEmail,
            isTreatmentPaused: activePause != nil,
            activePauseStartedAt: activePause?.startedAt
        )
    }

    /// Aggregate the discrete `SideEffectEntry` rows and per-day `DailyCheckIn`
    /// records into one capture per day, newest first.
    static func dayCaptureSnapshots(
        sideEffects: [SideEffectEntry],
        checkIns: [DailyCheckIn],
        calendar: Calendar = .current
    ) -> [DayCaptureSnapshot] {
        var days = Set<Date>()
        for entry in sideEffects { days.insert(calendar.startOfDay(for: entry.logDate)) }
        for checkIn in checkIns { days.insert(calendar.startOfDay(for: checkIn.logDate)) }

        return days.sorted(by: >).compactMap { day in
            let symptoms = sideEffects
                .filter { calendar.isDate($0.logDate, inSameDayAs: day) }
                .compactMap { entry -> SymptomCapture? in
                    guard let kind = SideEffectKind(rawValue: entry.symptom) else { return nil }
                    return SymptomCapture(
                        kind: kind,
                        severity: entry.severity.flatMap(SeverityLevel.init),
                        fromSystem: entry.source == "system"
                    )
                }
                .sorted { lhs, rhs in
                    let order = SideEffectKind.allCases
                    return (order.firstIndex(of: lhs.kind) ?? 0) < (order.firstIndex(of: rhs.kind) ?? 0)
                }

            let checkIn = checkIns.first { calendar.isDate($0.logDate, inSameDayAs: day) }
            let snapshot = DayCaptureSnapshot(
                logDate: day,
                symptoms: symptoms,
                mood: checkIn?.moodValence.flatMap(MoodValence.init),
                allClear: checkIn?.allClear ?? false,
                note: checkIn?.note
            )
            return snapshot.isEmpty ? nil : snapshot
        }
    }

    static let preview: DashboardSnapshot = {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -84, to: now) ?? now

        return DashboardSnapshot(
            profile: ProfileSnapshot(
                displayName: "Gaurava",
                email: "verification@example.com",
                age: 0,
                gender: "",
                heightCm: 0,
                startingWeightKg: 98.0,
                goalWeightKg: 82.0,
                treatmentStartDate: start,
                plannedDoseMg: 7.5,
                medication: .tirzepatide,
                preferredInjectionDay: 6,
                reminderDaysBefore: 1
            ),
            preferences: PreferenceSnapshot(
                weightUnit: "kg",
                heightUnit: "cm",
                dateFormat: "DD/MM/YYYY",
                weekStartsOn: 1,
                theme: "system",
                preferredInjectionSites: [
                    "Abdomen - Left",
                    "Abdomen - Right",
                    "Thigh - Left",
                    "Thigh - Right"
                ]
            ),
            weights: [
                WeightSnapshot(weightKg: 98.0, recordedAt: start, notes: "Treatment start"),
                WeightSnapshot(weightKg: 95.0, recordedAt: calendar.date(byAdding: .day, value: -56, to: now) ?? now, notes: nil),
                WeightSnapshot(weightKg: 92.9, recordedAt: calendar.date(byAdding: .day, value: -28, to: now) ?? now, notes: "Settled into routine"),
                WeightSnapshot(weightKg: 90.8, recordedAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now, notes: nil)
            ],
            injections: [
                InjectionSnapshot(doseMg: 5.0, injectionSite: "Abdomen - Right", injectionDate: calendar.date(byAdding: .day, value: -21, to: now) ?? now, batchNumber: nil, notes: nil),
                InjectionSnapshot(doseMg: 5.0, injectionSite: "Thigh - Left", injectionDate: calendar.date(byAdding: .day, value: -14, to: now) ?? now, batchNumber: nil, notes: nil),
                InjectionSnapshot(doseMg: 7.5, injectionSite: "Abdomen - Left", injectionDate: calendar.date(byAdding: .day, value: -7, to: now) ?? now, batchNumber: nil, notes: "First 7.5 mg dose")
            ],
            dailyLogs: [
                DailyLogSnapshot(logDate: now, title: "Today", detail: "Energy steady, appetite quiet, hydration on track.", tint: AppTheme.success, systemImage: AppSymbol.Status.onTrack),
                DailyLogSnapshot(logDate: calendar.date(byAdding: .day, value: -1, to: now) ?? now, title: "Yesterday", detail: "Light nausea after dinner, settled by bedtime.", tint: AppTheme.attention, systemImage: AppSymbol.Health.symptomNote),
                DailyLogSnapshot(logDate: calendar.date(byAdding: .day, value: -2, to: now) ?? now, title: "Earlier", detail: "Walked after lunch and logged weight.", tint: AppTheme.weight, systemImage: AppSymbol.Health.walking)
            ],
            hasProfile: true,
            receiptEmail: "verification@example.com"
        )
    }()

    static func medicationVerificationSeed(
        _ scenario: MedicationSeedScenario,
        now: Date = Date()
    ) -> DashboardSnapshot {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7 * 8, to: now) ?? now
        let doses = verificationDoses(for: scenario)
        let medication: Medication = scenario == .semaglutide ? .semaglutide : .tirzepatide
        let weightValues: [Double] = [98.0, 97.2, 96.1, 95.0, 93.8, 92.9, 91.7, 90.8, 90.0]

        return DashboardSnapshot(
            profile: ProfileSnapshot(
                displayName: "Gaurava",
                email: "verification@example.com",
                age: 0,
                gender: "",
                heightCm: 178,
                startingWeightKg: weightValues.first ?? 98,
                goalWeightKg: 82,
                treatmentStartDate: start,
                plannedDoseMg: doses.last,
                medication: medication,
                preferredInjectionDay: calendar.component(.weekday, from: now),
                reminderDaysBefore: 1
            ),
            preferences: PreferenceSnapshot(
                weightUnit: "kg",
                heightUnit: "cm",
                dateFormat: "DD/MM/YYYY",
                weekStartsOn: 1,
                theme: "system",
                preferredInjectionSites: InjectionSiteRotation.allSites
            ),
            weights: weightValues.enumerated().map { index, kg in
                WeightSnapshot(
                    weightKg: kg,
                    recordedAt: calendar.date(byAdding: .day, value: -7 * (weightValues.count - 1 - index), to: now) ?? now,
                    notes: index == 0 ? "Treatment start" : nil
                )
            },
            injections: doses.enumerated().map { index, dose in
                InjectionSnapshot(
                    doseMg: dose,
                    injectionSite: InjectionSiteRotation.allSites[index % InjectionSiteRotation.allSites.count],
                    injectionDate: calendar.date(byAdding: .day, value: -7 * (doses.count - 1 - index), to: now) ?? now,
                    batchNumber: nil,
                    notes: index == 0 ? "First logged dose" : nil
                )
            },
            dailyLogs: [
                DailyLogSnapshot(logDate: now, title: "Today", detail: "Steady day; hydration logged.", tint: AppTheme.success, systemImage: AppSymbol.Status.onTrack),
                DailyLogSnapshot(logDate: calendar.date(byAdding: .day, value: -1, to: now) ?? now, title: "Yesterday", detail: "Mild nausea noted and resolved.", tint: AppTheme.attention, systemImage: AppSymbol.Health.symptomNote)
            ],
            hasProfile: true,
            receiptEmail: "verification@example.com"
        )
    }

    private static func verificationDoses(for scenario: MedicationSeedScenario) -> [Double] {
        switch scenario {
        case .tirzepatide:
            return Medication.tirzepatide.dosePresets
        case .semaglutide:
            return Medication.semaglutide.dosePresets
        case .mixed:
            return [0.25, 0.5, 1, 1.7, 2.4, 5, 10]
        }
    }

    private static func displayName(from email: String?, hasProfile: Bool) -> String {
        guard hasProfile else { return "Gaurava" }
        guard let email, let name = email.split(separator: "@").first, !name.isEmpty else {
            return "Gaurava"
        }
        return name
            .split(separator: ".")
            .compactMap { part in
                guard let first = part.first else { return nil }
                return first.uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func logSnapshots(from logs: [DailyLog], entries: [DailyLogEntry]) -> [DailyLogSnapshot] {
        let entrySnapshots = entries
            .filter { $0.deletedAt == nil && !$0.entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.recordedAt ?? $0.logDate) > ($1.recordedAt ?? $1.logDate) }
            .map {
                DailyLogSnapshot(
                    id: $0.id,
                    logDate: $0.recordedAt ?? $0.logDate,
                    title: logTitle(for: $0.recordedAt ?? $0.logDate),
                    detail: $0.entryText,
                    tint: logTint(for: $0.source),
                    systemImage: logImage(for: $0.source)
                )
            }

        if !entrySnapshots.isEmpty {
            return entrySnapshots
        }

        return logs
            .sorted { $0.logDate > $1.logDate }
            .map {
                DailyLogSnapshot(
                    id: $0.id,
                    logDate: $0.logDate,
                    title: logTitle(for: $0.logDate),
                    detail: $0.notes?.isEmpty == false ? $0.notes ?? "Daily note saved locally." : "Daily note saved locally.",
                    tint: AppTheme.primary,
                    systemImage: AppSymbol.Health.dailyNote
                )
            }
    }

    private static func logTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.appFormatted(.dateTime.month(.abbreviated).day())
    }

    private static func logTint(for source: String) -> Color {
        switch source.lowercased() {
        case "voice":
            return AppTheme.medication
        case "chat":
            return AppTheme.blue
        default:
            return AppTheme.primary
        }
    }

    private static func logImage(for source: String) -> String {
        switch source.lowercased() {
        case "voice":
            return "waveform"
        case "chat":
            return "bubble.left.and.text.bubble.right.fill"
        default:
            return "square.and.pencil"
        }
    }
}
