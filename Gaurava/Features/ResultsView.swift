import Charts
import SwiftData
import SwiftUI

struct ResultsView: View {
    @Environment(\.modelContext) private var modelContext
    let snapshot: DashboardSnapshot
    @State private var selectedPeriod: ResultsPeriod = .all
    @State private var showingAddWeight = false
    @State private var editingWeight: WeightSnapshot?
    @State private var deleteCandidate: WeightSnapshot?
    @State private var showDeleteConfirmation = false
    @State private var showingPersonalInfo = false

    var body: some View {
        AppScreen(title: "Trends", ambientTint: AppTheme.blue) {
            let weights = filteredWeights
            let injections = filteredInjections
            // The 1M/3M/6M/All selector scopes a chart; with fewer than two
            // weights there is no chart to scope, so hide it rather than float a
            // dead control over an empty card.
            if snapshot.weights.count >= 2 {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(ResultsPeriod.allCases) { period in
                        Text(appLocalized(period.label)).tag(period)
                    }
                }
                .pickerStyle(.segmented)
            }
            if weights.count >= 2, let stats = resultStats(weights, profile: snapshot.profile) {
                let phases = dosePhases(weights: weights, injections: injections)
                ResultsChangeHero(stats: stats)
                ResultsOverviewGrid(stats: stats, onAddHeight: { showingPersonalInfo = true })
                ResultsReferenceChart(
                    weights: weights,
                    injections: injections,
                    goalWeightKg: snapshot.profile.goalWeightKg > 0 ? snapshot.profile.goalWeightKg : nil,
                    dosePhases: phases
                )
                ResultsDosePhasesSection(phases: phases)
                ResultsInsightsCard(stats: stats, doseInfo: doseInfo(injections))
                WeightHistorySection(
                    weights: weights,
                    edit: { editingWeight = $0 },
                    delete: {
                        deleteCandidate = $0
                        showDeleteConfirmation = true
                    }
                )
            } else if let single = weights.first {
                // One weight: a real checkpoint exists, but change / percent /
                // trend / weekly-average need two points. Show the value and an
                // honest "add another" prompt instead of "0.0 kg / 0.0%".
                SingleWeightState(weight: single, profile: snapshot.profile, onAddHeight: { showingPersonalInfo = true })
                WeightHistorySection(
                    weights: weights,
                    edit: { editingWeight = $0 },
                    delete: {
                        deleteCandidate = $0
                        showDeleteConfirmation = true
                    }
                )
            } else {
                // Zero weights (reference empty state). Acknowledge an entered goal
                // when one exists — never print "Goal 0 kg".
                EmptyStateCard(
                    title: "No weight entries yet",
                    message: snapshot.profile.goalWeightKg > 0
                        ? appLocalizedValue("Goal \(weightText(snapshot.profile.goalWeightKg)) · add a weight to start charting.")
                        : "Add a weight whenever you want a checkpoint.",
                    systemImage: AppSymbol.Health.weight,
                    tint: AppTheme.blue,
                    actionTitle: "Add weight",
                    actionSystemImage: AppSymbol.Action.add,
                    action: showAddWeight,
                    actionIdentifier: "resultsAddWeight"
                )
                Text(appLocalized("Your weight trend builds here."))
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, AppSpacing.xs)
                    .accessibilityIdentifier("resultsPurposeFootnote")
            }
        }
        .toolbar {
            Button("Add weight", systemImage: AppSymbol.Action.add, action: showAddWeight)
                .accessibilityLabel(appLocalized("Add weight"))
        }
        .sheet(isPresented: $showingAddWeight) {
            AddWeightSheet(snapshot: snapshot, onSave: addWeight)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingWeight) { weight in
            WeightEditorSheet(weight: weight, onSave: updateWeight)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPersonalInfo) {
            // Reuses Care's age + gender + height editor so BMI is unlocked from the
            // same form. Saving refreshes the @Query-derived snapshot, so the BMI
            // tile replaces this prompt live without a reload.
            PersonalInfoEditorSheet(snapshot: snapshot, save: savePersonalInfo)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete weight entry?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let deleteCandidate else { return }
                deleteWeight(deleteCandidate)
                self.deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text("This removes the selected weight entry from your trend.")
        }
    }

    private var filteredWeights: [WeightSnapshot] {
        let ordered = snapshot.weights.sorted { $0.recordedAt > $1.recordedAt }
        guard selectedPeriod != .all,
              let cutoff = Calendar.current.date(byAdding: .month, value: -selectedPeriod.months, to: Date())
        else {
            return ordered
        }
        return ordered.filter { $0.recordedAt >= cutoff }
    }

    private var filteredInjections: [InjectionSnapshot] {
        guard selectedPeriod != .all,
              let cutoff = Calendar.current.date(byAdding: .month, value: -selectedPeriod.months, to: Date())
        else {
            return snapshot.injections
        }
        return snapshot.injections.filter { $0.injectionDate >= cutoff }
    }

    private func showAddWeight() {
        showingAddWeight = true
    }

    private func dosePhases(weights: [WeightSnapshot], injections: [InjectionSnapshot]) -> [DosePhase] {
        DosePhaseMath.phases(
            injections: injections.map { (doseMg: $0.doseMg, injectionDate: $0.injectionDate) },
            weights: weights.map { (weightKg: $0.weightKg, recordedAt: $0.recordedAt) },
            pauses: snapshot.pauses.map { (start: $0.startedAt, end: $0.endedAt) }
        )
    }

    private func addWeight(weightKg: Double, recordedAt: Date, notes: String?) {
        let entry = WeightEntry(
            weightKg: weightKg,
            recordedAt: recordedAt,
            timeZoneIdentifier: TimeZone.current.identifier,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(entry)
        ModelWriteService.save(modelContext)
    }

    private func updateWeight(_ weight: WeightSnapshot, weightKg: Double, recordedAt: Date, notes: String?) {
        guard let entry = try? modelContext.fetch(FetchDescriptor<WeightEntry>()).first(where: { $0.id == weight.id }) else {
            return
        }
        entry.weightKg = weightKg
        entry.recordedAt = recordedAt
        entry.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }

    private func deleteWeight(_ weight: WeightSnapshot) {
        guard let entry = try? modelContext.fetch(FetchDescriptor<WeightEntry>()).first(where: { $0.id == weight.id }) else {
            return
        }
        modelContext.delete(entry)
        ModelWriteService.save(modelContext)
    }

    /// Mirrors SettingsView.savePersonalInfo: update the most-recent profile (or
    /// insert one) with the age/gender/height from the reused editor. Writing here
    /// keeps the BMI unlock self-contained on Trends.
    private func savePersonalInfo(age: Int, gender: String, heightCm: Double) {
        let existing = (try? modelContext.fetch(FetchDescriptor<TrackerProfile>())) ?? []
        let profile: TrackerProfile
        if let latest = existing.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            profile = latest
        } else {
            profile = TrackerProfile()
            modelContext.insert(profile)
        }
        profile.age = age
        profile.gender = gender
        profile.heightCm = heightCm
        profile.updatedAt = Date()
        ModelWriteService.save(modelContext)
    }
}

