import SwiftData
import SwiftUI

struct JabsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [TrackerProfile]
    let snapshot: DashboardSnapshot
    /// Raised by system-surface deep links (`gaurava://add-injection` or the
    /// Live Activity's `gaurava://jab-confirm`) to present the prefilled Add
    /// Injection sheet.
    /// Optional binding so other call sites can construct JabsView unchanged.
    var presentAddInjection: Binding<Bool>?
    @State private var showingAddInjection = false

    init(snapshot: DashboardSnapshot, presentAddInjection: Binding<Bool>? = nil) {
        self.snapshot = snapshot
        self.presentAddInjection = presentAddInjection
    }
    @State private var editingInjection: InjectionSnapshot?
    @State private var deleteCandidate: InjectionSnapshot?
    @State private var showDeleteConfirmation = false

    var body: some View {
        AppScreen(title: "Jabs", ambientTint: AppTheme.medication) {
            if snapshot.isTreatmentPaused {
                PausedTreatmentCard(startedAt: snapshot.activePauseStartedAt)
            } else if snapshot.scheduleState.needsConfirmation {
                // On treatment, but the latest dose is stale or unconfirmed. Ask
                // for the most recent dose instead of a giant overdue count.
                EmptyStateCard(
                    title: "Confirm your recent dose",
                    message: "Add your most recent injection and Gaurava picks your schedule back up — no overdue, no guesswork.",
                    systemImage: AppSymbol.Health.injection,
                    tint: AppTheme.medication,
                    actionTitle: "Add most recent dose",
                    actionSystemImage: AppSymbol.Action.add,
                    action: showAddInjection,
                    actionIdentifier: "jabsConfirmRecentDose"
                )
            } else if let nextDue = snapshot.nextInjectionDate {
                NextDueCard(
                    nextDue: nextDue,
                    daysUntil: snapshot.nextInjectionDayCount,
                    currentDose: snapshot.profile.plannedDoseMg ?? orderedInjections.first?.doseMg,
                    suggestedSite: snapshot.suggestedInjectionSite
                )
                if snapshot.injections.isEmpty {
                    // Already-going (bucket C): a confirmed dose drives the
                    // countdown, but nothing is logged yet. Invite the first log and
                    // offer a quiet backfill so the tab is more than a lone counter.
                    LogJabPromptCard(onLog: showAddInjection, onBackfill: showAddInjection)
                }
            } else if let projected = snapshot.projectedNextInjectionDate,
                      injectionWeekdayName(snapshot.profile.preferredInjectionDay) != nil {
                // Getting-ready (bucket B): one anticipation card — the planned
                // first jab AND the log CTA together — instead of a muted
                // provisional card stacked over a separate "No jabs logged yet".
                FirstJabAnticipationCard(date: projected, action: showAddInjection)
            } else {
                // Blank slate (bucket A): no weekday plan yet. The empty state
                // carries the CTA, and a one-line purpose footnote below it makes
                // the half-empty screen read as deliberate.
                EmptyStateCard(
                    title: "No jabs logged yet",
                    message: "Log each injection after it happens to build your treatment timeline.",
                    systemImage: AppSymbol.Health.injection,
                    tint: AppTheme.medication,
                    actionTitle: "Log first injection",
                    actionSystemImage: AppSymbol.Action.add,
                    action: showAddInjection,
                    actionIdentifier: "jabsLogFirstInjection"
                )
                Text(appLocalized("Your dose history builds here."))
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, AppSpacing.xs)
                    .accessibilityIdentifier("jabsPurposeFootnote")
            }

            if let last = orderedInjections.first {
                LastDoseStrip(last: last)
            }

            if let plannedDose = snapshot.profile.plannedDoseMg,
               let lastDose = orderedInjections.first?.doseMg,
               plannedDose != lastDose {
                PlannedDoseCard(currentDose: plannedDose, lastLoggedDose: lastDose)
            }

            // The stat strip is meaningless with zero jabs ("0 / Not set /
            // <1 wk"); render it only once at least one injection exists, matching
            // the history-list guard below. One quiet card with internal dividers
            // instead of three floating boxes — the hero above stays the loudest
            // surface on the screen.
            if !snapshot.injections.isEmpty {
                HealthCard(tint: AppTheme.medication, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
                    HStack(alignment: .top, spacing: 0) {
                        // Plain facts wear ink, not the color salad they used to
                        // (orange/blue/teal values competed with the hero); the
                        // dose-color ramp keeps its meaning in the history
                        // timeline where the progression actually encodes it.
                        JabStatColumn(
                            title: "Total",
                            value: "\(snapshot.injections.count)",
                            subtitle: "jabs",
                            metricIdentifier: "jabs-total-count"
                        )
                        Divider().overlay(AppTheme.stroke)
                        JabStatColumn(
                            title: "Current",
                            value: doseText(currentDose),
                            subtitle: nil,
                            metricIdentifier: "jabs-current-dose"
                        )
                        Divider().overlay(AppTheme.stroke)
                        JabStatColumn(
                            title: "On dose",
                            value: weeksOnDoseText(weeksOnCurrentDose),
                            subtitle: doseText(currentDose),
                            metricIdentifier: "jabs-on-dose"
                        )
                    }
                }
            }

            let historyItems = Array(orderedInjections.enumerated())
            if !historyItems.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeader(title: "Injection history")

                    ForEach(historyItems, id: \.element.id) { index, injection in
                        let isLastTimelineRow = index == orderedInjections.count - 1
                        Button {
                            editingInjection = injection
                        } label: {
                            InjectionTimelineRow(
                                injection: injection,
                                weekNumber: weekNumber(for: injection.injectionDate),
                                isDoseChange: isDoseChange(at: index),
                                isFirstInjection: isLastTimelineRow,
                                isLastTimelineRow: isLastTimelineRow,
                                nextDose: orderedInjections.indices.contains(index + 1)
                                    ? orderedInjections[index + 1].doseMg
                                    : nil
                            )
                        }
                        .buttonStyle(.plain)
                        .gentleScrollTransition()
                        .contextMenu {
                            Button("Edit", systemImage: AppSymbol.Action.edit) {
                                editingInjection = injection
                            }
                            Button("Delete", systemImage: AppSymbol.Action.delete, role: .destructive) {
                                deleteCandidate = injection
                                showDeleteConfirmation = true
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            Button("Add injection", systemImage: AppSymbol.Action.add, action: showAddInjection)
                .accessibilityLabel(appLocalized("Add injection"))
                .accessibilityIdentifier("jabsAddInjection")
        }
        .sheet(isPresented: $showingAddInjection) {
            // Large-only: the first-jab flow can add a medication card, and a
            // medium detent let those cards crowd the title and hide Save. The
            // pinned bottom Save bar plus a large sheet keeps everything reachable.
            AddInjectionSheet(snapshot: snapshot, onSave: addInjection)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingInjection) { injection in
            InjectionEditorSheet(
                injection: injection,
                medication: snapshot.profile.medication ?? Medication.inferred(fromMg: injection.doseMg),
                siteOptions: InjectionSiteRotation.siteOptions(
                    preferredSites: snapshot.preferences.preferredInjectionSites,
                    including: injection.injectionSite
                ),
                onSave: updateInjection
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete injection?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let deleteCandidate else { return }
                deleteInjection(deleteCandidate)
                self.deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text("This removes the selected injection from your history.")
        }
        .onAppear { consumeConfirmationRequest() }
        .onChange(of: presentAddInjection?.wrappedValue ?? false) { _, requested in
            if requested { consumeConfirmationRequest() }
        }
    }

    /// Present the prefilled Add Injection sheet when a system-surface deep link
    /// asked for it, then clear the request so it does not re-fire. Handles both
    /// warm (onChange) and cold-launch (onAppear) arrivals.
    private func consumeConfirmationRequest() {
        guard presentAddInjection?.wrappedValue == true else { return }
        showingAddInjection = true
        presentAddInjection?.wrappedValue = false
    }

    private var orderedInjections: [InjectionSnapshot] {
        snapshot.injections.sorted { $0.injectionDate > $1.injectionDate }
    }

    private var currentDose: Double? {
        orderedInjections.first?.doseMg ?? snapshot.profile.plannedDoseMg
    }

    private var weeksOnCurrentDose: Int {
        guard let latest = orderedInjections.first else { return 0 }
        let sameDoseDates = orderedInjections.prefix { $0.doseMg == latest.doseMg }.map(\.injectionDate)
        guard let firstAtDose = sameDoseDates.last else { return 0 }
        return Calendar.current.dateComponents([.weekOfYear], from: firstAtDose, to: Date()).weekOfYear ?? 0
    }

    /// Treatment week for a jab, or nil when the start isn't a valid anchor for
    /// it. A real treatment start precedes the jab; if the jab predates the start
    /// (e.g. a backfilled jab against a defaulted "today" start) the week number
    /// would be false, so we hide the chip instead. No schema change — heuristic.
    private func weekNumber(for date: Date) -> Int? {
        let start = snapshot.profile.treatmentStartDate
        guard start <= date else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: date).day ?? 0
        return max((days / 7) + 1, 1)
    }

    private func isDoseChange(at index: Int) -> Bool {
        guard orderedInjections.indices.contains(index + 1) else { return false }
        return orderedInjections[index].doseMg != orderedInjections[index + 1].doseMg
    }

    private func showAddInjection() {
        showingAddInjection = true
    }

    private func ensureProfile() -> TrackerProfile {
        if let existing = profiles.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return existing
        }
        let profile = TrackerProfile()
        modelContext.insert(profile)
        return profile
    }

    private func addInjection(medication: Medication, doseMg: Double, site: String, date: Date, batchNumber: String?, notes: String?) {
        if medication != .tirzepatide || !profiles.isEmpty {
            ensureProfile().applyMedication(medication)
        }

        let injection = InjectionEntry(
            doseMg: doseMg,
            injectionSite: site.trimmingCharacters(in: .whitespacesAndNewlines),
            injectionDate: date,
            timeZoneIdentifier: TimeZone.current.identifier,
            batchNumber: batchNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        modelContext.insert(injection)
        ModelWriteService.save(modelContext)
    }

    private func updateInjection(_ injection: InjectionSnapshot, doseMg: Double, site: String, date: Date, batchNumber: String?, notes: String?) {
        guard let entry = try? modelContext.fetch(FetchDescriptor<InjectionEntry>()).first(where: { $0.id == injection.id }) else {
            return
        }
        entry.doseMg = doseMg
        entry.injectionSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.injectionDate = date
        entry.batchNumber = batchNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        entry.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        entry.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }

    private func deleteInjection(_ injection: InjectionSnapshot) {
        guard let entry = try? modelContext.fetch(FetchDescriptor<InjectionEntry>()).first(where: { $0.id == injection.id }) else {
            return
        }
        modelContext.delete(entry)
        ModelWriteService.save(modelContext)
    }
}

struct AddInjectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: DashboardSnapshot
    let onSave: (Medication, Double, String, Date, String?, String?) -> Void
    @State private var medication: Medication
    @State private var dose: String
    @State private var site: String
    @State private var date = Date()
    @State private var batchNumber = ""
    @State private var notes = ""

    private let siteOptions: [String]

    init(snapshot: DashboardSnapshot, onSave: @escaping (Medication, Double, String, Date, String?, String?) -> Void) {
        self.snapshot = snapshot
        self.onSave = onSave
        let siteOptions = InjectionSiteRotation.siteOptions(preferredSites: snapshot.preferences.preferredInjectionSites)
        self.siteOptions = siteOptions
        let lastDose = snapshot.injections.sorted { $0.injectionDate > $1.injectionDate }.first?.doseMg
        // Form editing default only (never a display claim): the user's medication
        // if known, otherwise inferred from any planned/last dose.
        let medication = snapshot.profile.medication ?? Medication.inferred(fromMg: snapshot.profile.plannedDoseMg ?? lastDose)
        let doseValue = snapshot.profile.plannedDoseMg ?? lastDose ?? medication.starterDose
        _medication = State(initialValue: medication)
        _dose = State(initialValue: doseInputText(doseValue))
        _site = State(initialValue: siteOptions.contains(snapshot.suggestedInjectionSite) ? snapshot.suggestedInjectionSite : siteOptions[0])
    }

    var body: some View {
        InjectionFormShell(title: "Add Injection", tint: AppTheme.medication, saveDisabled: Double(dose) == nil || site.isEmpty, save: save) {
            if showsMedicationConfirmation {
                FirstJabMedicationPicker(selection: $medication)
            }

            InjectionDosePicker(selection: $dose, options: doseOptions)

            Picker("Site", selection: $site) {
                ForEach(siteOptions, id: \.self) { Text(InjectionSiteRotation.localizedDisplayName(for: $0)) }
            }

            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])

            AppTextFieldShell(systemImage: AppSymbol.Field.number, tint: AppTheme.muted) {
                TextField("Batch", text: $batchNumber)
            }

            AppTextFieldShell(systemImage: AppSymbol.Field.note, tint: AppTheme.muted) {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .accessibilityIdentifier("add-injection-sheet")
        .onChange(of: medication) { _, newMedication in
            guard let selectedDose = Double(dose),
                  doseOptionValues(for: newMedication).contains(where: { abs($0 - selectedDose) < 0.001 }) else {
                dose = doseInputText(newMedication.starterDose)
                return
            }
            dose = doseInputText(selectedDose)
        }
    }

    /// Ask which medicine only when we genuinely do not know it yet — not merely
    /// on the first jab. A user who set their medication during onboarding is not
    /// asked again; an unknown-medication user is asked until they confirm one.
    private var showsMedicationConfirmation: Bool {
        snapshot.profile.medication == nil
    }

    private var doseOptions: [String] {
        doseOptionValues(for: medication, including: Double(dose)).map(doseInputText)
    }

    private func save() {
        guard let doseValue = Double(dose) else { return }
        onSave(medication, doseValue, site, date, batchNumber, notes)
        dismiss()
    }
}

