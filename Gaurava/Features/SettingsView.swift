import CloudKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CareView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [TrackerProfile]
    @Query private var preferences: [UserPreference]
    @Query private var weights: [WeightEntry]
    @Query private var injections: [InjectionEntry]
    @Query private var treatmentPauses: [TreatmentPause]
    @Query private var dailyLogs: [DailyLog]
    @Query private var dailyLogEntries: [DailyLogEntry]
    @Query private var receipts: [SeedImportReceipt]
    let snapshot: DashboardSnapshot
    @State private var activeSheet: CareSheet?
    @State private var showingSeedImporter = false
    @State private var pendingSeedImport: PendingSeedImport?
    @State private var importResult: ImportResult?
    @State private var cloudSyncStatus: CloudSyncStatusState = .checking
    @State private var widgetPrivacy: SurfacePrivacyMode = SurfacePreferences().privacyMode
    @State private var liveActivityEnabled: Bool = SurfacePreferences().liveActivityEnabled
    @State private var injectionRemindersEnabled: Bool = SurfacePreferences().injectionRemindersEnabled
    @State private var remindersDeniedAlertShown = false
    @State private var confirmingPauseToggle = false
    /// Drives the Apple Health row's "Connected"/"Import weight" value. Per-device
    /// opt-in; written by `HealthKitWeightSync` when the user connects/disconnects.
    @AppStorage(HealthKitWeightKeys.enabled) private var healthKitEnabled = false
    #if GAURAVA_ONBOARDING_SANDBOX
    @State private var confirmingOnboardingReplay = false
    #endif

    var body: some View {
        AppScreen(title: "Care", ambientTint: AppTheme.profile) {
            SettingsProfileCard(snapshot: snapshot) {
                activeSheet = .personalInfo
            }

            WeightGoalsCard(snapshot: snapshot) {
                activeSheet = .goals
            }

            ShareJourneyEntryCard(snapshot: snapshot) {
                activeSheet = .shareJourney
            }

            // Treatment STATUS lives here (clinical state), not in Settings: a
            // Skipped/unknown user can set status, and a paused user can resume —
            // closing the one-way-door from onboarding (plan gap G1).
            TreatmentStatusCard(
                snapshot: snapshot,
                onPauseToggle: { confirmingPauseToggle = true },
                onUpdate: { activeSheet = .treatmentStatus }
            )

            SettingsSectionCard(title: "Treatment") {
                Button { activeSheet = .medication } label: {
                    EditableInfoRow(title: "Medication", value: snapshot.profile.medication?.displayName ?? appLocalized("Not set"), systemImage: AppSymbol.Health.dose, tint: AppTheme.medication)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-medication-row")

                Button { activeSheet = .plannedDose } label: {
                    EditableInfoRow(title: "Planned Dose", value: doseText(snapshot.profile.plannedDoseMg), systemImage: AppSymbol.Health.dose, tint: doseColor(snapshot.profile.plannedDoseMg))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-planned-dose-row")

                Button { activeSheet = .injectionSchedule } label: {
                    EditableInfoRow(title: "Injection Day", value: preferredInjectionDayName(snapshot.profile.preferredInjectionDay), systemImage: AppSymbol.Health.schedule, tint: AppTheme.medication)
                }
                .buttonStyle(.plain)

                Button { activeSheet = .injectionSites } label: {
                    EditableInfoRow(title: "Site Rotation", value: siteRotationSummary(snapshot.preferences.preferredInjectionSites), systemImage: AppSymbol.Health.injectionSite, tint: AppTheme.primary)
                }
                .buttonStyle(.plain)

                Button { activeSheet = .injectionSchedule } label: {
                    EditableInfoRow(title: "Reminder", value: reminderText(snapshot.profile.reminderDaysBefore), systemImage: AppSymbol.Health.reminder, tint: AppTheme.amber)
                }
                .buttonStyle(.plain)

                // Turns local injection reminders on/off for THIS device. The row
                // above sets the lead time; this row delivers it. Picking "On" is the
                // explicit, in-context opt-in that requests notification permission.
                Menu {
                    ForEach(RemindersOptIn.allCases) { option in
                        Button {
                            applyInjectionReminders(option.isEnabled)
                        } label: {
                            Label(
                                appLocalized(option.title),
                                systemImage: injectionRemindersEnabled == option.isEnabled ? AppSymbol.Status.selected : option.systemImage
                            )
                        }
                        .accessibilityIdentifier("injection-reminders-option-\(option.rawValue)")
                    }
                } label: {
                    EditableInfoRow(title: "Injection reminders", value: RemindersOptIn.title(for: injectionRemindersEnabled), systemImage: "bell.badge.fill", tint: AppTheme.amber)
                }
                .accessibilityIdentifier("care-injection-reminders-row")
            }

            SettingsSectionCard(title: "Preferences") {
                Button { activeSheet = .units } label: {
                    EditableInfoRow(title: "Units", value: appLocalizedValue("\(snapshot.preferences.weightUnit), \(snapshot.preferences.heightUnit)"), systemImage: AppSymbol.Health.weightUnit, tint: AppTheme.blue)
                }
                .buttonStyle(.plain)

                Button { activeSheet = .appleHealth } label: {
                    EditableInfoRow(title: "Apple Health", value: healthKitEnabled ? "Connected" : "Import weight", systemImage: AppSymbol.Health.appleHealth, tint: AppTheme.rose)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-apple-health-row")

                Menu {
                    ForEach(AppearanceOption.allCases) { option in
                        Button {
                            saveTheme(option.rawValue)
                        } label: {
                            Label(
                                appLocalized(option.title),
                                systemImage: snapshot.preferences.theme == option.rawValue ? AppSymbol.Status.selected : option.systemImage
                            )
                        }
                    }
                } label: {
                    EditableInfoRow(title: "Appearance", value: themeText(snapshot.preferences.theme), systemImage: appearanceIcon(snapshot.preferences.theme), tint: AppTheme.profile)
                }

                Menu {
                    ThemePicker()
                } label: {
                    EditableInfoRow(
                        title: "Theme",
                        value: AppThemeSelection.currentPalette.nameKey,
                        systemImage: "paintpalette",
                        tint: AppTheme.healthPrimary
                    )
                }
                .accessibilityIdentifier("care-theme-row")

                Menu {
                    LanguagePicker()
                } label: {
                    EditableInfoRow(
                        title: "Language",
                        value: AppLanguage(code: AppLocalization.effectiveCode).endonym,
                        systemImage: "globe",
                        tint: AppTheme.blue
                    )
                }
                .accessibilityIdentifier("care-language-row")
            }

            #if GAURAVA_ONBOARDING_SANDBOX
            // Sandbox-only testing affordance: wipe local records + clear the
            // first-run gate so onboarding replays — in whatever language the
            // Language picker above is set to. Compiled only into the
            // com.nags.gaurava.onboarding sandbox (never the real app), so it
            // can never touch real data or production CloudKit.
            SettingsSectionCard(title: "Onboarding sandbox") {
                InfoRow(
                    title: "Replays in",
                    value: AppLanguage(code: AppLocalization.effectiveCode).endonym,
                    systemImage: "globe",
                    tint: AppTheme.blue
                )
                SheetActionButton(title: "Reset & replay onboarding", systemImage: "arrow.counterclockwise", tint: AppTheme.medication) {
                    confirmingOnboardingReplay = true
                }
            }
            #endif

            SettingsSectionCard(title: "Privacy & Sync") {
                Button { activeSheet = .privacy } label: {
                    EditableInfoRow(title: "Privacy Statement", value: "Local-first", systemImage: AppSymbol.Legal.privacy, tint: AppTheme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-privacy-statement-row")

                Button { activeSheet = .dataControls } label: {
                    EditableInfoRow(title: "Data Controls", value: "Export, reset", systemImage: AppSymbol.Action.importHistory, tint: AppTheme.blue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-data-controls-row")

                Menu {
                    ForEach(SurfacePrivacyMode.allDisplayCases, id: \.self) { mode in
                        Button {
                            saveWidgetPrivacy(mode)
                        } label: {
                            Label(
                                appLocalized(mode.displayTitle),
                                systemImage: widgetPrivacy == mode ? AppSymbol.Status.selected : mode.displayIcon
                            )
                        }
                        .accessibilityIdentifier("widget-privacy-option-\(mode.rawValue)")
                    }
                } label: {
                    EditableInfoRow(title: "Widget Privacy", value: widgetPrivacy.displayTitle, systemImage: AppSymbol.Legal.privacy, tint: AppTheme.primary)
                }
                .accessibilityIdentifier("care-widget-privacy-row")

                Menu {
                    ForEach(LiveActivityOptIn.allCases) { option in
                        Button {
                            saveLiveActivityEnabled(option.isEnabled)
                        } label: {
                            Label(
                                appLocalized(option.title),
                                systemImage: liveActivityEnabled == option.isEnabled ? AppSymbol.Status.selected : option.systemImage
                            )
                        }
                        .accessibilityIdentifier("live-activity-option-\(option.rawValue)")
                    }
                } label: {
                    EditableInfoRow(title: "Injection Live Activity", value: LiveActivityOptIn.title(for: liveActivityEnabled), systemImage: AppSymbol.Health.injection, tint: AppTheme.medication)
                }
                .accessibilityIdentifier("care-live-activity-row")

                InfoRow(title: "iCloud Sync", value: cloudSyncStatus.title, systemImage: cloudSyncStatus.systemImage, tint: cloudSyncStatus.tint)
                    .accessibilityIdentifier("care-icloud-sync-row")
            }

            SettingsSectionCard(title: "Medical Safety") {
                Button { activeSheet = .clinicianExport } label: {
                    EditableInfoRow(title: "Share with Clinician", value: "Side effect summary", systemImage: AppSymbol.Health.symptomNote, tint: AppTheme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-clinician-export-row")

                Button { activeSheet = .medicalSafety } label: {
                    EditableInfoRow(title: "Care Guidance", value: "Not medical advice", systemImage: AppSymbol.Legal.medicalSafety, tint: AppTheme.attention)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-medical-safety-row")
            }

            SettingsSectionCard(title: "Support & Legal") {
                Button { activeSheet = .about } label: {
                    EditableInfoRow(title: "About Gaurava", value: appVersionText, systemImage: AppSymbol.Legal.about, tint: AppTheme.profile)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-about-row")

                Link(destination: CareLegalLinks.appleStandardEULAURL) {
                    EditableInfoRow(title: "Terms of Use", value: "Apple EULA", systemImage: AppSymbol.Legal.terms, tint: AppTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-terms-row")

                Link(destination: CareLegalLinks.supportMailURL) {
                    EditableInfoRow(title: "Contact Support", value: "Email", systemImage: AppSymbol.Legal.support, tint: AppTheme.success)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("care-support-row")
            }

            if ownerImportUIEnabled {
                SettingsSectionCard(title: "Data") {
                    if let receipt = receipts.sorted(by: { $0.importedAt > $1.importedAt }).first {
                        InfoRow(title: "History", value: appLocalizedValue("Imported \(receipt.importedAt.appFormatted(Date.FormatStyle(date: .abbreviated, time: .omitted)))"), systemImage: AppSymbol.Status.verified, tint: AppTheme.success)
                    }
                    SheetActionButton(title: "Import History", systemImage: AppSymbol.Action.importDocument, tint: AppTheme.primary) {
                        showingSeedImporter = true
                    }
                }
            }

            Text(appVersionText)
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity)
        }
        .task {
            await refreshCloudSyncStatus()
            // Reflect the real authorization status: if the user revoked
            // notifications in Settings, don't keep showing a stale "on".
            if injectionRemindersEnabled, await !InjectionReminderPermission.isAuthorized() {
                setInjectionRemindersEnabled(false)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .personalInfo:
                PersonalInfoEditorSheet(snapshot: snapshot, save: savePersonalInfo)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .goals:
                GoalsEditorSheet(snapshot: snapshot, save: saveGoals)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .shareJourney:
                ShareJourneyComposerSheet(snapshot: snapshot)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .treatmentStatus:
                TreatmentStatusSheet(snapshot: snapshot, save: saveTreatmentStatus)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .medication:
                MedicationEditorSheet(
                    selectedMedication: snapshot.profile.medication ?? Medication.inferred(fromMg: snapshot.profile.plannedDoseMg),
                    save: saveMedication
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            case .plannedDose:
                PlannedDoseEditorSheet(
                    medication: snapshot.profile.medication ?? Medication.inferred(fromMg: snapshot.profile.plannedDoseMg),
                    plannedDose: snapshot.profile.plannedDoseMg,
                    lastLoggedDose: snapshot.injections.sorted { $0.injectionDate > $1.injectionDate }.first?.doseMg,
                    save: savePlannedDose
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            case .injectionSchedule:
                InjectionScheduleEditorSheet(snapshot: snapshot, save: saveInjectionSchedule)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .injectionSites:
                InjectionSitesEditorSheet(snapshot: snapshot, save: saveInjectionSites)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .units:
                UnitsEditorSheet(snapshot: snapshot, save: saveUnits)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .appleHealth:
                AppleHealthSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .privacy:
                PrivacyStatementSheet(cloudSyncStatus: cloudSyncStatus)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .dataControls:
                DataControlsSheet(recordCounts: currentRecordCounts, makeExport: makeDataExport, resetData: resetAllData)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .medicalSafety:
                MedicalSafetySheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .clinicianExport:
                ClinicianExportSheet(snapshot: snapshot)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .about:
                AboutGauravaSheet(versionText: appVersionText)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $pendingSeedImport) { pending in
            SeedImportConfirmationSheet(pending: pending) {
                importSeed(pending)
            }
        }
        .fileImporter(isPresented: $showingSeedImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            prepareSeedImport(from: result)
        }
        .alert(item: $importResult) { result in
            Alert(title: Text(appLocalized(result.title)), message: Text(appLocalized(result.message)), dismissButton: .default(Text(appLocalized("OK"))))
        }
        .alert(appLocalized("Turn on notifications in Settings"), isPresented: $remindersDeniedAlertShown) {
            Button(appLocalized("OK"), role: .cancel) {}
        } message: {
            Text(appLocalized("To get dose reminders, allow notifications for Gaurava in Settings."))
        }
        .confirmationDialog(
            snapshot.isTreatmentPaused ? "Resume treatment?" : "Pause treatment?",
            isPresented: $confirmingPauseToggle,
            titleVisibility: .visible
        ) {
            Button(snapshot.isTreatmentPaused ? "Resume" : "Pause") {
                if snapshot.isTreatmentPaused { resumeTreatment() } else { pauseTreatment() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(snapshot.isTreatmentPaused
                ? appLocalized("We'll pick your schedule back up from your next logged dose.")
                : appLocalized("No reminders or overdue while you're paused. Resume anytime."))
        }
        #if GAURAVA_ONBOARDING_SANDBOX
        .confirmationDialog(
            "Reset & replay onboarding?",
            isPresented: $confirmingOnboardingReplay,
            titleVisibility: .visible
        ) {
            Button("Reset & replay onboarding", role: .destructive) {
                resetAndReplayOnboarding()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(appLocalized("Wipes this sandbox's local records and returns to the first-run flow, replaying it in the current app language. Sandbox only — it never touches the real Gaurava app or iCloud."))
        }
        #endif
    }

    private func ensureProfile() -> TrackerProfile {
        if let existing = profiles.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return existing
        }
        let profile = TrackerProfile()
        modelContext.insert(profile)
        return profile
    }

    private func ensurePreference() -> UserPreference {
        if let existing = preferences.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return existing
        }
        let preference = UserPreference()
        modelContext.insert(preference)
        return preference
    }

    private func saveWidgetPrivacy(_ mode: SurfacePrivacyMode) {
        widgetPrivacy = mode
        // Per-device display choice, not health data: write the App Group
        // preference, then republish so the producer re-applies redaction and
        // reloads the widget timelines (and reshapes the Live Activity) with the
        // new privacy shape.
        SurfacePreferences().privacyMode = mode
        SurfaceProducers.publish(from: modelContext)
    }

    private func saveLiveActivityEnabled(_ enabled: Bool) {
        liveActivityEnabled = enabled
        // Per-device opt-in (App Group), not health data. Republishing while the
        // app is foregrounded starts a due-today activity on enable, or ends a
        // running one on disable, via the projection's eligibility check.
        SurfacePreferences().liveActivityEnabled = enabled
        InjectionActivityPublisher.refresh(from: modelContext)
    }

    private func applyInjectionReminders(_ enabled: Bool) {
        guard enabled else {
            setInjectionRemindersEnabled(false)
            return
        }
        // Turning ON is the explicit, in-context opt-in: request authorization now
        // (never as a launch side effect), and keep the flag on only if granted.
        Task { @MainActor in
            if await InjectionReminderPermission.request() {
                setInjectionRemindersEnabled(true)
            } else {
                setInjectionRemindersEnabled(false)
                remindersDeniedAlertShown = true
            }
        }
    }

    private func setInjectionRemindersEnabled(_ enabled: Bool) {
        injectionRemindersEnabled = enabled
        // Per-device opt-in (App Group), not health data. Reconcile while
        // foregrounded so the single pending reminder is scheduled on enable or
        // cleared on disable, via the plan's eligibility check.
        SurfacePreferences().injectionRemindersEnabled = enabled
        InjectionReminderScheduler.reconcile(from: modelContext)
    }

    private func saveTheme(_ theme: String) {
        let preference = ensurePreference()
        preference.theme = theme
        preference.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }

    private func savePersonalInfo(age: Int, gender: String, heightCm: Double) {
        let profile = ensureProfile()
        profile.age = age
        profile.gender = gender
        profile.heightCm = heightCm
        profile.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }

    private func saveGoals(startingWeightKg: Double, goalWeightKg: Double, treatmentStartDate: Date) {
        let profile = ensureProfile()
        profile.startingWeightKg = startingWeightKg
        profile.goalWeightKg = goalWeightKg
        profile.treatmentStartDate = treatmentStartDate
        profile.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }

    private func saveMedication(_ medication: Medication) {
        let profile = ensureProfile()
        profile.applyMedication(medication)
        ModelWriteService.save(modelContext)
    }

    /// Begin a treatment break: mark the profile paused and open a TreatmentPause.
    /// Paused state suppresses due/overdue everywhere and ends any Live Activity.
    private func pauseTreatment() {
        let now = Date()
        let profile = ensureProfile()
        profile.treatmentStatus = .paused
        profile.scheduleAnchorState = .paused
        profile.updatedAt = now
        // Guard against a double-tap opening two active pauses (mirrors saveTreatmentStatus).
        if !treatmentPauses.contains(where: { $0.isActive(asOf: now) }) {
            modelContext.insert(TreatmentPause(startedAt: now, reason: "care"))
        }
        ModelWriteService.save(modelContext)
        SurfaceProducers.publish(from: modelContext)
    }

    /// Resume from a break: close any active pause and re-arm the schedule from the
    /// next logged dose — never retroactively overdue.
    private func resumeTreatment() {
        let now = Date()
        for pause in treatmentPauses where pause.isActive(asOf: now) {
            pause.endedAt = now
            pause.resumedOnDate = now
        }
        let profile = ensureProfile()
        profile.treatmentStatus = .active
        profile.scheduleAnchorState = .unknown
        profile.scheduleAnchorDate = nil
        profile.scheduleAnchorUpdatedAt = now
        profile.updatedAt = now
        ModelWriteService.save(modelContext)
        SurfaceProducers.publish(from: modelContext)
    }

    /// Apply a treatment-status change from the Care status sheet. Reconciles the
    /// pause records with the chosen status and, for an active user, records a
    /// confirmed most-recent dose as the schedule anchor.
    private func saveTreatmentStatus(_ draft: TreatmentStatusDraft) {
        let now = Date()
        let profile = ensureProfile()
        let resolved = draft.status ?? .unknown
        profile.treatmentStatus = resolved

        // Reconcile pauses: entering paused opens one; leaving paused closes any.
        if resolved == .paused {
            if !treatmentPauses.contains(where: { $0.isActive(asOf: now) }) {
                modelContext.insert(TreatmentPause(startedAt: now, reason: "care"))
            }
            profile.scheduleAnchorState = .paused
        } else {
            for pause in treatmentPauses where pause.isActive(asOf: now) {
                pause.endedAt = now
                pause.resumedOnDate = now
            }
        }

        switch resolved {
        case .active:
            if draft.lastDoseProvided && draft.confirmLatestDose {
                profile.scheduleAnchorDate = draft.lastDoseDate
                profile.scheduleAnchorSite = draft.site
                profile.scheduleAnchorUpdatedAt = now
                profile.scheduleAnchorState = .confirmedLatestDose
            } else if profile.scheduleAnchorState == .paused {
                profile.scheduleAnchorState = .unknown
            }
        case .startingNow:
            profile.scheduleAnchorState = profile.preferredInjectionDay != nil ? .plannedWeekday : .unknown
        case .unknown:
            if profile.scheduleAnchorState == .paused { profile.scheduleAnchorState = .unknown }
        case .paused:
            break
        }

        profile.updatedAt = now
        ModelWriteService.save(modelContext)
        SurfaceProducers.publish(from: modelContext)
    }

    private func savePlannedDose(_ plannedDose: Double?) {
        let profile = ensureProfile()
        profile.plannedDoseMg = plannedDose
        profile.plannedDoseUpdatedAt = Date()
        profile.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }

    private func saveInjectionSchedule(preferredInjectionDay: Int?, reminderDaysBefore: Int) {
        let profile = ensureProfile()
        profile.preferredInjectionDay = preferredInjectionDay
        profile.reminderDaysBefore = reminderDaysBefore
        profile.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }

    private func saveInjectionSites(_ sites: [String]) {
        let preference = ensurePreference()
        preference.preferredInjectionSites = sites
        preference.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }

    private func saveUnits(weightUnit: String, heightUnit: String, dateFormat: String) {
        let preference = ensurePreference()
        preference.weightUnit = weightUnit
        preference.heightUnit = heightUnit
        preference.dateFormat = dateFormat
        preference.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }

    private func makeDataExport() throws -> URL {
        try GauravaDataExporter.makeExportURL(
            profiles: profiles,
            preferences: preferences,
            weights: weights,
            injections: injections,
            treatmentPauses: treatmentPauses,
            dailyLogs: dailyLogs,
            dailyLogEntries: dailyLogEntries,
            receipts: receipts
        )
    }

    private func resetAllData() throws {
        dailyLogEntries.forEach(modelContext.delete)
        dailyLogs.forEach(modelContext.delete)
        treatmentPauses.forEach(modelContext.delete)
        injections.forEach(modelContext.delete)
        weights.forEach(modelContext.delete)
        preferences.forEach(modelContext.delete)
        profiles.forEach(modelContext.delete)
        receipts.forEach(modelContext.delete)
        try ModelWriteService.saveOrThrow(modelContext)
        // Clear any surface immediately so a widget never shows wiped data, and
        // end any running Live Activity (no injections left -> not due).
        GlancePublisher.publishTombstone()
        InjectionActivityPublisher.refresh(from: modelContext)
    }

    #if GAURAVA_ONBOARDING_SANDBOX
    /// Sandbox-only: wipe local records and clear the first-run gate so the app
    /// returns to the onboarding flow, replaying it in the persisted app
    /// language. Behind GAURAVA_ONBOARDING_SANDBOX so it never compiles into the
    /// real Gaurava app (Debug or Release) — it cannot touch real data or CloudKit.
    private func resetAndReplayOnboarding() {
        do {
            try resetAllData()
            UserDefaults.standard.set(false, forKey: FirstRunFlag.key)
        } catch {
            importResult = ImportResult(title: "Reset failed", message: error.localizedDescription)
        }
    }
    #endif

    private var currentRecordCounts: CareDataRecordCounts {
        CareDataRecordCounts(
            profiles: profiles.count,
            preferences: preferences.count,
            weights: weights.count,
            injections: injections.count,
            treatmentPauses: treatmentPauses.count,
            dailyLogs: dailyLogs.count,
            dailyLogEntries: dailyLogEntries.count,
            receipts: receipts.count
        )
    }

    @MainActor
    private func refreshCloudSyncStatus() async {
        guard CloudKitConfiguration.isEnabled else {
            cloudSyncStatus = .unavailable("Local onboarding sandbox")
            return
        }
        cloudSyncStatus = .checking
        do {
            let status = try await CKContainer(identifier: CloudKitConfiguration.containerIdentifier).accountStatus()
            cloudSyncStatus = CloudSyncStatusState(accountStatus: status)
        } catch {
            cloudSyncStatus = .unavailable("Unable to check")
        }
    }

    private func prepareSeedImport(from result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let envelope = try JSONDecoder().decode(SeedImportEnvelope.self, from: data)
            pendingSeedImport = PendingSeedImport(
                fileName: url.lastPathComponent,
                email: envelope.meta.subjectEmail,
                summary: SeedImportSummary(data: envelope.data),
                data: data
            )
        } catch {
            importResult = ImportResult(title: "Import not ready", message: error.localizedDescription)
        }
    }

    private func importSeed(_ pending: PendingSeedImport) {
        do {
            let summary = try SeedImporter(context: modelContext).importSeed(data: pending.data)
            pendingSeedImport = nil
            importResult = ImportResult(
                title: "Import complete",
                message: "Imported \(summary.totalRecords) records.\n\n\(summary.displayText)"
            )
        } catch {
            pendingSeedImport = nil
            importResult = ImportResult(title: "Import failed", message: error.localizedDescription)
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return appLocalizedValue("Version \(version) (\(build))")
    }

    private var ownerImportUIEnabled: Bool {
        OwnerImportGate.isUserInterfaceEnabled()
    }
}

/// Values collected by `TreatmentStatusSheet` and applied by `saveTreatmentStatus`.
struct TreatmentStatusDraft {
    var status: TreatmentStatus?
    var lastDoseProvided: Bool
    var lastDoseDate: Date
    var site: String?
    var confirmLatestDose: Bool
}

/// Care > Treatment status card (plan gap G1). Shows the current status pill,
/// medication/dose, and next-dose line, with one-tap Pause/Resume and an
/// "Update treatment details" path that reuses the onboarding status components.
private struct TreatmentStatusCard: View {
    let snapshot: DashboardSnapshot
    let onPauseToggle: () -> Void
    let onUpdate: () -> Void

    private var isPaused: Bool { snapshot.isTreatmentPaused }

    var body: some View {
        HealthCard(tint: pill.tint, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Treatment")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    StatusPill(text: pill.text, systemImage: pill.image, tint: pill.tint)
                }
                Text(summaryLine)
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let nextLine {
                    Label(nextLine, systemImage: AppSymbol.Health.schedule)
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.muted)
                }
                VStack(spacing: AppSpacing.md) {
                    SheetActionButton(
                        title: isPaused ? "Resume treatment" : "Pause treatment",
                        systemImage: isPaused ? "play.fill" : "pause.fill",
                        tint: isPaused ? AppTheme.success : AppTheme.blue,
                        action: onPauseToggle
                    )
                    .accessibilityIdentifier("careTreatmentPauseToggle")

                    Button(action: onUpdate) {
                        Text("Update treatment details")
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(AppTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppTheme.actionSurface, in: Capsule())
                            .overlay(Capsule().stroke(AppTheme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("careTreatmentUpdate")
                }
            }
        }
        .accessibilityIdentifier("careTreatmentCard")
    }

    private var pill: (text: String, image: String, tint: Color) {
        if isPaused { return (appLocalized("On a break"), "pause.circle.fill", AppTheme.blue) }
        switch snapshot.profile.treatmentStatus {
        case .active:
            return (appLocalized("Active"), AppSymbol.Status.onTrack, AppTheme.medication)
        case .startingNow:
            return (appLocalized("Just starting"), AppSymbol.Health.start, AppTheme.primary)
        case .paused:
            return (appLocalized("On a break"), "pause.circle.fill", AppTheme.blue)
        case .unknown:
            return snapshot.hasInjections
                ? (appLocalized("Active"), AppSymbol.Status.onTrack, AppTheme.medication)
                : (appLocalized("Status not set"), "questionmark.circle", AppTheme.muted)
        }
    }

    private var summaryLine: String {
        var parts: [String] = []
        if let med = snapshot.profile.medication { parts.append(med.displayName) }
        if let dose = snapshot.profile.plannedDoseMg ?? snapshot.lastInjection?.doseMg {
            parts.append(doseText(dose))
        }
        if parts.isEmpty {
            return appLocalized("Set your medication and dose so Gaurava can guide your schedule.")
        }
        return parts.joined(separator: " · ")
    }

    private var nextLine: String? {
        switch snapshot.scheduleState {
        case .scheduled(let next, _):
            return appLocalizedValue("Next dose \(next.appFormatted(.dateTime.month(.abbreviated).day()))")
        case .planned(let next):
            return appLocalizedValue("Planned for \(next.appFormatted(.dateTime.weekday(.wide)))")
        case .paused:
            return appLocalized("Paused — no next dose scheduled.")
        case .needsConfirmation:
            return appLocalized("Add your most recent dose to set your schedule.")
        case .idle:
            return nil
        }
    }
}

/// Reuses the onboarding status components so a Skipped/unknown user can set their
/// status later, a paused user can resume, and an active user can confirm their
/// most recent dose. The save handler reconciles pause records with the status.
private struct TreatmentStatusSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: DashboardSnapshot
    let save: (TreatmentStatusDraft) -> Void

    @State private var status: TreatmentStatus?
    @State private var lastDoseDate: Date
    @State private var lastDoseProvided: Bool
    @State private var siteSelection: String
    @State private var confirmLatestDose: Bool

    init(snapshot: DashboardSnapshot, save: @escaping (TreatmentStatusDraft) -> Void) {
        self.snapshot = snapshot
        self.save = save
        let profile = snapshot.profile
        _status = State(initialValue: profile.treatmentStatus == .unknown ? nil : profile.treatmentStatus)
        _lastDoseDate = State(initialValue: profile.scheduleAnchorDate ?? Date())
        _lastDoseProvided = State(initialValue: profile.scheduleAnchorDate != nil)
        _siteSelection = State(initialValue: profile.scheduleAnchorSite ?? OnboardingForm.unknownSite)
        _confirmLatestDose = State(initialValue: true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("Where are you in treatment?")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.ink)
                    Text("Update this whenever your treatment changes. Everything stays optional.")
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    TreatmentStatusSelector(selection: $status)

                    if status == .active {
                        Divider().overlay(AppTheme.stroke)
                        Text("Your most recent dose — optional")
                            .font(AppFont.label)
                            .foregroundStyle(AppTheme.muted)
                        OnboardingDateRow(
                            title: "Last dose date",
                            systemImage: AppSymbol.Health.injection,
                            date: $lastDoseDate,
                            provided: $lastDoseProvided,
                            idPrefix: "firstRunMostRecentDose"
                        )
                        if lastDoseProvided {
                            siteRow
                            Toggle(isOn: $confirmLatestDose) {
                                Text("This is my most recent dose")
                                    .font(AppFont.label)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            .tint(AppTheme.primary)
                            .accessibilityIdentifier("firstRunLatestDoseConfirmed")
                        }
                    }

                    Text(footnote)
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.xl)
            }
            .background(AppBackground())
            .navigationTitle(appLocalized("Treatment status"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                SheetActionButton(title: "Save", systemImage: AppSymbol.Action.save, tint: AppTheme.primary) {
                    save(TreatmentStatusDraft(
                        status: status,
                        lastDoseProvided: lastDoseProvided,
                        lastDoseDate: lastDoseDate,
                        site: OnboardingForm.resolvedSite(siteSelection),
                        confirmLatestDose: confirmLatestDose
                    ))
                    dismiss()
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.lg)
                .background(.bar)
                .accessibilityIdentifier("careTreatmentStatusSave")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private var siteRow: some View {
        HStack {
            Image(systemName: AppSymbol.Health.injectionSite)
                .foregroundStyle(AppTheme.muted)
            Text("Site")
                .font(AppFont.label)
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Picker("Site", selection: $siteSelection) {
                Text(appLocalized("Not sure")).tag(OnboardingForm.unknownSite)
                ForEach(InjectionSiteRotation.allSites, id: \.self) { site in
                    Text(InjectionSiteRotation.localizedDisplayName(for: site)).tag(site)
                }
            }
            .pickerStyle(.menu)
            .tint(AppTheme.primary)
        }
        .accessibilityIdentifier("firstRunMostRecentDoseSite")
    }

    private var footnote: String {
        switch status {
        case .paused:
            return appLocalized("We'll pause your schedule — no reminders, no overdue.")
        case .active:
            return appLocalized("We schedule only from a dose you confirm — never from an old start date.")
        case .startingNow:
            return appLocalized("No countdown until you log your first dose.")
        default:
            return appLocalized("Leave this unset to keep things calm and unscheduled.")
        }
    }
}

private enum CareSheet: String, Identifiable {
    case personalInfo
    case goals
    case shareJourney
    case treatmentStatus
    case medication
    case plannedDose
    case injectionSchedule
    case injectionSites
    case units
    case appleHealth
    case privacy
    case dataControls
    case medicalSafety
    case clinicianExport
    case about

    var id: String { rawValue }
}

private struct PendingSeedImport: Identifiable {
    let id = UUID()
    let fileName: String
    let email: String
    let summary: SeedImportSummary
    let data: Data
}

private struct ImportResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum CloudSyncStatusState: Equatable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case unavailable(String)

    init(accountStatus: CKAccountStatus) {
        switch accountStatus {
        case .available:
            self = .available
        case .noAccount:
            self = .noAccount
        case .restricted:
            self = .restricted
        case .temporarilyUnavailable:
            self = .temporarilyUnavailable
        case .couldNotDetermine:
            self = .couldNotDetermine
        @unknown default:
            self = .couldNotDetermine
        }
    }

    var title: String {
        switch self {
        case .checking:
            return "Checking"
        case .available:
            return "Available"
        case .noAccount:
            return "Sign in needed"
        case .restricted:
            return "Restricted"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        case .couldNotDetermine:
            return "Unknown"
        case .unavailable(let message):
            return message
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "Gaurava is checking whether private iCloud sync is available on this device."
        case .available:
            return "Private iCloud sync is available. The system syncs local SwiftData records in the background when conditions allow."
        case .noAccount:
            return "Sign in to iCloud in Settings to sync Gaurava data across your Apple devices."
        case .restricted:
            return "iCloud access is restricted for this Apple Account or device. Gaurava will keep working locally."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Local changes remain on this device and can sync later."
        case .couldNotDetermine:
            return "The current iCloud account state could not be determined. Local tracking remains available."
        case .unavailable:
            return "Gaurava could not check iCloud status right now. Local tracking remains available."
        }
    }

    var systemImage: String {
        switch self {
        case .available:
            return "icloud.fill"
        case .noAccount, .restricted:
            return "icloud.slash.fill"
        case .checking, .temporarilyUnavailable, .couldNotDetermine, .unavailable:
            return "icloud"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            return AppTheme.primary
        case .noAccount, .restricted, .temporarilyUnavailable:
            return AppTheme.attention
        case .checking, .couldNotDetermine, .unavailable:
            return AppTheme.muted
        }
    }
}

private struct CareDataRecordCounts: Equatable {
    let profiles: Int
    let preferences: Int
    let weights: Int
    let injections: Int
    let treatmentPauses: Int
    let dailyLogs: Int
    let dailyLogEntries: Int
    let receipts: Int

    var total: Int {
        profiles + preferences + weights + injections + treatmentPauses + dailyLogs + dailyLogEntries + receipts
    }
}

private enum CareLegalLinks {
    static let appleStandardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let supportMailURL = URL(string: "mailto:nagarajan.natarajan@gmail.com?subject=Gaurava%20Support")!
}

enum GauravaDataExporter {
    static func makeExportURL(
        profiles: [TrackerProfile],
        preferences: [UserPreference],
        weights: [WeightEntry],
        injections: [InjectionEntry],
        treatmentPauses: [TreatmentPause],
        dailyLogs: [DailyLog],
        dailyLogEntries: [DailyLogEntry],
        receipts: [SeedImportReceipt],
        generatedAt: Date = Date()
    ) throws -> URL {
        let data = try makeExportData(
            profiles: profiles,
            preferences: preferences,
            weights: weights,
            injections: injections,
            treatmentPauses: treatmentPauses,
            dailyLogs: dailyLogs,
            dailyLogEntries: dailyLogEntries,
            receipts: receipts,
            generatedAt: generatedAt
        )
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "Gaurava-Data-\(formatter.string(from: generatedAt)).json"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    static func makeExportData(
        profiles: [TrackerProfile],
        preferences: [UserPreference],
        weights: [WeightEntry],
        injections: [InjectionEntry],
        treatmentPauses: [TreatmentPause],
        dailyLogs: [DailyLog],
        dailyLogEntries: [DailyLogEntry],
        receipts: [SeedImportReceipt],
        generatedAt: Date = Date()
    ) throws -> Data {
        let envelope = GauravaExportEnvelope(
            metadata: GauravaExportMetadata(
                appName: "Gaurava",
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.nags.gaurava",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                cloudKitContainerIdentifier: CloudKitConfiguration.containerIdentifier,
                generatedAt: generatedAt
            ),
            profiles: profiles.sorted { $0.updatedAt < $1.updatedAt }.map(ProfileExportRecord.init),
            preferences: preferences.sorted { $0.updatedAt < $1.updatedAt }.map(PreferenceExportRecord.init),
            weights: weights.sorted { $0.recordedAt < $1.recordedAt }.map(WeightExportRecord.init),
            injections: injections.sorted { $0.injectionDate < $1.injectionDate }.map(InjectionExportRecord.init),
            treatmentPauses: treatmentPauses.sorted { $0.startedAt < $1.startedAt }.map(TreatmentPauseExportRecord.init),
            dailyLogs: dailyLogs.sorted { $0.logDate < $1.logDate }.map(DailyLogExportRecord.init),
            dailyLogEntries: dailyLogEntries.sorted { $0.createdAt < $1.createdAt }.map(DailyLogEntryExportRecord.init),
            receipts: receipts.sorted { $0.importedAt < $1.importedAt }.map(SeedImportReceiptExportRecord.init)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }
}

private struct GauravaExportEnvelope: Codable {
    let metadata: GauravaExportMetadata
    let profiles: [ProfileExportRecord]
    let preferences: [PreferenceExportRecord]
    let weights: [WeightExportRecord]
    let injections: [InjectionExportRecord]
    let treatmentPauses: [TreatmentPauseExportRecord]
    let dailyLogs: [DailyLogExportRecord]
    let dailyLogEntries: [DailyLogEntryExportRecord]
    let receipts: [SeedImportReceiptExportRecord]
}

private struct GauravaExportMetadata: Codable {
    let appName: String
    let bundleIdentifier: String
    let appVersion: String
    let buildNumber: String
    let cloudKitContainerIdentifier: String
    let generatedAt: Date
}

private struct ProfileExportRecord: Codable {
    let id: UUID
    let legacyServerId: String?
    let sourceUserId: String?
    let age: Int
    let gender: String
    let heightCm: Double
    let startingWeightKg: Double
    let goalWeightKg: Double
    let treatmentStartDate: Date
    let plannedDoseMg: Double?
    let medication: String?
    let plannedDoseUpdatedAt: Date?
    let preferredInjectionDay: Int?
    let reminderDaysBefore: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ model: TrackerProfile) {
        id = model.id
        legacyServerId = model.legacyServerId
        sourceUserId = model.sourceUserId
        age = model.age
        gender = model.gender
        heightCm = model.heightCm
        startingWeightKg = model.startingWeightKg
        goalWeightKg = model.goalWeightKg
        treatmentStartDate = model.treatmentStartDate
        plannedDoseMg = model.plannedDoseMg
        medication = model.medicationRaw
        plannedDoseUpdatedAt = model.plannedDoseUpdatedAt
        preferredInjectionDay = model.preferredInjectionDay
        reminderDaysBefore = model.reminderDaysBefore
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }
}

private struct PreferenceExportRecord: Codable {
    let id: UUID
    let legacyServerId: String?
    let sourceUserId: String?
    let weightUnit: String
    let heightUnit: String
    let dateFormat: String
    let weekStartsOn: Int
    let theme: String
    let preferredInjectionSites: [String]
    let createdAt: Date
    let updatedAt: Date

    init(_ model: UserPreference) {
        id = model.id
        legacyServerId = model.legacyServerId
        sourceUserId = model.sourceUserId
        weightUnit = model.weightUnit
        heightUnit = model.heightUnit
        dateFormat = model.dateFormat
        weekStartsOn = model.weekStartsOn
        theme = model.theme
        preferredInjectionSites = model.preferredInjectionSites
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }
}

private struct WeightExportRecord: Codable {
    let id: UUID
    let legacyServerId: String?
    let sourceUserId: String?
    let weightKg: Double
    let recordedAt: Date
    let timeZoneIdentifier: String?
    let notes: String?
    let clientMutationId: String?
    let sourceDailyLogEntryId: String?
    let sourceChatMessageId: String?
    let createdAt: Date
    let updatedAt: Date

    init(_ model: WeightEntry) {
        id = model.id
        legacyServerId = model.legacyServerId
        sourceUserId = model.sourceUserId
        weightKg = model.weightKg
        recordedAt = model.recordedAt
        timeZoneIdentifier = model.timeZoneIdentifier
        notes = model.notes
        clientMutationId = model.clientMutationId
        sourceDailyLogEntryId = model.sourceDailyLogEntryId
        sourceChatMessageId = model.sourceChatMessageId
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }
}

private struct InjectionExportRecord: Codable {
    let id: UUID
    let legacyServerId: String?
    let sourceUserId: String?
    let doseMg: Double
    let injectionSite: String
    let injectionDate: Date
    let timeZoneIdentifier: String?
    let batchNumber: String?
    let notes: String?
    let clientMutationId: String?
    let sourceChatMessageId: String?
    let createdAt: Date
    let updatedAt: Date

    init(_ model: InjectionEntry) {
        id = model.id
        legacyServerId = model.legacyServerId
        sourceUserId = model.sourceUserId
        doseMg = model.doseMg
        injectionSite = model.injectionSite
        injectionDate = model.injectionDate
        timeZoneIdentifier = model.timeZoneIdentifier
        batchNumber = model.batchNumber
        notes = model.notes
        clientMutationId = model.clientMutationId
        sourceChatMessageId = model.sourceChatMessageId
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }
}

private struct TreatmentPauseExportRecord: Codable {
    let id: UUID
    let legacyServerId: String?
    let sourceUserId: String?
    let startedAt: Date
    let endedAt: Date?
    let reason: String?
    let resumedOnDate: Date?
    let createdAt: Date

    init(_ model: TreatmentPause) {
        id = model.id
        legacyServerId = model.legacyServerId
        sourceUserId = model.sourceUserId
        startedAt = model.startedAt
        endedAt = model.endedAt
        reason = model.reason
        resumedOnDate = model.resumedOnDate
        createdAt = model.createdAt
    }
}

private struct DailyLogExportRecord: Codable {
    let id: UUID
    let legacyServerId: String?
    let sourceUserId: String?
    let logDate: Date
    let sideEffectsJSON: String?
    let activityJSON: String?
    let mentalJSON: String?
    let dietJSON: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    init(_ model: DailyLog) {
        id = model.id
        legacyServerId = model.legacyServerId
        sourceUserId = model.sourceUserId
        logDate = model.logDate
        sideEffectsJSON = model.sideEffectsJSON
        activityJSON = model.activityJSON
        mentalJSON = model.mentalJSON
        dietJSON = model.dietJSON
        notes = model.notes
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }
}

private struct DailyLogEntryExportRecord: Codable {
    let id: UUID
    let legacyServerId: String?
    let sourceUserId: String?
    let logDate: Date
    let recordedAt: Date?
    let timeZoneIdentifier: String?
    let source: String
    let entryText: String
    let parsedDraftJSON: String?
    let deletedAt: Date?
    let sourceDailyLogId: String?
    let sourceChatMessageId: String?
    let clientMutationId: String?
    let createdAt: Date
    let updatedAt: Date

    init(_ model: DailyLogEntry) {
        id = model.id
        legacyServerId = model.legacyServerId
        sourceUserId = model.sourceUserId
        logDate = model.logDate
        recordedAt = model.recordedAt
        timeZoneIdentifier = model.timeZoneIdentifier
        source = model.source
        entryText = model.entryText
        parsedDraftJSON = model.parsedDraftJSON
        deletedAt = model.deletedAt
        sourceDailyLogId = model.sourceDailyLogId
        sourceChatMessageId = model.sourceChatMessageId
        clientMutationId = model.clientMutationId
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }
}

private struct SeedImportReceiptExportRecord: Codable {
    let id: UUID
    let sourceEmail: String
    let importedAt: Date
    let sourceExportVersion: String
    let countsJSON: String
    let checksum: String
    let status: String
    let createdAt: Date
    let updatedAt: Date

    init(_ model: SeedImportReceipt) {
        id = model.id
        sourceEmail = model.sourceEmail
        importedAt = model.importedAt
        sourceExportVersion = model.sourceExportVersion
        countsJSON = model.countsJSON
        checksum = model.checksum
        status = model.status
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }
}

private struct SettingsProfileCard: View {
    let snapshot: DashboardSnapshot
    let edit: () -> Void

    var body: some View {
        HealthCard(tint: AppTheme.profile, cornerRadius: AppRadius.hero, padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack(spacing: AppSpacing.lg) {
                    Image(systemName: AppSymbol.Health.profile)
                        .font(.system(size: AppIconSize.large, weight: .semibold))
                        .foregroundStyle(AppTheme.profile)
                        .frame(width: 68, height: 68)
                        .background(AppTheme.profile.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(appLocalized("Personal details"))
                            .font(AppFont.cardTitle)
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(AppType.minScale)
                        Text(appLocalized("Used for context in charts and clinician export."))
                            .font(AppFont.body)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(action: edit) {
                        Image(systemName: AppSymbol.Action.edit)
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(AppTheme.muted)
                            .frame(width: 48, height: 48)
                            .background(AppTheme.cardElevated, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appLocalized("Edit profile"))
                }

                if snapshot.hasProfile {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
                        ProfileTile(title: "Age", value: snapshot.profile.age > 0 ? appLocalizedValue("\(snapshot.profile.age)") : appLocalized("Not set"), systemImage: AppSymbol.Health.schedule, tint: AppTheme.profile)
                        ProfileTile(title: "Gender", value: snapshot.profile.gender.isEmpty ? appLocalized("Not set") : appLocalized(snapshot.profile.gender.capitalized), systemImage: AppSymbol.Health.profile, tint: AppTheme.profile)
                        ProfileTile(title: "Height", value: snapshot.profile.heightCm > 0 ? appLocalizedValue("\(snapshot.profile.heightCm.formatted(.number.precision(.fractionLength(0)))) cm") : appLocalized("Not set"), systemImage: AppSymbol.Health.height, tint: AppTheme.blue)
                        ProfileTile(title: "Start Weight", value: weightText(snapshot.profile.startingWeightKg), systemImage: AppSymbol.Health.weightUnit, tint: AppTheme.blue)
                    }
                } else {
                    Text(appLocalized("Add age, height, and other basics when useful."))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, AppSpacing.xs)
                }
            }
        }
    }
}

private struct WeightGoalsCard: View {
    let snapshot: DashboardSnapshot
    let edit: () -> Void

    var body: some View {
        HealthCard(tint: AppTheme.success, cornerRadius: AppRadius.hero, padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack {
                    Label("Weight Goals", systemImage: AppSymbol.Health.goal)
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Button("Edit", action: edit)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.success)
                }

                HStack(spacing: AppSpacing.md) {
                    GoalBox(title: "Starting", value: weightText(snapshot.profile.startingWeightKg))
                    Image(systemName: AppSymbol.Action.next)
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.success)
                    GoalBox(title: "Goal", value: weightText(snapshot.profile.goalWeightKg), highlighted: true)
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Text(appLocalized("Progress toward goal"))
                        Spacer()
                        Text(appLocalizedValue("\(Int((snapshot.progress * 100).rounded()))%"))
                            .foregroundStyle(AppTheme.success)
                    }
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.muted)

                    ProgressView(value: snapshot.progress)
                        .tint(AppTheme.success)

                    Text(appLocalizedValue("\(weightText(snapshot.totalLost ?? 0)) lost · \(weightText((snapshot.currentWeight ?? snapshot.profile.startingWeightKg) - snapshot.profile.goalWeightKg)) to go"))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: title)

            HealthCard {
                VStack(spacing: AppSpacing.lg) {
                    content
                }
            }
        }
    }
}

private struct EditableInfoRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Settings-app idiom: glyph on a tinted gradient squircle, so the
            // rows read as a system settings list rather than a stack of chips.
            Image(systemName: systemImage)
                .font(.system(size: AppIconSize.small, weight: .semibold))
                .foregroundStyle(AppTheme.accentForeground)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(appLocalized(title))
                .font(AppFont.body)
                .foregroundStyle(AppTheme.ink)

            Spacer(minLength: 12)

            Text(appLocalized(value))
                .font(AppFont.bodyStrong)
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.trailing)

            Image(systemName: AppSymbol.Action.disclosure)
                .font(.system(size: AppIconSize.small, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
        }
        .contentShape(Rectangle())
    }
}

private struct ProfileTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ThemedMiniSurface(tint: tint) { surface in
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(surface.iconForeground)
                Text(appLocalized(value))
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(surface.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScaleTight)
                Text(appLocalized(title))
                    .font(AppFont.micro)
                    .foregroundStyle(surface.secondaryForeground)
            }
        }
    }
}

private struct GoalBox: View {
    let title: String
    let value: String
    var highlighted = false

    var body: some View {
        ThemedMiniSurface(tint: highlighted ? AppTheme.success : AppTheme.profile) { surface in
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(appLocalized(title))
                    .font(AppFont.micro)
                    .foregroundStyle(surface.secondaryForeground)
                Text(appLocalized(value))
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(highlighted ? surface.iconForeground : surface.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScaleTight)
            }
        }
    }
}

struct SettingsFormShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let tint: Color
    let saveDisabled: Bool
    let errorMessage: String?
    let save: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(appLocalized(title))
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppTheme.ink)

                content

                if let errorMessage {
                    Text(appLocalized(errorMessage))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.rose)
                }

                Spacer(minLength: 0)

                Button(action: save) {
                    Text(appLocalized("Save"))
                        .font(AppFont.bodyStrong)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                // Affirmative Save is the one brand-green action everywhere; the
                // `tint` parameter stays domain-colored for the form's content.
                .tint(AppTheme.primary)
                .disabled(saveDisabled)
            }
            .padding(AppSpacing.xl)
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
        }
    }
}

/// Age + gender + height editor. Lives here next to Care's profile section but is
/// also presented from Trends (ResultsView) when height is unset, so the BMI prompt
/// tile opens the same form. Keep non-private for that reuse.
struct PersonalInfoEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let save: (Int, String, Double) -> Void
    @State private var age: String
    @State private var gender: String
    @State private var heightCm: String
    @State private var errorMessage: String?

    init(snapshot: DashboardSnapshot, save: @escaping (Int, String, Double) -> Void) {
        self.save = save
        _age = State(initialValue: snapshot.profile.age > 0 ? "\(snapshot.profile.age)" : "")
        _gender = State(initialValue: snapshot.profile.gender.isEmpty ? "male" : snapshot.profile.gender)
        _heightCm = State(initialValue: snapshot.profile.heightCm > 0 ? snapshot.profile.heightCm.formatted(.number.precision(.fractionLength(0...1))) : "")
    }

    var body: some View {
        SettingsFormShell(
            title: "Personal Info",
            tint: AppTheme.profile,
            saveDisabled: parsedAge == nil || parsedHeight == nil,
            errorMessage: errorMessage,
            save: saveDraft
        ) {
            AppTextFieldShell(systemImage: AppSymbol.Health.schedule, tint: AppTheme.profile) {
                TextField("Age", text: $age)
                    .keyboardType(.numberPad)
            }
            Picker("Gender", selection: $gender) {
                Text(appLocalized("Male")).tag("male")
                Text(appLocalized("Female")).tag("female")
                Text(appLocalized("Other")).tag("other")
                Text(appLocalized("Prefer not to say")).tag("prefer_not_to_say")
            }
            .pickerStyle(.segmented)
            AppTextFieldShell(systemImage: AppSymbol.Health.height, tint: AppTheme.blue) {
                TextField("Height cm", text: $heightCm)
                    .keyboardType(.decimalPad)
            }
        }
    }

    private func saveDraft() {
        guard let ageValue = parsedAge, let heightValue = parsedHeight else {
            errorMessage = "Enter valid age and height."
            return
        }
        save(ageValue, gender, heightValue)
        dismiss()
    }

    private var parsedAge: Int? {
        let trimmed = age.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private var parsedHeight: Double? {
        positiveDecimal(heightCm)
    }
}

struct GoalsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let save: (Double, Double, Date) -> Void
    @State private var startingWeight: String
    @State private var goalWeight: String
    @State private var treatmentStartDate: Date
    @State private var errorMessage: String?

    init(snapshot: DashboardSnapshot, save: @escaping (Double, Double, Date) -> Void) {
        self.save = save
        let starting = snapshot.profile.startingWeightKg > 0 ? snapshot.profile.startingWeightKg : snapshot.currentWeight
        _startingWeight = State(initialValue: starting.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "")
        _goalWeight = State(initialValue: snapshot.profile.goalWeightKg > 0 ? snapshot.profile.goalWeightKg.formatted(.number.precision(.fractionLength(0...1))) : "")
        _treatmentStartDate = State(initialValue: snapshot.profile.treatmentStartDate)
    }

    var body: some View {
        SettingsFormShell(
            title: "Goals",
            tint: AppTheme.success,
            saveDisabled: parsedStartingWeight == nil || parsedGoalWeight == nil,
            errorMessage: errorMessage,
            save: saveDraft
        ) {
            AppTextFieldShell(systemImage: AppSymbol.Health.weightUnit, tint: AppTheme.blue) {
                TextField("Starting weight kg", text: $startingWeight)
                    .keyboardType(.decimalPad)
            }
            AppTextFieldShell(systemImage: AppSymbol.Health.goal, tint: AppTheme.success) {
                TextField("Goal weight kg", text: $goalWeight)
                    .keyboardType(.decimalPad)
            }
            DatePicker("Treatment start", selection: $treatmentStartDate, displayedComponents: .date)
        }
    }

    private func saveDraft() {
        guard let starting = parsedStartingWeight, let goal = parsedGoalWeight else {
            errorMessage = "Enter valid weights."
            return
        }
        save(starting, goal, treatmentStartDate)
        dismiss()
    }

    private var parsedStartingWeight: Double? {
        positiveDecimal(startingWeight)
    }

    private var parsedGoalWeight: Double? {
        positiveDecimal(goalWeight)
    }
}