struct AddWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: DashboardSnapshot
    let onSave: (Double, Date, String?) -> Void
    @State private var weightText: String
    @State private var recordedAt = Date()
    @State private var notes = ""
    @State private var errorMessage: String?

    init(snapshot: DashboardSnapshot, onSave: @escaping (Double, Date, String?) -> Void) {
        self.snapshot = snapshot
        self.onSave = onSave
        _weightText = State(initialValue: "")
    }

    var body: some View {
        WeightFormShell(title: "Add Weight", errorMessage: errorMessage, saveDisabled: parsedWeight == nil, save: save) {
            AppTextFieldShell(systemImage: AppSymbol.Field.number, tint: AppTheme.blue) {
                TextField("Weight kg", text: $weightText)
                    .keyboardType(.decimalPad)
            }

            DatePicker("Recorded", selection: $recordedAt, displayedComponents: [.date, .hourAndMinute])

            AppTextFieldShell(systemImage: AppSymbol.Field.note, tint: AppTheme.muted) {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .accessibilityIdentifier("add-weight-sheet")
    }

    private func save() {
        guard let weight = parsedWeight else {
            errorMessage = "Enter a valid weight."
            return
        }
        onSave(weight, recordedAt, cleanedNotes)
        dismiss()
    }

    private var parsedWeight: Double? {
        let normalized = weightText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var cleanedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct WeightEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let weight: WeightSnapshot
    let onSave: (WeightSnapshot, Double, Date, String?) -> Void
    @State private var weightText: String
    @State private var recordedAt: Date
    @State private var notes: String
    @State private var errorMessage: String?

    init(weight: WeightSnapshot, onSave: @escaping (WeightSnapshot, Double, Date, String?) -> Void) {
        self.weight = weight
        self.onSave = onSave
        _weightText = State(initialValue: weight.weightKg.formatted(.number.precision(.fractionLength(0...1))))
        _recordedAt = State(initialValue: weight.recordedAt)
        _notes = State(initialValue: weight.notes ?? "")
    }

    var body: some View {
        WeightFormShell(title: "Edit Weight", errorMessage: errorMessage, saveDisabled: parsedWeight == nil, save: save) {
            AppTextFieldShell(systemImage: AppSymbol.Field.number, tint: AppTheme.blue) {
                TextField("Weight kg", text: $weightText)
                    .keyboardType(.decimalPad)
            }

            DatePicker("Recorded", selection: $recordedAt, displayedComponents: [.date, .hourAndMinute])

            AppTextFieldShell(systemImage: AppSymbol.Field.note, tint: AppTheme.muted) {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }

    private func save() {
        guard let weightValue = parsedWeight else {
            errorMessage = "Enter a valid weight."
            return
        }
        onSave(weight, weightValue, recordedAt, cleanedNotes)
        dismiss()
    }

    private var parsedWeight: Double? {
        let normalized = weightText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var cleanedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct WeightFormShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let errorMessage: String?
    let saveDisabled: Bool
    let save: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HealthCard(tint: AppTheme.blue, cornerRadius: AppRadius.hero, padding: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        Label("Weight", systemImage: AppSymbol.Health.weight)
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(AppTheme.blue)

                        content

                        if let errorMessage {
                            Text(appLocalized(errorMessage))
                                .font(AppFont.body)
                                .foregroundStyle(AppTheme.rose)
                        }

                        SheetActionButton(title: "Save", systemImage: AppSymbol.Action.save, tint: AppTheme.primary, action: save)
                            .disabled(saveDisabled)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.xl)
            .background(AppBackground())
            .navigationTitle(appLocalized(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

private enum ResultsPeriod: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneMonth: "1M"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .all: "All"
        }
    }

    var months: Int {
        switch self {
        case .oneMonth: 1
        case .threeMonths: 3
        case .sixMonths: 6
        case .all: 0
        }
    }
}

private struct ResultsStats {
    let current: Double
    let starting: Double
    let change: Double
    let percentChange: Double
    let goal: Double?
    let toGoal: Double?
    let progressPercent: Double?
    let bmi: Double?
    let weeklyAverage: Double?
    let totalWeeks: Int
}

/// The one loud surface on Results: the period's change as a display numeral
/// with the percent-from-start alongside. Everything below stays quiet.
private struct ResultsChangeHero: View {
    let stats: ResultsStats

    private var changeTint: Color {
        stats.change <= 0 ? AppTheme.primary : AppTheme.rose
    }

    var body: some View {
        HeroCard(tint: changeTint, padding: AppSpacing.xl) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Total change")
                        .font(AppFont.label)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.muted)
                    Text(signedWeightText(stats.change))
                        .font(AppFont.display)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(AppType.minScaleTight)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: AppSpacing.md)

                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text("Percent")
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.muted)
                    Text(appLocalizedValue("\(stats.percentChange.formatted(.number.precision(.fractionLength(1))))%"))
                        .font(AppFont.metricValue)
                        .monospacedDigit()
                        .foregroundStyle(changeTint)
                        .contentTransition(.numericText())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appLocalized("Total change")), \(signedWeightText(stats.change))")
        .accessibilityIdentifier("results-total-change")
    }
}

private struct ResultsOverviewGrid: View {
    let stats: ResultsStats
    let onAddHeight: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 2)

    var body: some View {
        // Change + percent live in the hero above; the grid carries only the
        // quiet reference numbers.
        LazyVGrid(columns: columns, spacing: AppSpacing.md) {
            ResultsOverviewTile(title: "Weight", value: weightText(stats.current), systemImage: AppSymbol.Health.currentWeight, tint: AppTheme.blue)
            // BMI when height is set; otherwise a tappable invite tile in the same
            // slot. Filling the slot keeps the 2x2 grid balanced (no empty cell)
            // AND offers the one tap that unlocks BMI.
            if let bmi = stats.bmi {
                ResultsOverviewTile(title: "BMI", value: bmi.formatted(.number.precision(.fractionLength(1))), systemImage: AppSymbol.Health.bmi, tint: AppTheme.primary)
            } else {
                BMIPromptTile(onTap: onAddHeight)
            }
            ResultsOverviewTile(title: "Weekly avg", value: stats.weeklyAverage.map { appLocalizedValue("\($0.formatted(.number.precision(.fractionLength(2)))) kg/wk") } ?? appLocalized("Not set"), systemImage: AppSymbol.Health.weeklyAverage, tint: AppTheme.medication)
            ResultsOverviewTile(title: "To goal", value: toGoalText, systemImage: AppSymbol.Health.goal, tint: AppTheme.success)
        }
    }

    private var toGoalText: String {
        guard let toGoal = stats.toGoal else { return appLocalized("Not set") }
        if toGoal <= 0 { return appLocalized("Reached") }
        return weightText(toGoal)
    }
}

