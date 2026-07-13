import SwiftData
import SwiftUI

struct SummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [TrackerProfile]
    let snapshot: DashboardSnapshot
    /// Optional route request from system surfaces (widgets / controls). Summary
    /// consumes and clears it once its tab is mounted, mirroring JabsView's
    /// Add Injection route handoff.
    var requestedQuickAction: Binding<SummaryQuickAction?>?
    @State private var activeQuickAction: SummaryQuickAction?
    /// Presents the "Set your numbers" goals editor. The primary path for a user
    /// who skipped first-run setup and now wants the Journey hero to light up,
    /// reached from the empty state or the hero's no-goal prompt.
    @State private var presentSetNumbers = false
    /// Dignified acknowledgment of a completed save: one success haptic, no
    /// fanfare. Incremented by every Summary save path.
    @State private var saveFeedback = 0

    init(snapshot: DashboardSnapshot, requestedQuickAction: Binding<SummaryQuickAction?>? = nil) {
        self.snapshot = snapshot
        self.requestedQuickAction = requestedQuickAction
    }

    var body: some View {
        AppScreen(title: "Journey") {
            if snapshot.hasAnyData {
                CurrentWeightHeroCard(
                    snapshot: snapshot,
                    onSetGoal: { presentSetNumbers = true },
                    onAddWeight: { activeQuickAction = .weight }
                )
                injectionSummaryCard
            } else {
                // Blank slate (bucket A): one warm invitation, not an empty-state
                // card stacked over a separate "set your numbers" prompt. The quick
                // actions below carry the actual first-entry CTAs.
                WelcomeHeroCard()
            }

            // Quick actions stay outside every gate so the Journey can never go
            // fully blank — there is always a way to add the first entry.
            SummaryQuickActions { activeQuickAction = $0 }

            // Blank slate only: a quiet, demoted shortcut to the goals editor (kept
            // as `summarySetNumbers`). It disappears the moment any data exists.
            if !snapshot.hasAnyData {
                SetGoalNumbersLink { presentSetNumbers = true }
            }

            let metricTiles = summaryMetricTiles
            if !metricTiles.isEmpty {
                LazyVGrid(columns: metricColumns(metricTiles.count), spacing: AppSpacing.md) {
                    ForEach(metricTiles) { tile in
                        MetricTile(
                            title: tile.title,
                            value: tile.value,
                            subtitle: tile.subtitle,
                            systemImage: tile.systemImage,
                            tint: tile.tint,
                            minContentHeight: 96
                        )
                    }
                }
            }
        }
        .sheet(item: $activeQuickAction) { action in
            switch action {
            case .weight:
                AddWeightSheet(snapshot: snapshot, onSave: addWeight)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .injection:
                AddInjectionSheet(snapshot: snapshot, onSave: addInjection)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .dailyLog:
                AddDailyLogSheet(onSave: addDailyLog)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $presentSetNumbers) {
            // Reuses the same goals editor as Care so there is one place that
            // owns this form's layout, validation, and copy.
            GoalsEditorSheet(snapshot: snapshot, save: saveNumbers)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.success, trigger: saveFeedback)
        .onAppear { consumeQuickActionRequest() }
        .onChange(of: requestedQuickAction?.wrappedValue) { _, requested in
            if requested != nil { consumeQuickActionRequest() }
        }
    }

    private var orderedInjections: [InjectionSnapshot] {
        snapshot.injections.sorted { $0.injectionDate > $1.injectionDate }
    }

    private var orderedWeights: [WeightSnapshot] {
        snapshot.weights.sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Adaptive injection surface, driven by the single `scheduleState` machine so
    /// Summary always agrees with Jabs / the widget / the Live Activity: the live
    /// next-injection panel whenever a confirmed dose (logged OR the onboarding
    /// anchor) sets a date, a muted provisional plan when only a preferred weekday
    /// is set, or a CTA to log the first injection. Never a dead "Not scheduled"
    /// card, and never "log your first jab" while a countdown is already running.
    @ViewBuilder
    private var injectionSummaryCard: some View {
        if snapshot.isTreatmentPaused {
            PausedTreatmentCard(startedAt: snapshot.activePauseStartedAt)
        } else if snapshot.scheduleState.needsConfirmation {
            EmptyStateCard(
                title: "Confirm your recent dose",
                message: "Add your latest injection to restart your schedule.",
                systemImage: AppSymbol.Health.injection,
                tint: AppTheme.medication,
                actionTitle: "Add most recent dose",
                actionSystemImage: AppSymbol.Action.add,
                action: { activeQuickAction = .injection },
                actionIdentifier: "summaryConfirmRecentDose"
            )
        } else if snapshot.nextInjectionDate != nil {
            NextInjectionPanel(snapshot: snapshot)
        } else if let projected = snapshot.projectedNextInjectionDate,
                  let weekdayName = injectionWeekdayName(snapshot.profile.preferredInjectionDay) {
            ProvisionalInjectionCard(weekdayName: weekdayName, date: projected)
        } else {
            LogFirstInjectionCard { activeQuickAction = .injection }
        }
    }

    /// Only the metric tiles whose data exists, so a partial Journey shows real
    /// measurements instead of "Not set" placeholders.
    private var summaryMetricTiles: [SummaryMetricTileData] {
        [currentDoseMetric, weightTrendMetric].compactMap { $0 }
    }

    private func metricColumns(_ count: Int) -> [GridItem] {
        count <= 1 ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var currentDoseMetric: SummaryMetricTileData? {
        if let latest = orderedInjections.first {
            return SummaryMetricTileData(
                title: "Current dose",
                value: doseText(latest.doseMg),
                subtitle: currentDoseDurationText(for: latest),
                systemImage: AppSymbol.Health.dose,
                tint: doseColor(latest.doseMg)
            )
        }

        if let plannedDose = snapshot.profile.plannedDoseMg {
            // An active user who confirmed a recent dose is already ON this dose:
            // it is their current dose, not a future plan. Only a pre-treatment
            // user (planned weekday / idle, no dose anchor) sees it as "Planned".
            let isAnchoredDose = snapshot.nextInjectionDate != nil
            return SummaryMetricTileData(
                title: isAnchoredDose ? "Current dose" : "Planned dose",
                value: doseText(plannedDose),
                subtitle: isAnchoredDose ? nil : "Log first jab to start history",
                systemImage: AppSymbol.Health.dose,
                tint: doseColor(plannedDose)
            )
        }

        // No injection and no planned dose: omit the tile rather than asserting a
        // "Not set" measurement.
        return nil
    }

    private var weightTrendMetric: SummaryMetricTileData? {
        guard let latest = orderedWeights.first else {
            // No weights: omit the tile.
            return nil
        }

        guard let baseline = trendBaseline(for: latest) else {
            return SummaryMetricTileData(
                title: "Last weight",
                value: recencyText(since: latest.recordedAt),
                subtitle: weightText(latest.weightKg),
                systemImage: AppSymbol.Health.weight,
                tint: AppTheme.blue
            )
        }

        let daySpan = max(Calendar.current.dateComponents([.day], from: baseline.recordedAt, to: latest.recordedAt).day ?? 0, 1)
        let title = daySpan >= 25 ? "30-day trend" : "Recent trend"
        let subtitle = daySpan >= 25 ? nil : appLocalizedValue("Over \(daySpan) days")

        return SummaryMetricTileData(
            title: title,
            value: signedSummaryWeightText(latest.weightKg - baseline.weightKg),
            subtitle: subtitle,
            systemImage: AppSymbol.Health.trend,
            tint: AppTheme.blue
        )
    }

    private func currentDoseDurationText(for latest: InjectionSnapshot) -> String {
        let sameDoseDates = orderedInjections.prefix { $0.doseMg == latest.doseMg }.map(\.injectionDate)
        guard let firstAtDose = sameDoseDates.last else { return appLocalized("Latest logged dose") }

        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: firstAtDose),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0

        guard days >= 7 else { return appLocalized("Less than 1 week at this dose") }

        let weeks = max(days / 7, 1)
        if weeks == 1 { return appLocalized("1 week at this dose") }
        return appLocalizedValue("\(weeks) weeks at this dose")
    }

    private func trendBaseline(for latest: WeightSnapshot) -> WeightSnapshot? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: latest.recordedAt) ?? latest.recordedAt
        return orderedWeights
            .filter { $0.recordedAt < latest.recordedAt && $0.recordedAt >= cutoff }
            .min { $0.recordedAt < $1.recordedAt }
    }

    private func recencyText(since date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: date),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0

        if days == 0 { return appLocalized("Today") }
        if days == 1 { return appLocalized("1d ago") }
        return appLocalizedValue("\(days)d ago")
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
        saveFeedback += 1
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
            batchNumber: cleanedOptional(batchNumber),
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(injection)
        ModelWriteService.save(modelContext)
        saveFeedback += 1
    }

    private func addDailyLog(text: String, recordedAt: Date) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        LogCapture.appendNote(trimmed, on: recordedAt, in: modelContext)
        saveFeedback += 1
    }

    private func consumeQuickActionRequest() {
        guard let action = requestedQuickAction?.wrappedValue else { return }
        activeQuickAction = action
        requestedQuickAction?.wrappedValue = nil
    }

    /// Most-recently-updated profile, or a fresh one. Mirrors Care's editor so
    /// both surfaces write the same single profile row.
    private func ensureProfile() -> TrackerProfile {
        if let existing = profiles.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return existing
        }
        let profile = TrackerProfile()
        modelContext.insert(profile)
        return profile
    }

    private func saveNumbers(startingWeightKg: Double, goalWeightKg: Double, treatmentStartDate: Date) {
        let profile = ensureProfile()
        profile.startingWeightKg = startingWeightKg
        profile.goalWeightKg = goalWeightKg
        profile.treatmentStartDate = treatmentStartDate
        profile.updatedAt = Date()
        ModelWriteService.save(modelContext)
        saveFeedback += 1
    }
}