private struct MedicationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let save: (Medication) -> Void
    @State private var selectedMedication: Medication

    init(selectedMedication: Medication, save: @escaping (Medication) -> Void) {
        self.save = save
        _selectedMedication = State(initialValue: selectedMedication)
    }

    var body: some View {
        SettingsFormShell(title: "Medication", tint: AppTheme.medication, saveDisabled: false, errorMessage: nil, save: saveDraft) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(Medication.allCases) { medication in
                    Button {
                        selectedMedication = medication
                    } label: {
                        MedicationOptionRow(medication: medication, isSelected: selectedMedication == medication)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("medication-option-\(medication.rawValue)")
                }
            }
        }
        .accessibilityIdentifier("medication-editor-sheet")
    }

    private func saveDraft() {
        save(selectedMedication)
        dismiss()
    }
}

private struct PlannedDoseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let lastLoggedDose: Double?
    let save: (Double?) -> Void
    @State private var selectedDose: Double?
    private let doseOptions: [Double]

    init(medication: Medication, plannedDose: Double?, lastLoggedDose: Double?, save: @escaping (Double?) -> Void) {
        self.lastLoggedDose = lastLoggedDose
        self.save = save
        doseOptions = doseOptionValues(for: medication, including: plannedDose)
        _selectedDose = State(initialValue: plannedDose)
    }

    var body: some View {
        SettingsFormShell(title: "Planned Dose", tint: AppTheme.medication, saveDisabled: false, errorMessage: nil, save: saveDraft) {
            Button {
                selectedDose = nil
            } label: {
                DoseChoiceRow(
                    title: "Use last logged dose",
                    subtitle: lastLoggedDose.map { appLocalizedValue("Currently \(doseText($0))") } ?? appLocalized("No logged dose yet"),
                    isSelected: selectedDose == nil
                )
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
                ForEach(doseOptions, id: \.self) { dose in
                    Button {
                        selectedDose = dose
                    } label: {
                        DoseOptionChip(text: doseText(dose), isSelected: selectedDose == dose)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityIdentifier("planned-dose-editor-sheet")
    }

    private func saveDraft() {
        save(selectedDose)
        dismiss()
    }
}

private struct InjectionScheduleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let save: (Int?, Int) -> Void
    @State private var preferredDay: Int
    @State private var reminderDays: Int
    @State private var usePreferredDay: Bool

    init(snapshot: DashboardSnapshot, save: @escaping (Int?, Int) -> Void) {
        self.save = save
        _preferredDay = State(initialValue: snapshot.profile.preferredInjectionDay ?? 1)
        _reminderDays = State(initialValue: snapshot.profile.reminderDaysBefore)
        _usePreferredDay = State(initialValue: snapshot.profile.preferredInjectionDay != nil)
    }

    var body: some View {
        SettingsFormShell(title: "Injection Schedule", tint: AppTheme.medication, saveDisabled: false, errorMessage: nil, save: saveDraft) {
            Toggle("Use preferred day", isOn: $usePreferredDay)
                .tint(AppTheme.primary)
            Picker("Injection day", selection: $preferredDay) {
                ForEach(0..<7) { day in
                    // preferredInjectionDayName already returns the localized weekday
                    // name (dynamic data, not a catalog key) — render it verbatim.
                    Text(verbatim: preferredInjectionDayName(day)).tag(day)
                }
            }
            .disabled(!usePreferredDay)
            Picker("Reminder", selection: $reminderDays) {
                Text(appLocalized("Same day")).tag(0)
                Text(appLocalized("1 day before")).tag(1)
                Text(appLocalized("2 days before")).tag(2)
            }
            .pickerStyle(.segmented)
        }
    }

    private func saveDraft() {
        save(usePreferredDay ? preferredDay : nil, reminderDays)
        dismiss()
    }
}

private struct InjectionSitesEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let save: ([String]) -> Void
    @State private var selectedSites: Set<String>

    init(snapshot: DashboardSnapshot, save: @escaping ([String]) -> Void) {
        self.save = save
        _selectedSites = State(initialValue: Set(snapshot.preferences.preferredInjectionSites))
    }

    var body: some View {
        SettingsFormShell(
            title: "Site Rotation",
            tint: AppTheme.primary,
            saveDisabled: selectedSitesInOrder.count < 2,
            errorMessage: selectedSitesInOrder.count < 2 ? "Choose at least two sites for rotation." : nil,
            save: saveDraft
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(InjectionSiteRotation.allSites, id: \.self) { site in
                    Toggle(isOn: isSelected(site)) {
                        Text(InjectionSiteRotation.localizedDisplayName(for: site))
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(AppTheme.ink)
                    }
                    .tint(AppTheme.primary)
                    .padding(AppSpacing.lg)
                    .background(AppTheme.cardElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .stroke(selectedSites.contains(site) ? AppTheme.primary.opacity(0.45) : AppTheme.stroke, lineWidth: 1)
                    )
                }
            }

            Button("Use all sites", systemImage: AppSymbol.Status.selectedCircle) {
                selectedSites = Set(InjectionSiteRotation.allSites)
            }
            .font(AppFont.bodyStrong)
            .foregroundStyle(AppTheme.primary)
        }
    }

    private var selectedSitesInOrder: [String] {
        InjectionSiteRotation.allSites.filter { selectedSites.contains($0) }
    }

    private func isSelected(_ site: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedSites.contains(site)
            },
            set: { isSelected in
                if isSelected {
                    selectedSites.insert(site)
                } else {
                    selectedSites.remove(site)
                }
            }
        )
    }

    private func saveDraft() {
        guard selectedSitesInOrder.count >= 2 else { return }
        save(selectedSitesInOrder)
        dismiss()
    }
}