private struct ResultsOverviewTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ThemedMiniSurface(tint: tint, minHeight: 82) { surface in
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(surface.iconForeground)
                        .frame(width: 16)
                    Text(appLocalized(title))
                        .font(AppFont.micro)
                        .foregroundStyle(surface.secondaryForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(AppType.minScaleTight)
                }

                Text(appLocalized(value))
                    .font(AppFont.metricValue)
                    .foregroundStyle(surface.foreground)
                    .lineLimit(1)
                    // Intentionally tighter than AppType.minScaleTight: long localized
                    // metric values must fit one line in this narrow stat tile.
                    .minimumScaleFactor(0.54)
            }
        }
    }
}

/// Invite tile shown in the BMI slot when height is unset. Keeps a metric tile's
/// footprint so the overview grid stays balanced (no empty cell), but reads as a
/// metric "waiting for one more detail": a mint "Add height" call-to-action that
/// opens the age + height editor. Once a height exists the real BMI tile takes the
/// slot and this disappears.
private struct BMIPromptTile: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ThemedMiniSurface(tint: AppTheme.primary, minHeight: 82) { surface in
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: AppSymbol.Health.bmi)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(surface.iconForeground)
                            .frame(width: 16)
                        Text(appLocalized("BMI"))
                            .font(AppFont.micro)
                            .foregroundStyle(surface.secondaryForeground)
                            .lineLimit(1)
                            .minimumScaleFactor(AppType.minScaleTight)
                    }

                    HStack(spacing: AppSpacing.xs) {
                        Text(appLocalized("Add height"))
                            .font(AppFont.metricValue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.54)
                        Image(systemName: AppSymbol.Action.disclosure)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(surface.iconForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appLocalized("Add height"))
        .accessibilityHint(appLocalized("Add your height to see your BMI."))
        .accessibilityIdentifier("results-add-height-prompt")
    }
}

/// One-weight state: a real checkpoint exists but trend math needs two points.
/// Shows the value plus an honest "add another weight" prompt, and the facts that
/// ARE valid with a single sample (BMI when height is set, distance to goal).
private struct SingleWeightState: View {
    let weight: WeightSnapshot
    let profile: ProfileSnapshot
    let onAddHeight: () -> Void

    private var bmi: Double? {
        guard profile.heightCm > 0 else { return nil }
        let meters = profile.heightCm / 100
        return (weight.weightKg / (meters * meters) * 10).rounded() / 10
    }