private struct FirstJabMedicationPicker: View {
    @Binding var selection: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Medication")
                .font(AppFont.label)
                .foregroundStyle(AppTheme.muted)

            HStack(spacing: AppSpacing.md) {
                ForEach(Medication.allCases) { medication in
                    Button {
                        selection = medication
                    } label: {
                        FirstJabMedicationButton(
                            medication: medication,
                            isSelected: selection == medication
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("first-jab-medication-\(medication.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("first-jab-medication-picker")
    }
}

private struct FirstJabMedicationButton: View {
    let medication: Medication
    let isSelected: Bool

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: isSelected ? AppSymbol.Status.selectedCircle : AppSymbol.Status.unselectedCircle)
                .foregroundStyle(isSelected ? AppTheme.medication : AppTheme.muted)
            Text(appLocalized(medication.displayName))
                .font(AppFont.bodyStrong)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(AppType.minScale)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.vertical, AppSpacing.sm)
        .background(isSelected ? AppTheme.medication.opacity(0.12) : AppTheme.cardElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(isSelected ? AppTheme.medication.opacity(0.45) : AppTheme.stroke, lineWidth: 1)
        )
    }
}

private struct InjectionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let injection: InjectionSnapshot
    let siteOptions: [String]
    let onSave: (InjectionSnapshot, Double, String, Date, String?, String?) -> Void
    @State private var dose: String
    @State private var site: String
    @State private var injectionDate: Date
    @State private var batchNumber: String
    @State private var notes: String