private struct UnitsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let save: (String, String, String) -> Void
    @State private var weightUnit: String
    @State private var heightUnit: String
    @State private var dateFormat: String

    init(snapshot: DashboardSnapshot, save: @escaping (String, String, String) -> Void) {
        self.save = save
        _weightUnit = State(initialValue: snapshot.preferences.weightUnit)
        _heightUnit = State(initialValue: snapshot.preferences.heightUnit)
        _dateFormat = State(initialValue: snapshot.preferences.dateFormat)
    }

    var body: some View {
        SettingsFormShell(title: "Units", tint: AppTheme.blue, saveDisabled: false, errorMessage: nil, save: saveDraft) {
            Picker("Weight", selection: $weightUnit) {
                Text(appLocalized("kg")).tag("kg")
                Text(appLocalized("lbs")).tag("lbs")
                Text(appLocalized("stone")).tag("stone")
            }
            .pickerStyle(.segmented)
            Picker("Height", selection: $heightUnit) {
                Text(appLocalized("cm")).tag("cm")
                Text(appLocalized("ft/in")).tag("ft-in")
            }
            .pickerStyle(.segmented)
            Picker("Date", selection: $dateFormat) {
                Text(appLocalized("DD/MM/YYYY")).tag("DD/MM/YYYY")
                Text(appLocalized("MM/DD/YYYY")).tag("MM/DD/YYYY")
                Text(appLocalized("YYYY-MM-DD")).tag("YYYY-MM-DD")
            }
        }
    }

    private func saveDraft() {
        save(weightUnit, heightUnit, dateFormat)
        dismiss()
    }
}