    private var toGoal: Double? {
        profile.goalWeightKg > 0 ? weight.weightKg - profile.goalWeightKg : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HealthCard(tint: AppTheme.blue, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Current weight")
                        .font(AppFont.label)
                        .textCase(.uppercase)
                        .foregroundStyle(AppTheme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                        Text(weight.weightKg.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(.largeTitle, design: .serif, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(AppType.minScaleTight)
                    Text(appLocalized("kg"))
                            .font(AppFont.cardTitle)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Text("Add another weight to see change, percent, trend, and weekly average.")
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // BMI when height is set, otherwise the same invite tile as the grid so
            // a single weigh-in still offers the BMI unlock. To-goal sits beside it
            // when a goal exists.
            HStack(spacing: AppSpacing.md) {
                if let bmi {
                    ResultsOverviewTile(
                        title: "BMI",
                        value: bmi.formatted(.number.precision(.fractionLength(1))),
                        systemImage: AppSymbol.Health.bmi,
                        tint: AppTheme.primary
                    )
                } else {
                    BMIPromptTile(onTap: onAddHeight)
                }
                if let toGoal {
                    ResultsOverviewTile(
                        title: "To goal",
                        value: toGoal <= 0 ? appLocalized("Reached") : weightText(toGoal),
                        systemImage: AppSymbol.Health.goal,
                        tint: AppTheme.success
                    )
                }
            }
        }
        .accessibilityIdentifier("results-single-weight-state")
    }
}

private struct ResultsReferenceChart: View {
    let weights: [WeightSnapshot]
    let injections: [InjectionSnapshot]
    var goalWeightKg: Double?
    var dosePhases: [DosePhase] = []
    @AppStorage("resultsDoseLabelsVisible") private var showDoseLabels = false
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SectionHeader(title: "Weight Trend")
                Text(dateRangeText)
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, AppSpacing.xs)
            }

            if orderedPoints.isEmpty {
                ContentUnavailableView(
                    "No Weight Entries",
                    systemImage: AppSymbol.Health.trend,
                    description: Text("Add your first weight to see the trend.")
                )
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(AppTheme.card.opacity(0.62), in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    doseLegend
                    doseLabelToggle
                }
                .padding(.horizontal, AppSpacing.xs)

                trendChart
                    .frame(height: chartHeight)
                    .padding(.horizontal, -2)

                if let selectedPoint {
                    HStack(spacing: AppSpacing.sm) {
                        Circle()
                            .fill(doseColor(selectedPoint.doseMg))
                            .frame(width: 8, height: 8)
                        Text(selectedPointSummary(selectedPoint))
                            .font(AppFont.label)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.horizontal, AppSpacing.xs)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("results-reference-chart")
    }

    private var trendChart: some View {
        Chart {
            // Dose-phase bands: a quiet wash per contiguous dose run so the
            // journey reads as chapters. Drawn first, under everything else.
            ForEach(phaseBands) { band in
                RectangleMark(
                    xStart: .value("Phase start", band.start),
                    xEnd: .value("Phase end", band.end)
                )
                .foregroundStyle(band.tint.opacity(0.1))
            }

            ForEach(phaseBands.dropFirst()) { band in
                RuleMark(x: .value("Dose change", band.start))
                    .foregroundStyle(band.tint.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            ForEach(monthGridDates, id: \.self) { date in
                RuleMark(x: .value("Month", date))
                    .foregroundStyle(AppTheme.chartGrid)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 6]))
            }

            // Soft weight-blue wash under the trend so the curve reads as a
            // filled journey, not a wire. yStart pins the fill to the visible
            // domain floor — the default baseline is 0 kg, which paints a slab
            // far below the plot because marks outside the domain aren't clipped.
            if orderedPoints.count > 1 {
                ForEach(smoothedTrendSamples) { sample in
                    AreaMark(
                        x: .value("Date", sample.date),
                        yStart: .value("Baseline", yDomain.lowerBound),
                        yEnd: .value("Weight", sample.weightKg)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.blue.opacity(0.22), AppTheme.blue.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }

            // Goal line: shown once the journey is approaching it, so a far-off
            // goal never flattens the working range of the chart.
            if let goal = visibleGoal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(AppTheme.success.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("Goal")
                            .font(AppFont.micro)
                            .foregroundStyle(AppTheme.success)
                    }
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(AppTheme.ink.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            if orderedPoints.count > 1 {
                ForEach(doseTrendSegments) { segment in
                    ForEach(segment.points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weightKg),
                            series: .value("Dose segment", segment.id)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(segment.tint)
                        .lineStyle(StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
                    }
                }
            }

            ForEach(orderedPoints) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Weight", point.weightKg)
                )
                .foregroundStyle(point.id == selectedPoint?.id ? AppTheme.ink : doseColor(point.doseMg))
                .symbolSize(point.id == selectedPoint?.id ? 118 : 66)
            }

            if showDoseLabels {
                ForEach(doseLabels) { label in
                    PointMark(
                        x: .value("Dose label date", label.date),
                        y: .value("Dose label weight", label.weightKg)
                    )
                    .foregroundStyle(.clear)
                    .symbolSize(1)
                    .annotation(
                        position: .top,
                        alignment: .leading,
                        spacing: AppSpacing.xs,
                        overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))
                    ) {
                        DoseBadge(doseMg: label.doseMg, tint: doseColor(label.doseMg))
                            .accessibilityHidden(true)
                    }
                }

                // Per-phase change, pinned just under the plot's top edge at the
                // band midpoint. Same opt-in toggle as the dose badges so the
                // default chart stays quiet.
                ForEach(phaseDeltaLabels) { label in
                    PointMark(
                        x: .value("Phase midpoint", label.date),
                        y: .value("Plot top", yDomain.upperBound)
                    )
                    .foregroundStyle(.clear)
                    .symbolSize(1)
                    .annotation(
                        position: .bottom,
                        spacing: AppSpacing.xs,
                        overflowResolution: .init(x: .fit(to: .plot), y: .disabled)
                    ) {
                        Text(signedWeightText(label.changeKg))
                            .font(AppFont.micro)
                            .monospacedDigit()
                            .foregroundStyle(label.tint)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(AppTheme.card.opacity(0.9), in: Capsule())
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: monthLabelTicks.map(\.date)) { value in
                AxisTick()
                    .foregroundStyle(.clear)
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(monthLabelText(for: date))
                            .font(AppFont.label)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                    .foregroundStyle(AppTheme.chartGrid)
                AxisTick()
                    .foregroundStyle(.clear)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(number.formatted(.number.precision(.fractionLength(0))))kg")
                            .font(AppFont.label)
                            .foregroundStyle(AppTheme.muted.opacity(0.88))
                    }
                }
            }
        }
        .chartXScale(domain: xDomain, range: .plotDimension(startPadding: 8, endPadding: 12))
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .background(AppTheme.card.opacity(0.18))
                .clipped()
        }
                .accessibilityLabel(appLocalized("Weight trend chart"))
                .accessibilityValue(accessibilityTrendSummary)
    }

    private var orderedWeights: [WeightSnapshot] {
        weights.sorted { $0.recordedAt < $1.recordedAt }
    }

    private var orderedPoints: [WeightPoint] {
        orderedWeights.map { weight in
            WeightPoint(
                id: weight.id,
                date: weight.recordedAt,
                weightKg: weight.weightKg,
                doseMg: doseFor(date: weight.recordedAt)
            )
        }
    }

    private var smoothedTrendSamples: [TrendSample] {
        orderedPoints.enumerated().map { index, point in
            let weight: Double
            if index == 0 || index == orderedPoints.count - 1 {
                weight = point.weightKg
            } else {
                let previous = orderedPoints[index - 1]
                let next = orderedPoints[index + 1]
                weight = (previous.weightKg * 0.25) + (point.weightKg * 0.5) + (next.weightKg * 0.25)
            }
            return TrendSample(id: index, date: point.date, weightKg: weight, doseMg: point.doseMg)
        }
    }

    private var doseTrendSegments: [TrendLineSegment] {
        zip(smoothedTrendSamples, smoothedTrendSamples.dropFirst()).enumerated().map { index, pair in
            let start = pair.0
            let end = pair.1
            return TrendLineSegment(
                id: index,
                points: [start, end],
                tint: doseColor(start.doseMg ?? end.doseMg)
            )
        }
    }

    /// Phase bands clamped to the visible domain. Suppressed for a single
    /// phase — tinting the whole plot one color adds noise, not information.
    private var phaseBands: [PhaseBand] {
        guard dosePhases.count >= 2 else { return [] }
        let domain = xDomain
        return dosePhases.compactMap { phase in
            let start = max(phase.start, domain.lowerBound)
            let end = min(phase.end ?? domain.upperBound, domain.upperBound)
            guard start < end else { return nil }
            return PhaseBand(
                id: phase.id,
                start: start,
                end: end,
                tint: doseColor(phase.doseMg),
                changeKg: phase.changeKg
            )
        }
    }

    /// Change labels only for bands wide enough to host one without colliding
    /// with a neighbour's.
    private var phaseDeltaLabels: [PhaseDeltaLabel] {
        let domain = xDomain
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return [] }
        return phaseBands.compactMap { band in
            guard let changeKg = band.changeKg else { return nil }
            let width = band.end.timeIntervalSince(band.start)
            guard width / span >= 0.16 else { return nil }
            return PhaseDeltaLabel(
                id: band.id,
                date: band.start.addingTimeInterval(width / 2),
                changeKg: changeKg,
                tint: band.tint
            )
        }
    }

    private var activeDoses: [Double] {
        Array(Set(orderedPoints.compactMap(\.doseMg))).sorted()
    }

    private var doseLegend: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(appLocalized("Dose color"))
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.muted)
                .accessibilityIdentifier("results-dose-color-legend")
            HStack(spacing: AppSpacing.sm) {
                ForEach(activeDoses, id: \.self) { dose in
                    DoseLegendChip(doseMg: dose, tint: doseColor(dose))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var doseLabelToggle: some View {
        Toggle(isOn: $showDoseLabels) {
            Label(appLocalized("Dose labels"), systemImage: showDoseLabels ? AppSymbol.Action.doseLabelsOn : AppSymbol.Action.doseLabels)
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.muted)
        }
        .toggleStyle(.switch)
        .tint(AppTheme.primary)
        .frame(minHeight: 44)
        .accessibilityHint(appLocalized("Shows or hides dose change labels on the weight chart."))
        .accessibilityIdentifier("results-dose-labels-toggle")
    }

    private var doseLabels: [DoseLabel] {
        var previousDose: Double?
        var labels: [DoseLabel] = []

        for injection in injections.sorted(by: { $0.injectionDate < $1.injectionDate }) {
            guard injection.doseMg != previousDose else { continue }
            previousDose = injection.doseMg
            guard let point = nearestPoint(to: injection.injectionDate) else { continue }
            labels.append(DoseLabel(date: point.date, weightKg: point.weightKg, doseMg: injection.doseMg))
        }

        return labels
    }

    private var monthGridDates: [Date] {
        guard let first = orderedPoints.first?.date, let last = orderedPoints.last?.date else { return [] }
        return ResultsChartScale.monthGridDates(first: first, last: last, domain: xDomain)
    }

    private var monthLabelTicks: [MonthLabelTick] {
        guard let first = orderedPoints.first?.date, let last = orderedPoints.last?.date else { return [] }
        return ResultsChartScale.monthLabelTicks(first: first, last: last, domain: xDomain)
    }

    private func monthLabelText(for date: Date) -> String {
        let tick = monthLabelTicks.first { abs($0.date.timeIntervalSince(date)) < 0.5 }
        return (tick?.monthStart ?? date).appFormatted(.dateTime.month(.abbreviated))
    }

    private var selectedPoint: WeightPoint? {
        guard let selectedDate else { return nil }
        return nearestPoint(to: selectedDate)
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = orderedPoints.first?.date, let last = orderedPoints.last?.date else {
            return Date().addingTimeInterval(-86_400)...Date()
        }
        return ResultsChartScale.xDomain(first: first, last: last)
    }

    /// The goal weight, only once the data has come within striking distance
    /// (6 kg) of it — a far-off goal must not flatten the chart's working range.
    private var visibleGoal: Double? {
        guard let goalWeightKg, let minValue = orderedPoints.map(\.weightKg).min() else { return nil }
        return minValue - goalWeightKg <= 6 ? goalWeightKg : nil
    }

    private var yDomain: ClosedRange<Double> {
        let values = orderedPoints.map(\.weightKg)
        guard let minValue = values.min(), let maxValue = values.max() else { return 0...1 }
        let floorValue = min(minValue, visibleGoal ?? minValue)
        let rawPadding = max(3.0, (maxValue - floorValue) * 0.20)
        let lower = floor((floorValue - rawPadding) / 2) * 2
        let upper = ceil((maxValue + rawPadding) / 2) * 2
        if lower < upper {
            return lower...upper
        }
        return (minValue - 1)...(maxValue + 1)
    }

    private var chartHeight: CGFloat {
        orderedPoints.count > 20 ? 440 : 410
    }

    private var dateRangeText: String {
        guard let first = orderedPoints.first?.date, let last = orderedPoints.last?.date else {
            return appLocalized("No entries")
        }
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .day) {
            return first.appFormatted(.dateTime.month(.abbreviated).day().year())
        }
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .year) {
            return appLocalizedValue("\(shortDate(first)) - \(last.appFormatted(.dateTime.month(.abbreviated).day().year()))")
        }
        return appLocalizedValue("\(first.appFormatted(.dateTime.month(.abbreviated).day().year())) - \(last.appFormatted(.dateTime.month(.abbreviated).day().year()))")
    }

    private var accessibilityTrendSummary: String {
        guard let current = orderedPoints.last else { return appLocalized("No weight entries yet.") }
        let first = orderedPoints.first
        let change = current.weightKg - (first?.weightKg ?? current.weightKg)
        let labelState = showDoseLabels ? appLocalized("on") : appLocalized("off")
        return appLocalizedValue("Latest weight \(weightText(current.weightKg)), \(signedWeightText(change)) since start. Dose labels are \(labelState).")
    }

    private func nearestPoint(to date: Date) -> WeightPoint? {
        orderedPoints.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func doseFor(date: Date) -> Double? {
        let sorted = injections.sorted { $0.injectionDate < $1.injectionDate }
        if let active = sorted.last(where: { $0.injectionDate <= date }) {
            return active.doseMg
        }
        return sorted.first?.doseMg
    }

    private func selectedPointSummary(_ point: WeightPoint) -> String {
        if let doseMg = point.doseMg {
            return appLocalizedValue("\(shortDate(point.date)) · \(weightText(point.weightKg)) · \(doseText(doseMg))")
        }
        return appLocalizedValue("\(shortDate(point.date)) · \(weightText(point.weightKg))")
    }
}