    private let doseOptions: [String]

    init(injection: InjectionSnapshot, medication: Medication, siteOptions: [String], onSave: @escaping (InjectionSnapshot, Double, String, Date, String?, String?) -> Void) {
        self.injection = injection
        self.siteOptions = siteOptions
        self.onSave = onSave
        doseOptions = doseOptionValues(for: medication, including: injection.doseMg).map(doseInputText)
        _dose = State(initialValue: doseInputText(injection.doseMg))
        _site = State(initialValue: injection.injectionSite)
        _injectionDate = State(initialValue: injection.injectionDate)
        _batchNumber = State(initialValue: injection.batchNumber ?? "")
        _notes = State(initialValue: injection.notes ?? "")
    }

    var body: some View {
        InjectionFormShell(title: "Edit Injection", tint: AppTheme.medication, saveDisabled: Double(dose) == nil || site.isEmpty, save: save) {
            InjectionDosePicker(selection: $dose, options: doseOptions)

            Picker("Site", selection: $site) {
                ForEach(siteOptions, id: \.self) { Text(InjectionSiteRotation.localizedDisplayName(for: $0)) }
            }

            DatePicker("Date", selection: $injectionDate, displayedComponents: [.date, .hourAndMinute])

            AppTextFieldShell(systemImage: AppSymbol.Field.number, tint: AppTheme.muted) {
                TextField("Batch", text: $batchNumber)
            }

            AppTextFieldShell(systemImage: AppSymbol.Field.note, tint: AppTheme.muted) {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .accessibilityIdentifier("edit-injection-sheet")
    }

    private func save() {
        guard let doseValue = Double(dose) else { return }
        onSave(injection, doseValue, site, injectionDate, batchNumber, notes)
        dismiss()
    }
}

private struct InjectionDosePicker: View {
    @Binding var selection: String
    let options: [String]

    private let columns = [
        GridItem(.flexible(), spacing: AppSpacing.md),
        GridItem(.flexible(), spacing: AppSpacing.md),
        GridItem(.flexible(), spacing: AppSpacing.md)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Dose")
                .font(AppFont.label)
                .foregroundStyle(AppTheme.muted)

            LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(appLocalizedValue("\(option) mg"))
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(selection == option ? AppTheme.accentForeground : AppTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(AppType.minScale)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .padding(.horizontal, AppSpacing.sm)
                            .background(
                                selection == option ? AppTheme.medication : AppTheme.cardElevated.opacity(0.9),
                                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                    .stroke(selection == option ? AppTheme.medication.opacity(0.65) : AppTheme.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appLocalizedValue("\(option) mg"))
                }
            }
        }
    }
}

private struct InjectionFormShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let tint: Color
    let saveDisabled: Bool
    let save: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        Label("Injection", systemImage: AppSymbol.Health.injection)
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(tint)