private struct DoseChoiceRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: isSelected ? AppSymbol.Status.selectedCircle : AppSymbol.Status.unselectedCircle)
                .foregroundStyle(isSelected ? AppTheme.medication : AppTheme.muted)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(appLocalized(title))
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.ink)
                Text(appLocalized(subtitle))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
        }
        .padding(AppSpacing.lg)
        .background(AppTheme.cardElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }
}

private struct MedicationOptionRow: View {
    let medication: Medication
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: isSelected ? AppSymbol.Status.selectedCircle : AppSymbol.Status.unselectedCircle)
                .foregroundStyle(isSelected ? AppTheme.medication : AppTheme.muted)
            Text(appLocalized(medication.displayName))
                .font(AppFont.bodyStrong)
                .foregroundStyle(AppTheme.ink)
            Spacer()
        }
        .padding(AppSpacing.lg)
        .background(AppTheme.cardElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(isSelected ? AppTheme.medication.opacity(0.45) : AppTheme.stroke, lineWidth: 1)
        )
    }
}

private struct DoseOptionChip: View {
    let text: String
    let isSelected: Bool

    var body: some View {
        Text(appLocalized(text))
            .font(AppFont.bodyStrong)
            .foregroundStyle(isSelected ? AppTheme.accentForeground : AppTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(isSelected ? AppTheme.medication : AppTheme.cardElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(isSelected ? AppTheme.medication : AppTheme.stroke, lineWidth: 1)
            )
    }
}

private struct PrivacyStatementSheet: View {
    let cloudSyncStatus: CloudSyncStatusState