private func cleanedOptional(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func signedSummaryWeightText(_ value: Double) -> String {
    if abs(value) < 0.05 {
        return appLocalizedValue("\(0.0.formatted(.number.precision(.fractionLength(1)))) kg")
    }

    let sign = value > 0 ? "+" : "-"
    return appLocalizedValue("\(sign)\(abs(value).formatted(.number.precision(.fractionLength(1)))) kg")
}

enum SummaryQuickAction: Identifiable, Equatable {
    case weight
    case injection
    case dailyLog

    var id: Self { self }
}

private struct SummaryMetricTileData: Identifiable {
    let title: String
    let value: String
    let subtitle: String?
    let systemImage: String
    let tint: Color

    // Dose and trend titles are distinct, so the title is a stable identity.
    var id: String { title }
}

/// Blank-slate (bucket A) Journey hero: one warm invitation that the timeline
/// starts here, replacing an empty-state card stacked over a "set your numbers"
/// prompt. The quick actions and the demoted goals link below carry the CTAs.
private struct WelcomeHeroCard: View {
    var body: some View {
        HeroCard(tint: AppTheme.primary) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(appLocalized("Your timeline starts here"))
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppTheme.ink)
                Text(appLocalized("Add a weight, jab, or note — anytime."))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("summaryWelcomeHero")
    }
}