                        content
                    }
                    .accessibilityIdentifier("addInjectionFormSection")
                }
                .padding(AppSpacing.xl)
            }
            .background(AppBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(appLocalized(title))
            .navigationBarTitleDisplayMode(.inline)
            // Save is pinned in a bottom safe-area bar so it can never scroll out
            // of reach behind the form content (a P0 fix from the onboarding plan).
            .safeAreaInset(edge: .bottom) {
                SheetActionButton(title: "Save", systemImage: AppSymbol.Action.save, tint: AppTheme.primary, action: save)
                    .disabled(saveDisabled)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.lg)
                    .background(.bar)
                    .accessibilityIdentifier("addInjectionPinnedSave")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

private struct PlannedDoseCard: View {
    let currentDose: Double
    let lastLoggedDose: Double

    var body: some View {
        HealthCard(tint: AppTheme.medication, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: AppSymbol.Health.dose)
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.medication)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.medication.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Planned dose")
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.medication)
                        Text(appLocalizedValue("\(doseText(currentDose)) next"))
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.ink)
                        Text(appLocalizedValue("Last jab was \(doseText(lastLoggedDose))"))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
            }
        }
    }
}

/// Getting-ready (bucket B) Jabs hero: the planned first jab and the log CTA in
/// one card, replacing a muted provisional card stacked over a separate empty
/// state. Calm medication tint, no countdown — there is no confirmed dose yet.
private struct FirstJabAnticipationCard: View {
    let date: Date
    let action: () -> Void