/// "By Dose" ledger: one row per contiguous dose phase, chronological so it
/// reads left-to-right with the chart above, in the same dose colors. Shown
/// only once there is more than one phase — with a single dose the change
/// equals the hero total and a breakdown would just repeat it.
private struct ResultsDosePhasesSection: View {
    let phases: [DosePhase]

    var body: some View {
        if phases.count >= 2 {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(title: "By Dose")

                HealthCard(tint: AppTheme.medication, cornerRadius: AppRadius.card, padding: AppSpacing.xs) {
                    VStack(spacing: 0) {
                        ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                            DosePhaseRow(phase: phase)

                            if index < phases.count - 1 {
                                Divider()
                                    .overlay(AppTheme.stroke.opacity(0.6))
                                    .padding(.leading, AppSpacing.lg)
                            }
                        }
                    }
                }

                Text(footnoteText)
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, AppSpacing.xs)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("results-dose-phases")
        }
    }

    private var footnoteText: String {
        phases.contains { $0.pausedDays >= 1 }
            ? appLocalizedValue("Estimated from the weigh-ins nearest each dose change. Paused time is left out of durations and weekly rates.")
            : appLocalizedValue("Estimated from the weigh-ins nearest each dose change.")
    }
}

/// Ledger row: dose pill + duration on the left, the phase's change (with a
/// quiet per-week rate beneath it) on the right. A flat or rising phase stays
/// neutral — steadiness is not failure.
private struct DosePhaseRow: View {
    let phase: DosePhase