private struct CurrentWeightHeroCard: View {
    let snapshot: DashboardSnapshot
    let onSetGoal: () -> Void
    let onAddWeight: () -> Void

    private var hasGoal: Bool { snapshot.profile.goalWeightKg > 0 }
    private var hasStarting: Bool { snapshot.profile.startingWeightKg > 0 }
    private var hasCurrentWeight: Bool { snapshot.currentWeight != nil }
    /// Real, measurable loss since the starting weight. Until there is movement a
    /// "0% complete" ring reads as failure, so the hero shows a calm "Day 0" chip.
    private var hasMovement: Bool { (snapshot.totalLost ?? 0) >= 0.05 }

    var body: some View {
        HeroCard(tint: AppTheme.primary) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack(alignment: .center, spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Current weight")
                            .font(AppFont.label)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(AppTheme.muted)
                        if let current = snapshot.currentWeight {
                            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                                Text(current.formatted(.number.precision(.fractionLength(1))))
                                    .font(AppFont.display)
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(AppType.minScale)
                                    .contentTransition(.numericText())
                                Text(appLocalized(snapshot.preferences.weightUnit))
                                    .font(AppFont.cardTitle)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            // Stable hook for UI tests: the number and unit are
                            // separate Text views, so combine them into one
                            // element whose label reads "<n> kg". Tests assert a
                            // numeric value rendered, not a specific seed weight.
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("summary-current-weight-value")

                            if let totalLost = snapshot.totalLost, abs(totalLost) >= 0.05 {
                                Text(totalLost >= 0
                                    ? appLocalizedValue("\(weightText(abs(totalLost))) down since treatment start")
                                    : appLocalizedValue("\(weightText(abs(totalLost))) up since treatment start")
                                )
                                    .font(AppFont.bodyStrong)
                                    .foregroundStyle(AppTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            // No weight yet (goal- or profile-only). Invite the
                            // first weight instead of a hollow "-- kg" headline.
                            Button(action: onAddWeight) {
                                HStack(spacing: AppSpacing.sm) {
                                    Label("Add today's weight", systemImage: AppSymbol.Health.weight)
                                    Image(systemName: AppSymbol.Action.disclosure)
                                        .font(.caption2.weight(.bold))
                                }
                                .font(AppFont.cardTitle)
                                .foregroundStyle(AppTheme.primary)
                            }
                            .buttonStyle(AppPressableButtonStyle())
                            .accessibilityIdentifier("summaryHeroAddWeight")
                        }

                        // Start and goal are reference numbers, not a feature
                        // row: one quiet line instead of values pinned to
                        // opposite card edges with a hole in the middle.
                        if hasGoal {
                            Text(boundariesLine)
                                .font(AppFont.label)
                                .foregroundStyle(AppTheme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(AppType.minScale)
                                .padding(.top, AppSpacing.sm)
                        }
                    }

                    Spacer(minLength: AppSpacing.md)

                    // The signature goal ring replaces both the decorative icon
                    // chip and the thin progress bar. Only with a real goal AND a
                    // real current weight — never a 0% ring against no data.
                    // "To go" is the ring's caption: percent done and distance
                    // left are two readings of the same fact, so they live
                    // together instead of the remainder floating as an orphan
                    // line at the card bottom.
                    if hasGoal, hasCurrentWeight, let current = snapshot.currentWeight {
                        if hasMovement {
                            VStack(spacing: AppSpacing.xs) {
                                ProgressRing(progress: snapshot.progress, tint: AppTheme.primary)
                                    .frame(width: 84, height: 84)
                                    .accessibilityLabel(appLocalizedValue("\(Int((snapshot.progress * 100).rounded()))% complete"))
                                Text(appLocalizedValue("\(weightText(current - snapshot.profile.goalWeightKg)) to go"))
                                    .font(AppFont.micro)
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(AppType.minScale)
                            }
                        } else {
                            // Day one: no measurable change yet. A 0%-complete ring
                            // reads as failure; the chip reads as a fresh start.
                            DayZeroChip()
                        }
                    }
                }

                if !hasGoal, hasCurrentWeight {
                    // A weight but no goal: offer a one-tap way to set numbers
                    // instead of a 0 kg goal and a bogus progress ring.
                    Button(action: onSetGoal) {
                        HStack(spacing: AppSpacing.sm) {
                            Label("Set a goal to track progress", systemImage: AppSymbol.Health.goal)
                            Image(systemName: AppSymbol.Action.disclosure)
                                .font(.caption2.weight(.bold))
                        }
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.primary)
                    }
                    .buttonStyle(AppPressableButtonStyle())
                    .accessibilityIdentifier("summaryHeroSetGoal")
                }
            }
        }
        // Stable hook for UI tests: identify the seeded weight hero without
        // matching a hardcoded weight value. `.contain` keeps the inner
        // Add-weight / Set-goal buttons individually queryable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary-current-weight-hero")
    }

    /// Goal framing as one muted reference line. Mentions Start only when a
    /// real starting weight exists, so a goal-only profile never prints
    /// "Start 0 kg".
    private var boundariesLine: String {
        let goal = weightText(snapshot.profile.goalWeightKg)
        if hasStarting {
            return appLocalizedValue("Start \(weightText(snapshot.profile.startingWeightKg)) · Goal \(goal)")
        }
        return appLocalizedValue("Goal \(goal)")
    }
}