    var body: some View {
        HealthCard(tint: AppTheme.medication, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .center, spacing: AppSpacing.lg) {
                    Image(systemName: AppSymbol.Health.schedule)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.medication)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.medication.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(appLocalized("First jab"))
                            .font(AppFont.cardTitle)
                            .foregroundStyle(AppTheme.ink)
                        Text(date.appFormatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(AppTheme.muted)
                        Text(appLocalized("Log it after your first dose."))
                            .font(AppFont.label)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    Spacer(minLength: 6)
                }

                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: AppSymbol.Action.add)
                        Text(appLocalized("Log first jab"))
                    }
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.accentForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppTheme.medication, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("jabsLogFirstInjection")
            }
        }
        .accessibilityIdentifier("jabsFirstJabAnticipation")
    }
}

/// Already-going (bucket C) helper shown under the live countdown when a confirmed
/// dose anchors the schedule but no jab has been logged yet: invites the first log
/// and offers a quiet backfill path, so the tab is more than a lone countdown.
private struct LogJabPromptCard: View {
    let onLog: () -> Void
    let onBackfill: () -> Void

    var body: some View {
        HealthCard(tint: AppTheme.medication, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(appLocalized("Log each jab to build your history"))
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AppSpacing.lg) {
                    Button(action: onLog) {
                        HStack(spacing: 8) {
                            Image(systemName: AppSymbol.Action.add)
                            Text(appLocalized("Log a jab"))
                        }
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.accentForeground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AppTheme.medication, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("jabsLogJab")

                    Button(action: onBackfill) {
                        HStack(spacing: 4) {
                            Text(appLocalized("Add past jabs"))
                            Image(systemName: AppSymbol.Action.disclosure)
                                .font(.caption2.weight(.bold))
                        }
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.medication)
                    }
                    .buttonStyle(AppPressableButtonStyle())
                    .accessibilityIdentifier("jabsAddPastJabs")
                }
            }
        }
    }
}