    var body: some View {
        CareInfoSheet(title: "Privacy Statement", tint: AppTheme.primary) {
            PolicyHero(
                systemImage: AppSymbol.Legal.privacy,
                title: "Private by default",
                message: "Gaurava is built for local treatment tracking. Your routine data stays on your device and can sync through your private iCloud account when iCloud is available."
            )

            PolicySection(title: "What Gaurava Stores") {
                PolicyBullet("Profile basics such as age, height, goals, treatment start date, and preferences.")
                PolicyBullet("Weight entries, injection records, treatment pauses, daily logs, and notes you choose to save.")
                PolicyBullet("Seed import receipts used to avoid importing the same source history repeatedly.")
            }

            PolicySection(title: "Where It Goes") {
                PolicyBullet("Routine reads and writes are local SwiftData operations on this device.")
                PolicyBullet(CloudKitConfiguration.isEnabled
                    ? appLocalizedValue("When iCloud is available, SwiftData uses the private CloudKit container \(CloudKitConfiguration.containerIdentifier) for background sync across your Apple devices.")
                    : "This onboarding sandbox stores data locally only and does not connect to CloudKit.")
                PolicyBullet("Gaurava does not include advertising SDKs, analytics SDKs, data brokers, or a Gaurava-hosted account server.")
            }

            PolicySection(title: "Control") {
                PolicyBullet("Use Data Controls to export a JSON copy of your records.")
                PolicyBullet("Use Reset Gaurava Data to delete local records; the system will sync those deletions to your other signed-in devices when CloudKit sync runs.")
                PolicyBullet("Photos access is only requested when you ask Gaurava to save a journey card to your Photos library.")
            }

            StatusDisclosureRow(title: "Current iCloud Status", detail: cloudSyncStatus.detail, systemImage: cloudSyncStatus.systemImage, tint: cloudSyncStatus.tint)
        }
    }
}

private struct DataControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recordCounts: CareDataRecordCounts
    let makeExport: () throws -> URL
    let resetData: () throws -> Void
    @State private var exportURL: URL?
    @State private var actionMessage: String?
    @State private var actionError: String?
    @State private var showingResetConfirmation = false