/// Day-one marker shown in place of a 0%-complete ring before any weight change:
/// a calm fresh-start cue rather than a progress reading that looks like failure.
private struct DayZeroChip: View {
    var body: some View {
        VStack(spacing: 2) {
            Text(appLocalized("Day 0"))
                .font(AppFont.metricValue)
                .foregroundStyle(AppTheme.primary)
            Text(appLocalized("Just starting"))
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(AppType.minScale)
        }
        .frame(width: 84, height: 84)
        .background(AppTheme.primary.opacity(0.10), in: Circle())
        .overlay(Circle().stroke(AppTheme.primary.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("summaryDayZeroChip")
    }
}

private struct NextInjectionPanel: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        let status = nextInjectionStatus(snapshot.nextInjectionDayCount)

        HealthCard(tint: status.tint, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                Image(systemName: status.image)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .frame(width: 52, height: 52)
                    .background(status.tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Next injection")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.ink)
                    Text(appLocalized(nextInjectionLine))
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let plannedDoseLine {
                        Label(appLocalized(plannedDoseLine), systemImage: AppSymbol.Health.dose)
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(AppTheme.medication)
                    }
                    if let displaySite = snapshot.suggestedInjectionSiteDisplay {
                        Label(InjectionSiteRotation.localizedDisplayName(for: displaySite), systemImage: AppSymbol.Health.injectionSite)
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Label(appLocalized(status.label), systemImage: status.image)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(status.tint)
                }

                Spacer(minLength: 6)

                VStack(spacing: AppSpacing.xs) {
                    Text(appLocalized(dayCountText(snapshot.nextInjectionDayCount)))
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(status.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(AppType.minScaleTight)
                        .contentTransition(.numericText())
                    Text(appLocalized(countdownCaption(snapshot.nextInjectionDayCount)))
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.muted)
                }
                .frame(minWidth: 68)
            }
        }
    }