    private var tint: Color {
        doseColor(phase.doseMg)
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            Text(doseText(phase.doseMg))
                .font(AppFont.micro)
                .monospacedDigit()
                .foregroundStyle(tint)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(tint.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(0.28), lineWidth: 1))

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(durationText)
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.ink)
                Text(jabCountText)
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                if let changeKg = phase.changeKg {
                    Text(signedWeightText(changeKg))
                        .font(AppFont.metricValue)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                    if let rate = phase.weeklyRateKg {
                        Text(appLocalizedValue("\(rate.formatted(.number.precision(.fractionLength(2)))) kg/wk"))
                            .font(AppFont.micro)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.muted)
                    }
                } else {
                    Text("Not enough weigh-ins")
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // Duration is active time on the dose: recorded pauses are excluded, and
    // shown alongside the jab count so the week count stays explainable.
    private var durationText: String {
        let base = spanText(days: phase.activeDays)
        return phase.isOngoing ? appLocalizedValue("\(base) so far") : base
    }

    private var jabCountText: String {
        let jabs = phase.injectionCount == 1
            ? appLocalizedValue("1 jab")
            : appLocalizedValue("\(phase.injectionCount) jabs")
        guard phase.pausedDays >= 1 else { return jabs }
        return appLocalizedValue("\(jabs) · \(spanText(days: phase.pausedDays)) paused")
    }

    private func spanText(days: Int) -> String {
        if days < 14 {
            let days = max(1, days)
            return days == 1 ? appLocalizedValue("1 day") : appLocalizedValue("\(days) days")
        }
        let weeks = max(1, Int((Double(days) / 7).rounded()))
        return appLocalizedValue("\(weeks) weeks")
    }

    private var accessibilitySummary: String {
        var parts = [doseText(phase.doseMg), durationText, jabCountText]
        if let changeKg = phase.changeKg {
            parts.append(signedWeightText(changeKg))
            if let rate = phase.weeklyRateKg {
                parts.append(appLocalizedValue("\(rate.formatted(.number.precision(.fractionLength(2)))) kg per week"))
            }
        } else {
            parts.append(appLocalized("Not enough weigh-ins"))
        }
        return parts.joined(separator: ", ")
    }
}

private struct WeightHistorySection: View {
    let weights: [WeightSnapshot]
    let edit: (WeightSnapshot) -> Void
    let delete: (WeightSnapshot) -> Void