    var body: some View {
        CareInfoSheet(title: "Data Controls", tint: AppTheme.blue) {
            PolicyHero(
                systemImage: AppSymbol.Action.importHistory,
                title: appLocalizedValue("\(recordCounts.total) records"),
                message: "Export a complete JSON backup or reset the local Gaurava store on this device."
            )

            HealthCard(tint: AppTheme.blue, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
                    RecordCountTile(title: "Weights", count: recordCounts.weights, tint: AppTheme.blue)
                    RecordCountTile(title: "Jabs", count: recordCounts.injections, tint: AppTheme.medication)
                    RecordCountTile(title: "Daily Logs", count: recordCounts.dailyLogs + recordCounts.dailyLogEntries, tint: AppTheme.success)
                    RecordCountTile(title: "Settings", count: recordCounts.profiles + recordCounts.preferences, tint: AppTheme.profile)
                }
            }

            PolicySection(title: "Export") {
                PolicyBullet("The export includes profile, preferences, weight entries, injections, treatment pauses, logs, log entries, and import receipts.")
                PolicyBullet("The JSON file is prepared on this device and shared only when you choose where to send or save it.")
            }

            SheetActionButton(title: exportURL == nil ? "Prepare JSON Export" : "Refresh JSON Export", systemImage: AppSymbol.Action.importHistory, tint: AppTheme.blue) {
                prepareExport()
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label(appLocalized("Share JSON Export"), systemImage: AppSymbol.Action.share)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.accentForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                        .background(AppTheme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            PolicySection(title: "Reset") {
                PolicyBullet("Reset removes Gaurava records from this device.")
                PolicyBullet("If iCloud sync is active, CloudKit can propagate these deletions to other devices signed in with the same Apple Account.")
                PolicyBullet("Export first if you want a copy before deleting.")
            }

            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label(appLocalized("Reset Gaurava Data"), systemImage: AppSymbol.Action.delete)
                    .font(AppFont.bodyStrong)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if let actionMessage {
                StatusDisclosureRow(title: "Done", detail: actionMessage, systemImage: AppSymbol.Status.verified, tint: AppTheme.success)
            }

            if let actionError {
                StatusDisclosureRow(title: "Could not complete action", detail: actionError, systemImage: AppSymbol.Status.needsLogging, tint: AppTheme.rose)
            }
        }
        .confirmationDialog("Reset Gaurava data?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset Gaurava Data", role: .destructive) {
                resetLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes local profile, treatment, weight, injection, log, and import records. Export first if you need a backup.")
        }
    }

    private func prepareExport() {
        do {
            exportURL = try makeExport()
            actionError = nil
            actionMessage = "JSON export is ready to share."
        } catch {
            actionMessage = nil
            actionError = error.localizedDescription
        }
    }

    private func resetLocalData() {
        do {
            try resetData()
            exportURL = nil
            actionError = nil
            actionMessage = "Gaurava data was reset on this device."
            dismiss()
        } catch {
            actionMessage = nil
            actionError = error.localizedDescription
        }
    }
}

private struct AppleHealthSheet: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HealthKitWeightKeys.enabled) private var enabled = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var isAvailable: Bool { HealthKitWeightSync.isAvailable }

    var body: some View {
        CareInfoSheet(title: "Apple Health", tint: AppTheme.rose) {
            PolicyHero(
                systemImage: AppSymbol.Health.appleHealth,
                title: "Import weight from Apple Health",
                message: "Gaurava reads body weight from Apple Health so readings you already logged appear in your trends — automatically, and only when you allow it."
            )

            PolicySection(title: "How it works") {
                PolicyBullet("Gaurava only reads weight. It never writes anything back to Apple Health.")
                PolicyBullet("New readings sync each time you open Gaurava.")
                PolicyBullet("You can disconnect anytime. Imported weights stay in Gaurava.")
            }

            if !isAvailable {
                StatusDisclosureRow(
                    title: "Apple Health is unavailable",
                    detail: "This device does not have Apple Health, so weight import isn't available here.",
                    systemImage: AppSymbol.Status.needsLogging,
                    tint: AppTheme.muted
                )
            } else if enabled {
                if let synced = HealthKitWeightSync.lastSyncedAt {
                    StatusDisclosureRow(
                        title: "Connected to Apple Health",
                        detail: appLocalizedValue("Last synced \(synced.appFormatted(.dateTime.month(.abbreviated).day().hour().minute()))"),
                        systemImage: AppSymbol.Status.verified,
                        tint: AppTheme.success
                    )
                }

                SheetActionButton(title: isWorking ? "Syncing…" : "Sync Now", systemImage: AppSymbol.Health.appleHealth, tint: AppTheme.rose) {
                    runSync()
                }
                .disabled(isWorking)
                .accessibilityIdentifier("apple-health-sync-now")

                Button(role: .destructive) {
                    HealthKitWeightSync.disconnect()
                    statusMessage = nil
                    errorMessage = nil
                } label: {
                    Label(appLocalized("Disconnect"), systemImage: AppSymbol.Action.delete)
                        .font(AppFont.bodyStrong)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isWorking)
                .accessibilityIdentifier("apple-health-disconnect")
            } else {
                SheetActionButton(title: isWorking ? "Connecting…" : "Connect Apple Health", systemImage: AppSymbol.Health.appleHealth, tint: AppTheme.rose) {
                    runConnect()
                }
                .disabled(isWorking)
                .accessibilityIdentifier("apple-health-connect")
            }

            if let statusMessage {
                StatusDisclosureRow(title: "Done", detail: statusMessage, systemImage: AppSymbol.Status.verified, tint: AppTheme.success)
            }
            if let errorMessage {
                StatusDisclosureRow(title: "Couldn't import from Apple Health", detail: errorMessage, systemImage: AppSymbol.Status.needsLogging, tint: AppTheme.rose)
            }
        }
    }

    private func runConnect() {
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        Task { @MainActor in
            let outcome = await HealthKitWeightSync.connect(context: modelContext)
            applyOutcome(outcome)
            isWorking = false
        }
    }

    private func runSync() {
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        Task { @MainActor in
            let outcome = await HealthKitWeightSync.syncNow(context: modelContext)
            applyOutcome(outcome)
            isWorking = false
        }
    }

    private func applyOutcome(_ outcome: HealthKitWeightOutcome) {
        switch outcome {
        case .unavailable:
            errorMessage = appLocalized("Apple Health is unavailable on this device.")
        case let .imported(new):
            statusMessage = new > 0
                ? appLocalizedValue("Imported \(new) new weight readings.")
                : appLocalized("No new weight readings found.")
        case let .failed(message):
            errorMessage = message
        }
    }
}