    private var nextInjectionLine: String {
        guard let date = snapshot.nextInjectionDate else { return appLocalized("Not scheduled") }
        let dateText = date.appFormatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if let dose = currentDose {
            return appLocalizedValue("\(dateText) · \(doseText(dose))")
        }
        return dateText
    }

    private var currentDose: Double? {
        snapshot.profile.plannedDoseMg ?? lastLoggedDose
    }

    private var lastLoggedDose: Double? {
        snapshot.injections.sorted { $0.injectionDate > $1.injectionDate }.first?.doseMg
    }

    private var plannedDoseLine: String? {
        guard let planned = snapshot.profile.plannedDoseMg,
              let last = lastLoggedDose,
              planned != last
        else {
            return nil
        }
        return appLocalizedValue("Last jab was \(doseText(last))")
    }
}

/// Demoted, one-line shortcut to the goals editor for a blank-slate Journey: a
/// quiet tappable link, not a full card stacked under the welcome hero. Keeps the
/// `summarySetNumbers` identifier so the skipper's "set your numbers" path is
/// unchanged. Shown only while there is no data.
private struct SetGoalNumbersLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: AppSymbol.Health.goal)
                    .font(.caption.weight(.semibold))
                Text(appLocalized("Set goal & numbers"))
                Image(systemName: AppSymbol.Action.disclosure)
                    .font(.caption2.weight(.bold))
            }
            .font(AppFont.label)
            .foregroundStyle(AppTheme.primary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, AppSpacing.sm)
        }
        .buttonStyle(AppPressableButtonStyle())
        .accessibilityIdentifier("summarySetNumbers")
    }
}