private struct NextDueCard: View {
    let nextDue: Date
    let daysUntil: Int?
    let currentDose: Double?
    let suggestedSite: String

    // Mirrors the Summary/Results hero grammar: eyebrow, ONE display numeral in
    // ink on the left (the countdown — the thing you actually glance for), one
    // muted support line carrying date · dose · site, and a single tinted status
    // block on the right (the only color in the card, so urgency reads
    // instantly when it flips to amber/rose).
    var body: some View {
        let style = nextDueStyle(daysUntil)
        HeroCard(tint: style.tint, padding: AppSpacing.xl) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Next injection")
                        .font(AppFont.label)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.muted)
                    Text(appLocalized(countdownDisplayText(daysUntil)))
                        .font(AppFont.display)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(AppType.minScaleTight)
                        .contentTransition(.numericText())
                    Text(supportLine)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(AppType.minScale)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppSpacing.md)

                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text("Status")
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.muted)
                    Label(appLocalized(style.label), systemImage: style.image)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(style.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(AppType.minScale)
                }
            }
        }
        .accessibilityElement(children: .combine)
        // Stable hook: the card combines its children, so "Next injection" is not a
        // standalone static text — tests assert the live countdown by this id.
        .accessibilityIdentifier("jabsNextDueCard")
    }

    private var supportLine: String {
        let date = nextDue.appFormatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let site = InjectionSiteRotation.localizedDisplayName(for: suggestedSite)
        return appLocalizedValue("\(date) · \(doseText(currentDose)) · \(site)")
    }
}

private struct LastDoseStrip: View {
    let last: InjectionSnapshot

    var body: some View {
        HealthCard(tint: doseColor(last.doseMg), cornerRadius: AppRadius.control, padding: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Circle()
                    .fill(doseColor(last.doseMg))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)

                Text("Last")
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.ink)
                Text(appLocalizedValue("\(last.injectionDate.appFormatted(.dateTime.month(.abbreviated).day())) · \(doseText(last.doseMg)) · \(InjectionSiteRotation.localizedDisplayName(for: last.injectionSite))"))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScale)

                Spacer(minLength: 8)

                Text(daysAgoText(daysAgo(last.injectionDate)))
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
        }
    }
}

/// One column of the jab stat strip. Mirrors MetricTile's accessibility contract
/// (combined element, "title, value" label, stable identifier) so the UI tests
/// keyed to jabs-total-count / jabs-current-dose / jabs-on-dose keep passing.
private struct JabStatColumn: View {
    let title: String
    let value: String
    let subtitle: String?
    let metricIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(appLocalized(title))
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(AppType.minScale)
            Text(appLocalized(value))
                .font(AppFont.metricValue)
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(AppType.minScaleTight)
                .contentTransition(.numericText())
            if let subtitle {
                Text(appLocalized(subtitle))
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScale)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appLocalized(title)), \(appLocalized(value))")
        .accessibilityIdentifier(metricIdentifier)
    }
}