private struct MedicalSafetySheet: View {
    var body: some View {
        CareInfoSheet(title: "Medical Safety", tint: AppTheme.attention) {
            PolicyHero(
                systemImage: AppSymbol.Legal.medicalSafety,
                title: "Tracking, not treatment",
                message: "Gaurava helps you record your treatment routine. It does not diagnose, prescribe, calculate drug dosage, or replace clinical advice."
            )

            PolicySection(title: "Before Decisions") {
                PolicyBullet("Check with a doctor or qualified clinician before making medical decisions.")
                PolicyBullet("Use medication labels, pharmacy instructions, and clinician guidance as the source of truth for dose and schedule.")
                PolicyBullet("Seek urgent care immediately for severe symptoms or any emergency concern.")
            }

            PolicySection(title: "How Gaurava Uses Dose Data") {
                PolicyBullet("Dose fields are user-entered tracking values.")
                PolicyBullet("Gaurava can display your last logged or planned dose, but it does not recommend dose changes.")
                PolicyBullet("Reminder and schedule settings are convenience tools, not clinical instructions.")
            }
        }
    }
}

private struct AboutGauravaSheet: View {
    let versionText: String

    var body: some View {
        CareInfoSheet(title: "About Gaurava", tint: AppTheme.profile) {
            PolicyHero(
                systemImage: AppSymbol.Legal.about,
                title: "Gaurava",
                message: "A private, local-first treatment tracker for calm recovery of agency, dignity, and continuity."
            )

            PolicySection(title: "Product") {
                PolicyBullet("Native iPhone and iPad app.")
                PolicyBullet("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown").")
                PolicyBullet(CloudKitConfiguration.isEnabled
                    ? appLocalizedValue("CloudKit container: \(CloudKitConfiguration.containerIdentifier).")
                    : "CloudKit: disabled for local onboarding sandbox.")
                PolicyBullet(versionText)
            }

            PolicySection(title: "Legal") {
                Link(destination: CareLegalLinks.appleStandardEULAURL) {
                    Label("Apple Standard Terms of Use", systemImage: AppSymbol.Legal.terms)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.primary)
                }
                Link(destination: CareLegalLinks.supportMailURL) {
                    Label("Contact Support", systemImage: AppSymbol.Legal.support)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }
}

private struct CareInfoSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    content
                }
                .padding(AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxl)
            }
            .background(AppBackground())
            .navigationTitle(appLocalized(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(tint)
                }
            }
        }
    }
}