/// Shown on Summary when there is no injection history and no preferred weekday:
/// a clear next step to start the treatment timeline, never a dead countdown.
private struct LogFirstInjectionCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HealthCard(tint: AppTheme.medication, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: AppSymbol.Health.injection)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.medication)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.medication.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Log first injection")
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(AppTheme.ink)
                        Text("Start your treatment timeline after it happens")
                            .font(AppFont.label)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: AppSymbol.Action.disclosure)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
        .buttonStyle(AppPressableButtonStyle())
        .accessibilityIdentifier("summaryLogFirstInjection")
    }
}

private struct SummaryQuickActions: View {
    let select: (SummaryQuickAction) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            QuickActionButton(title: "Weight", systemImage: AppSymbol.Health.weight, tint: AppTheme.blue) {
                select(.weight)
            }
            QuickActionButton(title: "Injection", systemImage: AppSymbol.Health.injection, tint: AppTheme.medication) {
                select(.injection)
            }
            QuickActionButton(title: "Daily Log", systemImage: AppSymbol.Health.dailyLog, tint: AppTheme.primary) {
                select(.dailyLog)
            }
        }
    }
}

private struct AddDailyLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, Date) -> Void
    @State private var text = ""
    @FocusState private var isTextFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HealthCard(tint: AppTheme.primary, cornerRadius: AppRadius.hero, padding: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        HStack(alignment: .center, spacing: AppSpacing.md) {
                            Image(systemName: AppSymbol.Health.dailyNote)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 42, height: 42)
                                .background(AppTheme.primary.opacity(0.14), in: Circle())

                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(appLocalized("Daily note"))
                                    .font(AppFont.cardTitle)
                                    .foregroundStyle(AppTheme.ink)
                                Text(Date().appFormatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                    .font(AppFont.body)
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }

                        AppTextFieldShell(systemImage: AppSymbol.Health.note, tint: AppTheme.primary) {
                            TextField(appLocalized("What stood out today?"), text: $text, axis: .vertical)
                                .lineLimit(5...9)
                                .focused($isTextFocused)
                                .accessibilityIdentifier("daily-log-text-editor")
                        }
                        .frame(minHeight: 150, alignment: .top)

                        SheetActionButton(title: "Save", systemImage: AppSymbol.Action.save, tint: AppTheme.primary) {
                            isTextFocused = false
                            onSave(text, Date())
                            dismiss()
                        }
                        .disabled(trimmedText.isEmpty)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.xl)
            .background(AppBackground())
            .navigationTitle("Daily Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextFocused = false
                    }
                }
            }
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                isTextFocused = true
            }
        }
    }
}

private func nextInjectionStatus(_ days: Int?) -> (label: String, image: String, tint: Color) {
    guard let days else { return (appLocalized("First dose not logged"), AppSymbol.Status.notScheduled, AppTheme.muted) }
    if days < 0 { return (appLocalized("Needs logging"), AppSymbol.Status.needsLogging, AppTheme.rose) }
    if days == 0 { return (appLocalized("Ready to log"), AppSymbol.Status.readyToLog, AppTheme.success) }
    if days <= 2 { return (appLocalized("Coming up"), AppSymbol.Status.comingUp, AppTheme.amber) }
    return (appLocalized("On track"), AppSymbol.Status.onTrack, AppTheme.success)
}

private func dayCountText(_ days: Int?) -> String {
    guard let days else { return "--" }
    if days < 0 { return "\(abs(days))d" }
    if days == 0 { return appLocalized("Today") }
    return appLocalizedValue("\(days)d")
}

private func countdownCaption(_ days: Int?) -> String {
    guard let days else { return appLocalized("no date") }
    if days < 0 { return appLocalized("overdue") }
    if days == 0 { return appLocalized("today") }
    return appLocalized("remaining")
}