    var body: some View {
        let ordered = weights.sorted { $0.recordedAt > $1.recordedAt }
        if !ordered.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(title: "Weight History")

                // One grouped card with hairline dividers instead of a stack of
                // N identical floating cards — the journey reads as a ledger, and
                // the weight value carries the row (no repeated icon chips).
                HealthCard(tint: AppTheme.blue, cornerRadius: AppRadius.card, padding: AppSpacing.xs) {
                    VStack(spacing: 0) {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, weight in
                            Button {
                                edit(weight)
                            } label: {
                                WeightHistoryRow(weight: weight, previous: ordered.indices.contains(index + 1) ? ordered[index + 1] : nil)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Edit", systemImage: AppSymbol.Action.edit) {
                                    edit(weight)
                                }
                                Button("Delete", systemImage: AppSymbol.Action.delete, role: .destructive) {
                                    delete(weight)
                                }
                            }

                            if index < ordered.count - 1 {
                                Divider()
                                    .overlay(AppTheme.stroke.opacity(0.6))
                                    .padding(.leading, AppSpacing.lg)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("results-weight-entry-count")
            .accessibilityLabel(appLocalizedValue("Weight entries \(ordered.count)"))
        }
    }
}

/// Ledger row: date + optional note on the left, the weight (with a quiet
/// delta-vs-previous beneath it) on the right.
private struct WeightHistoryRow: View {
    let weight: WeightSnapshot
    let previous: WeightSnapshot?

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(weight.recordedAt.appFormatted(.dateTime.month(.abbreviated).day().year()))
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.ink)
                    // Provenance: a quiet Apple-Health mark so an imported reading is
                    // distinguishable from one typed by hand, without a noisy label.
                    if weight.isFromHealthKit {
                        Image(systemName: AppSymbol.Health.appleHealth)
                            .font(AppFont.micro)
                            .foregroundStyle(AppTheme.rose)
                            .accessibilityLabel(appLocalized("From Apple Health"))
                    }
                }
                if let notes = weight.notes {
                    Text(localizedAppAuthoredWeightNote(notes))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                Text(weightText(weight.weightKg))
                    .font(AppFont.metricValue)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
                if let previous {
                    let delta = weight.weightKg - previous.weightKg
                    Text(signedWeightText(delta))
                        .font(AppFont.micro)
                        .monospacedDigit()
                        .foregroundStyle(delta <= 0 ? AppTheme.primary : AppTheme.muted)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }
}

private func localizedAppAuthoredWeightNote(_ note: String) -> String {
    switch note {
    case "Starting weight from onboarding":
        appLocalizedValue("Starting weight from onboarding")
    case "Treatment start":
        appLocalizedValue("Treatment start")
    case "Settled into routine":
        appLocalizedValue("Settled into routine")
    default:
        note
    }
}

private struct ResultsInsightsCard: View {
    let stats: ResultsStats
    let doseInfo: (current: Double?, previous: Double?, weeks: Int?)