private struct PolicyHero: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HealthCard(tint: AppTheme.primary, cornerRadius: AppRadius.hero, padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.primary.opacity(0.14), in: Circle())

                Text(appLocalized(title))
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppTheme.ink)

                Text(appLocalized(message))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PolicySection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HealthCard(tint: AppTheme.profile, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(appLocalized(title))
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.ink)
                content
            }
        }
    }
}

private struct PolicyBullet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Circle()
                .fill(AppTheme.primary)
                .frame(width: 6, height: 6)
                .padding(.top, AppSpacing.sm)
            Text(appLocalized(text))
                .font(AppFont.body)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StatusDisclosureRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HealthCard(tint: tint, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: AppIconSize.medium, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(appLocalized(title))
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.ink)
                    Text(appLocalized(detail))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct RecordCountTile: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(appLocalizedValue("\(count)"))
                .font(AppFont.cardTitle)
                .foregroundStyle(tint)
            Text(appLocalized(title))
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppTheme.cardElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }
}

private struct SeedImportConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pending: PendingSeedImport
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    LabeledContent("Name", value: pending.fileName)
                    LabeledContent("Source", value: pending.email)
                }

                Section("Records") {
                    LabeledContent("Profiles", value: "\(pending.summary.profiles)")
                    LabeledContent("Weights", value: "\(pending.summary.weightEntries)")
                    LabeledContent("Jabs", value: "\(pending.summary.injections)")
                    LabeledContent("Daily logs", value: "\(pending.summary.dailyLogs)")
                    LabeledContent("Log entries", value: "\(pending.summary.dailyLogEntries)")
                }

                Section {
                    Button {
                        onImport()
                    } label: {
                        Label("Import \(pending.summary.totalRecords) Records", systemImage: AppSymbol.Action.importHistory)
                    }
                }
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

// Display vocabulary for the surface privacy preference (Build 2). The mode
// itself lives in SharedSurfaces (Foundation only); titles/icons stay app-side.
extension SurfacePrivacyMode {
    static var allDisplayCases: [SurfacePrivacyMode] { [.full, .minimal, .redacted] }

    var displayTitle: String {
        switch self {
        case .full: return "Full detail"
        case .minimal: return "Minimal"
        case .redacted: return "Hide details"
        }
    }

    var displayIcon: String {
        switch self {
        case .full: return "eye"
        case .minimal: return "eye.trianglebadge.exclamationmark"
        case .redacted: return "eye.slash"
        }
    }
}

// Opt-in vocabulary for the injection-day Live Activity (Build 4). The flag
// itself lives in SharedSurfaces (App Group, per-device); titles/icons stay
// app-side, mirroring the Widget Privacy picker pattern.
private enum LiveActivityOptIn: String, CaseIterable, Identifiable {
    case on
    case off

    var id: String { rawValue }
    var isEnabled: Bool { self == .on }

    var title: String {
        switch self {
        case .on: return "On"
        case .off: return "Off"
        }
    }

    var systemImage: String {
        switch self {
        case .on: return "bell.badge.fill"
        case .off: return "bell.slash"
        }
    }

    static func title(for enabled: Bool) -> String {
        (enabled ? LiveActivityOptIn.on : .off).title
    }
}

private enum RemindersOptIn: String, CaseIterable, Identifiable {
    case on
    case off

    var id: String { rawValue }
    var isEnabled: Bool { self == .on }

    var title: String {
        switch self {
        case .on: return "On"
        case .off: return "Off"
        }
    }

    var systemImage: String {
        switch self {
        case .on: return "bell.badge.fill"
        case .off: return "bell.slash"
        }
    }

    static func title(for enabled: Bool) -> String {
        (enabled ? RemindersOptIn.on : .off).title
    }
}

private enum AppearanceOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "iphone"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }
}

private func preferredInjectionDayName(_ value: Int?) -> String {
    guard let value else { return appLocalized("Not set") }
    // effectiveCalendar so the weekday name follows the in-app picker, not the
    // system locale (see AppLocalization).
    return AppLocalization.effectiveCalendar.weekdaySymbols[max(min(value, 6), 0)]
}

private func reminderText(_ value: Int) -> String {
    if value == 0 { return appLocalized("Same day") }
    if value == 1 { return appLocalized("1 day before") }
    return appLocalizedValue("\(value) days before")
}

private func siteRotationSummary(_ sites: [String]) -> String {
    let normalized = InjectionSiteRotation.normalizedPreferredSites(sites)
    if normalized.count == InjectionSiteRotation.allSites.count {
        return appLocalized("All 6 sites")
    }
    if normalized.count <= 2 {
        return normalized.map { InjectionSiteRotation.localizedDisplayName(for: $0) }.joined(separator: ", ")
    }
    return appLocalizedValue("\(normalized.count) sites")
}

private func themeText(_ theme: String) -> String {
    switch theme.lowercased() {
    case "light":
        return appLocalized("Light")
    case "dark":
        return appLocalized("Dark")
    default:
        return appLocalized("System")
    }
}

private func appearanceIcon(_ theme: String) -> String {
    switch theme.lowercased() {
    case "light":
        return "sun.max.fill"
    case "dark":
        return "moon.fill"
    default:
        return "iphone"
    }
}

private func positiveDecimal(_ value: String) -> Double? {
    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: ".")
    guard let parsed = Double(normalized), parsed > 0 else { return nil }
    return parsed
}