private struct InjectionTimelineRow: View {
    let injection: InjectionSnapshot
    let weekNumber: Int?
    let isDoseChange: Bool
    let isFirstInjection: Bool
    let isLastTimelineRow: Bool
    /// Dose of the next-older jab below this row, so the rail connector can run
    /// a gradient from this dose's color into the next one (the dose ramp made
    /// visible along the timeline).
    var nextDose: Double?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            TimelineRail(
                tint: doseColor(injection.doseMg),
                nextTint: doseColor(nextDose ?? injection.doseMg),
                showsConnector: !isLastTimelineRow
            )
                .frame(width: 24)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(injection.injectionDate.appFormatted(.dateTime.month(.abbreviated).day()))
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)

                    if isDoseChange {
                        StatusPill(text: "Dose change", systemImage: AppSymbol.Action.doseChange, tint: AppTheme.success)
                    } else if isFirstInjection {
                        StatusPill(text: "First jab", systemImage: AppSymbol.Action.firstJab, tint: AppTheme.medication)
                    }

                    Spacer(minLength: 6)

                    Text(doseText(injection.doseMg))
                        .font(AppFont.metricValue)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                }

                Text(weekNumber.map { appLocalizedValue("\(InjectionSiteRotation.localizedDisplayName(for: injection.injectionSite)) · Week \($0)") } ?? InjectionSiteRotation.localizedDisplayName(for: injection.injectionSite))
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
            .padding(.bottom, isLastTimelineRow ? 0 : 14)
        }
        .frame(minHeight: 56, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct TimelineRail: View {
    let tint: Color
    var nextTint: Color?
    let showsConnector: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(tint.gradient)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(AppTheme.healthSurface, lineWidth: 3))
                .shadow(color: tint.opacity(0.35), radius: 5, x: 0, y: 2)
                .accessibilityHidden(true)

            if showsConnector {
                // The dose ramp made visible: the connector runs this jab's dose
                // color into the next (older) one, so titration steps read as a
                // gradient seam instead of a flat grey wire.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.55), (nextTint ?? tint).opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .frame(minHeight: 50)
                    .padding(.top, AppSpacing.xs)
                    .accessibilityHidden(true)
            }
        }
    }
}

private func weeksOnDoseText(_ weeks: Int) -> String {
    if weeks <= 0 { return appLocalized("<1 wk") }
    if weeks == 1 { return appLocalized("1 wk") }
    return appLocalizedValue("\(weeks) wks")
}

private func daysAgo(_ date: Date) -> Int {
    Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day ?? 0
}

private func daysAgoText(_ days: Int) -> String {
    if days == 0 { return appLocalized("Today") }
    if days == 1 { return appLocalized("1d ago") }
    return appLocalizedValue("\(days)d ago")
}

private func nextDueStyle(_ days: Int?) -> (label: String, image: String, tint: Color) {
    guard let days else { return (appLocalized("Not scheduled"), AppSymbol.Status.notScheduled, AppTheme.muted) }
    if days < 0 { return (appLocalized("Needs logging"), AppSymbol.Status.needsLogging, AppTheme.rose) }
    if days == 0 { return (appLocalized("Ready"), AppSymbol.Status.readyToLog, AppTheme.success) }
    if days <= 2 { return (appLocalized("Coming up"), AppSymbol.Status.comingUp, AppTheme.amber) }
    return (appLocalized("On track"), AppSymbol.Status.onTrack, AppTheme.success)
}

/// The hero numeral. Calm and literal (no idiom, translates cleanly): a count
/// of days forward, "Today" on the day, and a days-ago count once it is past —
/// the tinted status block carries the "needs logging" urgency.
private func countdownDisplayText(_ days: Int?) -> String {
    guard let days else { return "--" }
    if days < 0 {
        return abs(days) == 1 ? appLocalized("1 day ago") : appLocalizedValue("\(abs(days)) days ago")
    }
    if days == 0 { return appLocalized("Today") }
    return days == 1 ? appLocalized("1 day") : appLocalizedValue("\(days) days")
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