    var body: some View {
        let insights = buildInsights(stats: stats, doseInfo: doseInfo)
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(title: "Insights")
                ForEach(insights.prefix(2), id: \.title) { insight in
                    HealthCard(tint: insight.tint, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
                        HStack(alignment: .top, spacing: AppSpacing.lg) {
                            Image(systemName: insight.icon)
                                .font(AppFont.bodyStrong)
                                .foregroundStyle(insight.tint)
                                .frame(width: 42, height: 42)
                                .background(insight.tint.opacity(0.16), in: Circle())
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(appLocalized(insight.title))
                                    .font(AppFont.bodyStrong)
                                    .foregroundStyle(AppTheme.ink)
                                Text(appLocalized(insight.description))
                                    .font(AppFont.body)
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct WeightPoint: Identifiable {
    let id: UUID
    let date: Date
    let weightKg: Double
    let doseMg: Double?
}

private struct TrendSample: Identifiable {
    let id: Int
    let date: Date
    let weightKg: Double
    let doseMg: Double?
}

private struct TrendLineSegment: Identifiable {
    let id: Int
    let points: [TrendSample]
    let tint: Color
}

private struct DoseLabel: Identifiable {
    let date: Date
    let weightKg: Double
    let doseMg: Double

    var id: String {
        "\(date.timeIntervalSince1970)-\(doseMg)"
    }
}

private struct PhaseBand: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let tint: Color
    let changeKg: Double?
}

private struct PhaseDeltaLabel: Identifiable {
    let id: String
    let date: Date
    let changeKg: Double
    let tint: Color
}

struct MonthLabelTick: Identifiable {
    let date: Date
    let monthStart: Date

    var id: String {
        "\(monthStart.timeIntervalSince1970)"
    }
}

enum ResultsChartScale {
    // The domain must not depend on any overlay toggle: changing it re-scales
    // every mark, so flipping dose labels used to shift the whole trend line.
    // Annotations that would overflow the trailing edge are pulled inside the
    // plot via annotation overflowResolution instead.
    static func xDomain(
        first: Date,
        last: Date,
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        guard first < last else {
            return first.addingTimeInterval(-86_400)...last.addingTimeInterval(86_400)
        }
        return first...last
    }

    static func monthGridDates(
        first: Date,
        last: Date,
        domain: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [Date] {
        displayedMonthStarts(first: first, last: last, calendar: calendar)
            .filter { domain.contains($0) }
    }

    // Labels sit AT the month-start gridline (clamped to the domain edge), not
    // at the month's midpoint. A midpoint "Jan" rendered under a late-January
    // dose-change line and read as "the new dose started at Jan"; anchoring the
    // label to the gridline keeps in-month events legible.
    static func monthLabelTicks(
        first: Date,
        last: Date,
        domain: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [MonthLabelTick] {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return [] }
        return displayedMonthStarts(first: first, last: last, calendar: calendar).compactMap { monthStart in
            guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                return nil
            }
            let visibleStart = max(monthStart, domain.lowerBound)
            let visibleEnd = min(monthEnd, domain.upperBound)
            guard visibleStart < visibleEnd else {
                return nil
            }
            // A sliver month clipped at either domain edge (e.g. three visible
            // December days before a late-December start) gets no label — its
            // label would crowd the neighbour and overstate the month.
            guard visibleEnd.timeIntervalSince(visibleStart) / span >= 0.08 else {
                return nil
            }
            return MonthLabelTick(date: visibleStart, monthStart: monthStart)
        }
    }

    private static func displayedMonthStarts(first: Date, last: Date, calendar: Calendar) -> [Date] {
        var ticks: [Date] = []
        var current = calendar.dateInterval(of: .month, for: first)?.start ?? first
        let lastMonth = calendar.dateInterval(of: .month, for: last)?.start ?? last

        while current <= lastMonth {
            ticks.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }

        if ticks.count > 6 {
            let step = max(1, Int(ceil(Double(ticks.count) / 4.0)))
            ticks = ticks.enumerated().compactMap { index, tick in
                index % step == 0 || index == ticks.count - 1 ? tick : nil
            }
        }
        return ticks
    }
}

private struct DoseBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let doseMg: Double
    let tint: Color

    var body: some View {
        Text(doseText(doseMg))
            .font(.system(.subheadline, weight: .heavy))
            .foregroundStyle(doseBadgeForeground(doseMg, colorScheme: colorScheme))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow, radius: 8, x: 0, y: 3)
            .fixedSize()
    }
}

private struct DoseLegendChip: View {
    let doseMg: Double
    let tint: Color

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Capsule()
                .fill(tint)
                .frame(width: 16, height: 7)
            Text(doseText(doseMg))
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(AppType.minScale)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private func resultStats(_ weights: [WeightSnapshot], profile: ProfileSnapshot) -> ResultsStats? {
    let orderedWeights = weights.sorted { $0.recordedAt < $1.recordedAt }
    guard let first = orderedWeights.first, let last = orderedWeights.last else { return nil }
    let starting = profile.startingWeightKg > 0 ? profile.startingWeightKg : first.weightKg
    let change = last.weightKg - first.weightKg
    // Percent change (and the milestone insights that read it) is measured from
    // the actual starting weight, not the period-filtered first sample, so "10%
    // from your starting weight" can't fire off a short window.
    let percentChange = starting > 0 ? ((last.weightKg - starting) / starting) * 100 : 0
    let toGoal = profile.goalWeightKg > 0 ? last.weightKg - profile.goalWeightKg : nil
    let progress: Double?
    if profile.goalWeightKg > 0, starting > profile.goalWeightKg {
        progress = min(100, max(0, ((starting - last.weightKg) / (starting - profile.goalWeightKg)) * 100))
    } else {
        progress = nil
    }
    let bmi: Double?
    if profile.heightCm > 0 {
        let meters = profile.heightCm / 100
        bmi = (last.weightKg / (meters * meters) * 10).rounded() / 10
    } else {
        bmi = nil
    }
    let weekly = weeklyAverages(orderedWeights)
    let weekSpan = max(1, last.recordedAt.timeIntervalSince(first.recordedAt) / (7 * 24 * 60 * 60))
    let weeklyAverage = orderedWeights.count >= 2 ? change / weekSpan : nil

    return ResultsStats(
        current: last.weightKg,
        starting: starting,
        change: change,
        percentChange: percentChange,
        goal: profile.goalWeightKg > 0 ? profile.goalWeightKg : nil,
        toGoal: toGoal,
        progressPercent: progress,
        bmi: bmi,
        weeklyAverage: weeklyAverage,
        totalWeeks: weekly.count
    )
}

private func weeklyAverages(_ weights: [WeightSnapshot]) -> [(week: String, average: Double)] {
    let grouped = Dictionary(grouping: weights) { entry -> String in
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: entry.recordedAt)?.start ?? entry.recordedAt
        return start.formatted(.iso8601.year().month().day())
    }
    return grouped.map { key, values in
        (key, values.map(\.weightKg).reduce(0, +) / Double(values.count))
    }
    .sorted { $0.week < $1.week }
}

private func shortDate(_ date: Date) -> String {
    date.appFormatted(.dateTime.month(.abbreviated).day())
}

private func doseInfo(_ injections: [InjectionSnapshot]) -> (current: Double?, previous: Double?, weeks: Int?) {
    var changes: [(date: Date, dose: Double)] = []
    var lastDose: Double?
    for injection in injections.sorted(by: { $0.injectionDate < $1.injectionDate }) {
        if injection.doseMg != lastDose {
            changes.append((injection.injectionDate, injection.doseMg))
            lastDose = injection.doseMg
        }
    }
    guard let current = changes.last else { return (nil, nil, nil) }
    let previous = changes.count > 1 ? changes[changes.count - 2].dose : nil
    let weeks = Calendar.current.dateComponents([.weekOfYear], from: current.date, to: Date()).weekOfYear
    return (current.dose, previous, weeks)
}

private func buildInsights(
    stats: ResultsStats,
    doseInfo: (current: Double?, previous: Double?, weeks: Int?)
) -> [(title: String, description: String, icon: String, tint: Color)] {
    var items: [(String, String, String, Color)] = []
    if let weekly = stats.weeklyAverage, weekly < 0, stats.totalWeeks >= 4 {
        items.append(("Steady Progress", appLocalizedValue("Your recent entries show a steady downward trend across \(stats.totalWeeks) weeks."), AppSymbol.Insight.downTrend, AppTheme.success))
    }
    if let current = doseInfo.current, let previous = doseInfo.previous, current > previous, let weeks = doseInfo.weeks {
        let description = weeks == 1
            ? appLocalizedValue("You moved to \(doseText(current)) 1 week ago.")
            : appLocalizedValue("You moved to \(doseText(current)) \(weeks) weeks ago.")
        items.append(("Dose Increased", description, AppSymbol.Insight.doseIncrease, AppTheme.blue))
    }
    if let toGoal = stats.toGoal, toGoal > 0, toGoal <= 5 {
        items.append(("Close to Goal", appLocalizedValue("\(weightText(toGoal)) remains against the goal you set."), AppSymbol.Insight.target, AppTheme.success))
    }
    if stats.percentChange <= -10 {
        items.append(("10% Milestone", appLocalized("You have crossed 10% from your starting weight."), AppSymbol.Insight.milestone, AppTheme.amber))
    } else if stats.percentChange <= -5 {
        items.append(("5% Milestone", appLocalized("You have crossed 5% from your starting weight."), AppSymbol.Insight.milestone, AppTheme.amber))
    }
    if let weekly = stats.weeklyAverage, weekly > 0 {
        items.append(("Weight Trending Up", appLocalized("Your average weight is increasing. Consider reviewing recent patterns."), AppSymbol.Insight.upTrend, AppTheme.rose))
    }
    return items
}


private func signedWeightText(_ value: Double) -> String {
    if abs(value) < 0.05 {
        return appLocalized("0.0 kg")
    }
    let sign = value > 0 ? "+" : "-"
    return appLocalizedValue("\(sign)\(abs(value).formatted(.number.precision(.fractionLength(1)))) kg")
}
