import SwiftData
import SwiftUI

/// The single UserDefaults key that gates the first-run experience. Owned here
/// so `AppRootView` (the gate) and `OwnerSeedImportLaunchHandler` (which marks
/// it complete after an owner import) reference one source of truth.
enum FirstRunFlag {
    static let key = "hasCompletedFirstRun"
}

/// First-run setup (see docs/onboarding-redesign-mockups.html, v1.0.0). A clean
/// multi-step flow: a value-only Welcome, then the treatment-status question asked
/// EXACTLY ONCE, then a short sequence of one-thing-per-screen steps tailored to
/// the chosen track, ending on the Summary tab. There is no status control after
/// the Status step, so the old duplicate-question shape cannot reappear.
///
/// Truthful defaults are unchanged: no pre-picked medication or dose, an
/// unselected (or "I'm not sure") status reads as `.unknown`, so no downstream
/// surface can present a guess as fact. The write/save contract — `commit()`,
/// `applyStatusContract`, `materializeWeights` — is identical to the prior
/// single-form version; only the screens were reorganized.
struct FirstRunSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The same key `AppRootView` watches. Setting it flips the root back to the
    /// tab shell; `hasAnyData` changing after a save does the same, so either
    /// path resolves the gate.
    @AppStorage(FirstRunFlag.key) private var hasCompletedFirstRun = false

    /// The screens of the flow. The branch screens are reached only via the Status
    /// step, which is the one and only place treatment status is set.
    private enum Screen: Hashable {
        case welcome
        case status
        // Just starting (.startingNow)
        case startMedicine, startDay, reminders
        // Already on treatment (.active)
        case activeLastDose, activeMedicine
        // Treatment-start date — active branch only. Dates the history baseline
        // (the materialized starting-weight checkpoint), never the dose schedule.
        case treatmentStart
        // Taking a break (.paused)
        case pausedContext
        // The shared weight baseline, split into one decision per screen. Current,
        // starting, and goal are MANDATORY (the gate holds Continue until valid);
        // numbersHealth is the lone exempt/optional step and only appears when
        // HealthKit is available (see `visibleScreens`).
        case numbersHealth, numbersCurrent, numbersStarting, numbersGoal
        // Forward-looking close before the app opens.
        case close
    }

    /// The current screen and the manual back-stack that powers the Back chevron.
    @State private var step: Screen
    @State private var history: [Screen] = []
    @State private var navigationDirection: NavigationDirection = .forward

    fileprivate enum NavigationDirection {
        case forward
        case backward
    }

    /// Treatment status — nil until the user picks one. Leaving it untouched (or
    /// Skip) persists nothing and reads as `.unknown`, a calm un-nagged state.
    @State private var status: TreatmentStatus?

    // Numbers — all optional, shown on the track's numbers step.
    @State private var currentWeight = ""
    @State private var startingWeight = ""
    @State private var goalWeight = ""

    // Treatment start (active path). `provided` is tracked separately from the
    // Date because DatePicker only binds a Date — it gives no "confirmed default"
    // signal — so accepting today's default would otherwise record nothing.
    @State private var treatmentStartDate = Date()
    @State private var treatmentStartProvided = false

    // Medication / dose — no pre-pick, so unknown stays unknown.
    @State private var medicationChoice: Medication?
    @State private var doseChoice: Double?

    // Most-recent dose (active path) — the only thing that may anchor the schedule.
    @State private var lastDoseDate = Date()
    @State private var lastDoseProvided = false
    @State private var lastDoseSiteSelection = OnboardingForm.unknownSite
    @State private var confirmLatestDose = true

    // Optional last-dose context for the paused path.
    @State private var pausedLastDoseDate = Date()
    @State private var pausedLastDoseProvided = false

    /// Optional injection-day anchor. Off by default; only persisted when the user
    /// turns it on, in which case it also creates a profile so the Jabs surface can
    /// show a provisional plan before the first logged jab.
    @State private var injectionDayEnabled = false
    /// Stored 0-based with Sunday == 0 (indexes Calendar.weekdaySymbols), matching
    /// TrackerProfile.preferredInjectionDay. Defaults to Monday, like Care.
    @State private var preferredInjectionDay = 1

    /// Optional reminders discovery step (just-starting branch only). `enabled`
    /// reflects whether the in-card opt-in actually turned reminders on (so the card
    /// can show a confirmation); `deniedHint` shows the one-line Settings hint when
    /// the system authorization was declined. Both default off; the primary
    /// "Continue" is a no-op "Maybe later" that never spends the one-shot prompt.
    @State private var remindersEnabled = false
    @State private var remindersDeniedHint = false

    /// Apple Health weight import (offered on the weight step). `connected` reflects
    /// that the in-context opt-in asked for read access and set the per-device flag;
    /// `connecting` drives the in-flight spinner. The actual history pull is deferred
    /// to the post-commit `syncIfEnabled` — pulling mid-onboarding would insert
    /// WeightEntry rows, flip `hasAnyData`, and eject the first-run flow.
    @State private var healthConnected = false
    @State private var healthConnecting = false

    /// Escape hatch from the goal ruler to the typed field (precision entry,
    /// VoiceOver, and the UI-test path).
    @State private var isTypingGoal = false

    @FocusState private var focusedField: Field?
    private enum Field: Hashable {
        case current, starting, goal

        var accessibilityIdentifier: String {
            switch self {
            case .current: return "firstRunCurrentWeight"
            case .starting: return "firstRunStartingWeight"
            case .goal: return "firstRunGoalWeight"
            }
        }
    }

    /// Real HealthKit availability, resolved once at init so navigation, progress, the
    /// gate, and the deep-link entry all agree on whether the Apple Health step exists.
    /// Overridable for tests/sandbox — see `resolveHealthAvailable`.
    private let healthAvailable: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        let resolvedHealth = Self.resolveHealthAvailable(args: args)
        self.healthAvailable = resolvedHealth
        // Test hook: deep-link straight into a branch (status pre-set), so
        // branch-specific UI tests don't have to tap through Welcome + Status. The
        // entry resolves to the first VISIBLE step (skips Health when unavailable).
        if let token = Self.value(of: "--gaurava-first-run-branch", in: args),
           let preset = Self.status(forBranchToken: token) {
            _status = State(initialValue: preset)
            _step = State(initialValue: Self.visibleScreens(for: preset, healthAvailable: resolvedHealth).first ?? .close)
        } else if args.contains("--gaurava-show-first-run-welcome") {
            _step = State(initialValue: .welcome)
        } else if args.contains("--gaurava-show-first-run") {
            // Existing setup-focused tests skip the splash and land on the question.
            _step = State(initialValue: .status)
        } else {
            _step = State(initialValue: .welcome)
        }
    }

    /// Real HealthKit availability with two deterministic overrides: the onboarding
    /// sandbox target forces it OFF (it carries no HealthKit signing), and a launch
    /// arg drives either state so UI/unit coverage can exercise both the Health-shown
    /// and Health-hidden flows without depending on the run environment.
    private static func resolveHealthAvailable(args: [String]) -> Bool {
        if args.contains("--gaurava-onboarding-hide-health") { return false }
        if args.contains("--gaurava-onboarding-show-health") { return true }
        #if GAURAVA_ONBOARDING_SANDBOX
        return false
        #else
        return HealthKitWeightSync.isAvailable
        #endif
    }

    var body: some View {
        OnboardingShell(
            spec: stepSpec,
            // Block Back while an Apple Health auth request is in flight so the user
            // cannot navigate out mid-request (the opt-in stays cancellation-aware).
            canGoBack: !history.isEmpty && step != .welcome && !healthConnecting,
            progress: progressModel,
            primaryTitle: primaryTitle,
            primaryIcon: primaryIcon,
            primaryIdentifier: step == .welcome ? "firstRunBegin" : "firstRunContinue",
            // The mandatory hard gate: Continue stays disabled until the visible
            // step's required field is valid. There is no secondary "Set up later"
            // exit — the only completion path is the close screen → commit().
            primaryDisabled: !isSatisfied(step) || healthConnecting,
            primaryDisabledHint: primaryDisabledHint,
            actionsHidden: focusedField != nil,
            navigationDirection: navigationDirection,
            reduceMotion: reduceMotion,
            back: back,
            primary: primaryActionForCurrentStep
        ) {
            stepContent
        }
        .background(AppBackground())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                // Stable identifier so UI tests dismiss the keyboard by ID — the
                // visible "Done" label localizes (e.g. "हो गया"), so matching on the
                // English label breaks the localized onboarding walks.
                Button("Done") { focusedField = nil }
                    .accessibilityIdentifier("firstRunKeyboardDone")
            }
        }
        .sensoryFeedback(SensoryFeedback.selection, trigger: status)
        .sensoryFeedback(SensoryFeedback.selection, trigger: medicationChoice)
        .sensoryFeedback(SensoryFeedback.selection, trigger: doseChoice)
        // One dignified success note when setup completes — the same
        // acknowledgment language the tabs use for saves.
        .sensoryFeedback(.success, trigger: step == .close) { _, isClose in isClose }
    }

    // MARK: - Step specs and content

    private var stepSpec: OnboardingStepSpec {
        let copy = headerCopy(for: step)
        return OnboardingStepSpec(
            id: String(describing: step),
            title: copy?.title,
            body: copy?.why,
            tint: stepTint,
            systemImage: stepSymbol,
            // Status renders its own centered question + choices (redesigned
            // layout), so it skips the shared icon hero like Welcome does.
            showsHero: step != .welcome && step != .close && step != .status
        )
    }

    private var stepTint: Color {
        switch step {
        case .activeLastDose, .activeMedicine:
            return AppTheme.medication
        case .numbersHealth:
            return AppTheme.rose
        case .numbersCurrent, .numbersStarting:
            return AppTheme.blue
        case .numbersGoal:
            return AppTheme.success
        case .pausedContext:
            return AppTheme.blue
        case .reminders:
            return AppTheme.amber
        case .close:
            return AppTheme.success
        default:
            // welcome, status, startMedicine, startDay, treatmentStart.
            return AppTheme.primary
        }
    }

    private var stepSymbol: String {
        switch step {
        case .welcome:
            return AppSymbol.Legal.privacy
        case .status:
            return AppSymbol.Health.start
        case .startMedicine, .activeMedicine:
            return AppSymbol.Health.dose
        case .startDay:
            return AppSymbol.Health.schedule
        case .reminders:
            return AppSymbol.Health.reminder
        case .treatmentStart:
            return AppSymbol.Health.schedule
        case .numbersHealth:
            return AppSymbol.Health.appleHealth
        case .numbersCurrent:
            return AppSymbol.Health.currentWeight
        case .numbersStarting:
            return AppSymbol.Health.weightUnit
        case .numbersGoal:
            return AppSymbol.Health.goal
        case .activeLastDose, .pausedContext:
            return AppSymbol.Health.injection
        case .close:
            return AppSymbol.Status.verified
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeIdentityScreen()
        case .status:
            StartingPointSelector(selection: $status)
        case .startMedicine:
            medicineContent(
                eyebrow: "Medicine",
                doseCaption: "Planned starting dose",
                emptyNote: nil,
                selectedNote: nil
            )
        case .startDay:
            injectionDayCard
        case .reminders:
            remindersCard
        case .treatmentStart:
            treatmentStartContent
        case .numbersHealth:
            healthImportContent
        case .numbersCurrent:
            currentWeightContent
        case .numbersStarting:
            startingWeightContent
        case .numbersGoal:
            goalWeightContent
        case .activeLastDose:
            HealthCard(tint: AppTheme.medication) {
                lastDoseContent
            }
        case .activeMedicine:
            medicineContent(
                eyebrow: "Medicine",
                doseCaption: "Current dose",
                emptyNote: nil,
                selectedNote: "For tracking only. No dosing advice."
            )
        case .pausedContext:
            pausedContextContent
        case .close:
            OnboardingCloseContent(model: closeModel, recapRows: closeRecapRows)
        }
    }

    // MARK: - Step content builders

    private func medicineContent(
        eyebrow: String,
        doseCaption: String,
        emptyNote: String?,
        selectedNote: String?
    ) -> some View {
        // Rows stand alone (like the Status step); the dose grid hangs off the
        // selected medicine in its own card.
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            MedicationSegment(selection: $medicationChoice) { doseChoice = nil }
            if medicationChoice != nil {
                HealthCard(tint: AppTheme.medication) {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        OnboardingCardLabel(title: doseCaption, detail: nil)
                        DoseChips(medication: medicationChoice ?? .tirzepatide, selection: $doseChoice)
                        if let selectedNote {
                            Text(appLocalized(selectedNote))
                                .font(AppFont.micro)
                                .foregroundStyle(AppTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let emptyNote {
                Text(appLocalized(emptyNote))
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Active-branch only. When treatment started — the history baseline counts from
    /// this day. One-tap chips are the mandatory-gate satisfier; "Pick a date" covers
    /// older starts. History/progress timing only: it dates the materialized starting
    /// checkpoint and never anchors the dose schedule.
    private var treatmentStartContent: some View {
        HealthCard(tint: AppTheme.primary) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                OnboardingCardLabel(title: "Treatment start", detail: "No schedule")
                DateQuickPickChips(
                    date: $treatmentStartDate,
                    provided: $treatmentStartProvided,
                    idPrefix: "firstRunTreatmentStart",
                    tint: AppTheme.primary,
                    presetOffsets: [0, -7, -30],
                    sheetTitle: "Treatment start"
                )
                if treatmentStartProvided {
                    Label {
                        Text(verbatim: "\(appLocalized("Starts")) · \(treatmentStartDate.appFormatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    } icon: {
                        Image(systemName: AppSymbol.Status.selectedCircle)
                    }
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.primary)
                    .accessibilityIdentifier("firstRunTreatmentStartConfirmedDate")
                } else {
                    Text(appLocalized("Pick the day you started — your history counts from here."))
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Exempt/optional. Connect Apple Health to bring in past weights (shown only
    /// when HealthKit is available — see `visibleScreens`). Connect-only: the history
    /// pull is deferred to the post-commit `syncIfEnabled`, and Continue advances
    /// whether or not the user connected — Apple never tells us if read access was
    /// granted, so there is nothing to gate on.
    private var healthImportContent: some View {
        HealthCard(tint: AppTheme.rose) {
            appleHealthImportRow
        }
    }

    /// Required. Today's weight — the gate holds Continue until a positive value is
    /// entered. A calm helper (never error styling) states what is needed while empty.
    private var currentWeightContent: some View {
        HealthCard(tint: AppTheme.blue) {
            measurementField(
                title: "Current weight",
                placeholder: "0.0",
                text: $currentWeight,
                field: .current,
                systemImage: AppSymbol.Health.currentWeight,
                tint: AppTheme.blue,
                helper: Self.positiveWeight(currentWeight) == nil ? "Enter today's weight to continue." : nil
            )
        }
    }

    /// Required. Where the user began. Current weight is mandatory and precedes this,
    /// so the "Same as today" chip is always available with a real value — the
    /// one-tap satisfier that copies current into starting without retyping.
    private var startingWeightContent: some View {
        HealthCard(tint: AppTheme.blue) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                measurementField(
                    title: "Starting weight",
                    placeholder: "0.0",
                    text: $startingWeight,
                    field: .starting,
                    systemImage: AppSymbol.Health.weightUnit,
                    tint: AppTheme.blue,
                    helper: nil
                )
                sameAsTodayChip
            }
        }
    }

    /// The mandatory starting weight's one-tap satisfier: copy the (always present)
    /// current weight into starting. Guarded on current being parseable, which always
    /// holds in the mandatory flow since current precedes and gates this screen.
    @ViewBuilder
    private var sameAsTodayChip: some View {
        if let current = Self.positiveWeight(currentWeight) {
            let selected = Self.positiveWeight(startingWeight) == current
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    startingWeight = String(format: "%.1f", current)
                }
            } label: {
                Text(verbatim: "\(appLocalized("Same as today")) (\(weightText(current)))")
                    .font(AppFont.label)
                    .foregroundStyle(selected ? AppTheme.ink : AppTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScale)
                    .padding(.horizontal, AppSpacing.lg)
                    .frame(minHeight: 44)
                    .background(
                        selected ? AppTheme.blue.opacity(0.20) : AppTheme.actionSurface.opacity(0.22),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(selected ? AppTheme.blue.opacity(0.5) : AppTheme.stroke.opacity(0.58), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("firstRunStartingSameAsToday")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }

    /// Required. A goal direction (a recorded values exception, kept dignified). The
    /// ruler is seeded to a gentle anchored default on entry (see `advance(to:)`) so
    /// Continue is satisfied with zero taps and the committed goal equals what is
    /// shown; "type instead" then a blank re-disables Continue.
    private var goalWeightContent: some View {
        HealthCard(tint: AppTheme.success) {
            goalSection
        }
    }

    /// Optional Apple Health weight import on the weight step (only when HealthKit is
    /// available). An explicit in-context opt-in mirroring the reminders priming: a
    /// tap requests read access and flips the per-device flag; the history pull is
    /// deferred to after onboarding commits (see `commit()`), so we never insert
    /// weight rows mid-flow. The typed fields below stay available for hand entry.
    @ViewBuilder
    private var appleHealthImportRow: some View {
        if healthConnected {
            Label {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Connected to Apple Health")
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.ink)
                    Text("Your weight history imports when setup finishes.")
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: AppSymbol.Status.selectedCircle)
                    .foregroundStyle(AppTheme.rose)
            }
            .transition(.opacity)
            .accessibilityIdentifier("firstRunHealthConnected")
        } else {
            Button(action: connectAppleHealth) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: AppSymbol.Health.appleHealth)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.rose)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.rose.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Import from Apple Health")
                            .font(AppFont.label)
                            .foregroundStyle(AppTheme.ink)
                        Text("Bring in weights you've already logged.")
                            .font(AppFont.micro)
                            .foregroundStyle(AppTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if healthConnecting {
                        ProgressView()
                    } else {
                        Image(systemName: AppSymbol.Action.next)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(AppTheme.rose)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(healthConnecting)
            .accessibilityIdentifier("firstRunHealthConnect")
        }
    }

    /// The explicit Apple Health opt-in: request read access and set the per-device
    /// flag now; the import itself runs once onboarding completes. iOS hides read
    /// grant status, so we reflect "asked" optimistically — a denied user just imports
    /// nothing on the deferred pull.
    private func connectAppleHealth() {
        guard !healthConnecting else { return }
        healthConnecting = true
        Task { @MainActor in
            let ok = await HealthKitWeightSync.enableFromOnboarding()
            withAnimation(.snappy(duration: 0.16)) {
                healthConnecting = false
                healthConnected = ok
            }
        }
    }

    /// Goal weight is a decision rather than a reported fact, so it defaults to
    /// the ruler (anchored to today's weight) with a one-tap escape to the same
    /// typed field the other numbers use — which is also the VoiceOver and
    /// precise-entry path.
    @ViewBuilder
    private var goalSection: some View {
        if isTypingGoal {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                measurementField(
                    title: "Goal weight",
                    placeholder: "0.0",
                    text: $goalWeight,
                    field: .goal,
                    systemImage: AppSymbol.Health.goal,
                    tint: AppTheme.success,
                    helper: nil
                )
                Button {
                    focusedField = nil
                    withAnimation(.easeInOut(duration: 0.2)) { isTypingGoal = false }
                } label: {
                    Label("Use the slider", systemImage: "slider.horizontal.3")
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("firstRunGoalUseSlider")
            }
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Goal weight")
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.muted)
                GoalWeightRuler(
                    valueKg: Binding(
                        get: { Self.positiveWeight(goalWeight) },
                        set: { goalWeight = $0.map { String(format: "%.1f", $0) } ?? "" }
                    ),
                    referenceKg: Self.positiveWeight(currentWeight) ?? Self.positiveWeight(startingWeight)
                )
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isTypingGoal = true }
                    // Raise the keyboard once the field is installed.
                    Task {
                        await Task.yield()
                        focusedField = .goal
                    }
                } label: {
                    Label("Type instead", systemImage: "keyboard")
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("firstRunGoalTypeInstead")
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func measurementField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        systemImage: String,
        tint: Color,
        helper: String?
    ) -> some View {
        let focused = focusedField == field
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(appLocalized(title))
                .font(AppFont.label)
                .foregroundStyle(AppTheme.muted)

            HStack(spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(focused ? AppTheme.primary : AppTheme.textTertiary)
                    .frame(width: 24)

                TextField(appLocalized(placeholder), text: text)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: field)
                    .accessibilityIdentifier(field.accessibilityIdentifier)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)

                Text("kg")
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, AppSpacing.lg)
            .frame(minHeight: 54)
            .background(AppTheme.inputSurface, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(focused ? AppTheme.primary.opacity(0.55) : AppTheme.stroke, lineWidth: focused ? 1.5 : 1)
            }

            if let helper {
                Text(appLocalized(helper))
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var lastDoseContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            OnboardingCardLabel(title: "Most recent dose", detail: nil)
            DateQuickPickChips(
                date: $lastDoseDate,
                provided: $lastDoseProvided,
                idPrefix: "firstRunMostRecentDose",
                tint: AppTheme.medication
            )
            if lastDoseProvided {
                Label {
                    Text(verbatim: "\(appLocalized("Last dose")) · \(lastDoseDate.appFormatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                } icon: {
                    Image(systemName: AppSymbol.Status.selectedCircle)
                }
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.primary)
                .accessibilityIdentifier("firstRunMostRecentDoseConfirmedDate")
                Divider().overlay(AppTheme.stroke)
                sitePicker
                Toggle(isOn: $confirmLatestDose) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("This is my latest dose")
                            .font(AppFont.label)
                            .foregroundStyle(AppTheme.ink)
                        Text("Sets your schedule.")
                            .font(AppFont.micro)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .tint(AppTheme.primary)
                .accessibilityIdentifier("firstRunLatestDoseConfirmed")
            } else {
                Text("Skip if unsure.")
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pausedContextContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            MedicationSegment(selection: $medicationChoice) { doseChoice = nil }
            HealthCard(tint: AppTheme.blue) {
                OnboardingDateRow(
                    title: "Last dose",
                    systemImage: AppSymbol.Health.injection,
                    date: $pausedLastDoseDate,
                    provided: $pausedLastDoseProvided,
                    idPrefix: "firstRunPausedLastDose",
                    style: .embedded
                )
            }
        }
    }

    private var sitePicker: some View {
        Menu {
            Button(appLocalized("Not sure")) {
                lastDoseSiteSelection = OnboardingForm.unknownSite
            }
            Divider()
            ForEach(InjectionSiteRotation.allSites, id: \.self) { site in
                Button(InjectionSiteRotation.localizedDisplayName(for: site)) {
                    lastDoseSiteSelection = site
                }
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: AppSymbol.Health.injectionSite)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.muted.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Site")
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.ink)
                    Text(siteSelectionTitle)
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.primary)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("firstRunMostRecentDoseSite")
    }

    private var siteSelectionTitle: String {
        guard lastDoseSiteSelection != OnboardingForm.unknownSite else {
            return appLocalized("Not sure")
        }
        return InjectionSiteRotation.localizedDisplayName(for: lastDoseSiteSelection)
    }

    /// Visually subordinate, fully optional injection-day anchor on the
    /// just-starting track. The schedule engine surfaces it only as a future plan,
    /// never as overdue, and no injection is created here.
    private var injectionDayCard: some View {
        HealthCard(tint: AppTheme.primary) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                OnboardingCardLabel(
                    title: "Weekly planning day",
                    detail: injectionDayEnabled ? nil : "Optional"
                )
                // The seven days are shown directly: tapping one enables the plan
                // and selects it; tapping the selected day again clears it. No
                // separate toggle — the screen shows the decision it asks for.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 7), spacing: AppSpacing.sm) {
                    ForEach(0..<7, id: \.self) { day in
                        weekdayButton(day)
                    }
                }
                if injectionDayEnabled {
                    Text(appLocalizedValue("Planned for every \(Self.weekdayName(preferredInjectionDay)). No countdown yet."))
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else {
                    Text("Tap a day to plan, or skip.")
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
    }

    private func weekdayButton(_ day: Int) -> some View {
        let selected = injectionDayEnabled && preferredInjectionDay == day
        return Button {
            withAnimation(.snappy(duration: 0.16)) {
                if injectionDayEnabled && preferredInjectionDay == day {
                    // Tapping the selected day again clears the plan (the "off" state).
                    injectionDayEnabled = false
                } else {
                    preferredInjectionDay = day
                    injectionDayEnabled = true
                }
            }
        } label: {
            Text(Self.weekdayInitial(day))
                .font(AppFont.label)
                .foregroundStyle(selected ? AppTheme.accentForeground : AppTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? AppTheme.primary : AppTheme.actionSurface, in: Capsule())
                .overlay(Capsule().stroke(selected ? AppTheme.primary.opacity(0.4) : AppTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.weekdayName(day))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("firstRunInjectionDay-\(day)")
    }

    /// Optional reminders discovery step (docs/injection-reminders-plan.html,
    /// Component 3): a self-contained priming card mirroring `injectionDayCard`. The
    /// in-card "Turn on reminders" is the only thing that spends the one-shot system
    /// prompt; the primary "Continue" is the no-op "Maybe later" (this step is exempt
    /// from the mandatory gate — notification permission cannot be forced). Reuses the
    /// same `InjectionReminderPermission.request()` +
    /// `SurfacePreferences().injectionRemindersEnabled` path as the Care toggle, so
    /// the post-commit save fan-out reconciles the schedule for free.
    private var remindersCard: some View {
        HealthCard(tint: AppTheme.amber) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                OnboardingCardLabel(
                    title: "Injection reminders",
                    detail: remindersEnabled ? nil : "Optional"
                )
                Text("Get a reminder the day before each dose?")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if remindersEnabled {
                    Label {
                        Text("Reminders are on.")
                    } icon: {
                        Image(systemName: AppSymbol.Status.selectedCircle)
                    }
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.primary)
                    .transition(.opacity)
                    .accessibilityIdentifier("firstRunRemindersConfirmed")
                } else {
                    Button(action: turnOnReminders) {
                        Label {
                            Text(appLocalized("Turn on reminders"))
                        } icon: {
                            Image(systemName: AppSymbol.Health.reminder)
                        }
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.accentForeground)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppTheme.amber, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("firstRunRemindersTurnOn")

                    if remindersDeniedHint {
                        Text("To get dose reminders, allow notifications for Gaurava in Settings.")
                            .font(AppFont.micro)
                            .foregroundStyle(AppTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                            .accessibilityIdentifier("firstRunRemindersDeniedHint")
                    }
                }
            }
        }
    }

    /// The explicit, in-context opt-in: request authorization now (never as a launch
    /// side effect) and keep the per-device flag on only if granted. A denial shows
    /// the Settings hint; the schedule itself is reconciled by the save fan-out when
    /// onboarding commits, so nothing is scheduled here.
    private func turnOnReminders() {
        Task { @MainActor in
            if await InjectionReminderPermission.request() {
                SurfacePreferences().injectionRemindersEnabled = true
                withAnimation(.snappy(duration: 0.16)) {
                    remindersEnabled = true
                    remindersDeniedHint = false
                }
            } else {
                withAnimation(.snappy(duration: 0.16)) {
                    remindersDeniedHint = true
                }
            }
        }
    }

    // MARK: - Navigation

    private var progressModel: OnboardingProgressModel {
        if step == .welcome {
            return .hidden
        }
        if step == .status {
            return .setup
        }
        let steps = branchSteps(for: status ?? .unknown)
        let index = steps.firstIndex(of: step) ?? 0
        return .steps(count: steps.count, index: index)
    }

    private func branchSteps(for status: TreatmentStatus) -> [Screen] {
        Self.visibleScreens(for: status, healthAvailable: healthAvailable)
    }

    /// The CANONICAL per-branch screen sequence following the shared welcome → status
    /// preamble — the single sequence the Efficiency ratchet locks. It always counts
    /// `.numbersHealth`; `visibleScreens` filters it out on HealthKit-less devices, so
    /// the locked count never depends on the run environment. Static so it needs no
    /// view instance. The switch is intentionally `default`-less: a new
    /// `TreatmentStatus` case fails to compile here until it is added and re-baselined
    /// (see the Definition of Done).
    private static func branchScreens(for status: TreatmentStatus) -> [Screen] {
        switch status {
        case .startingNow:
            return [.startMedicine, .startDay, .reminders,
                    .numbersHealth, .numbersCurrent, .numbersStarting, .numbersGoal, .close]
        case .active:
            return [.activeLastDose, .activeMedicine, .reminders, .treatmentStart,
                    .numbersHealth, .numbersCurrent, .numbersStarting, .numbersGoal, .close]
        case .paused:
            return [.pausedContext,
                    .numbersHealth, .numbersCurrent, .numbersStarting, .numbersGoal, .close]
        case .unknown:
            return [.numbersHealth, .numbersCurrent, .numbersStarting, .numbersGoal, .close]
        }
    }

    /// The canonical sequence filtered for what actually renders on THIS device: the
    /// Apple Health step shows only when HealthKit is available. Pure + static so the
    /// seam is unit-testable in both states; navigation, progress, the gate, and the
    /// deep-link entry all key off this — while `branchStepCount` / the ratchet stays
    /// on the canonical `branchScreens`, so the locked count never depends on the run
    /// environment's HealthKit state.
    private static func visibleScreens(for status: TreatmentStatus, healthAvailable: Bool) -> [Screen] {
        branchScreens(for: status).filter { healthAvailable || $0 != .numbersHealth }
    }

    /// Count of the steps that actually render for a branch on a device with the
    /// given HealthKit availability. Internal (returns `Int`, leaking no private type)
    /// so the seam test can assert: equals the canonical `branchStepCount` when Health
    /// is available, and exactly one fewer (the hidden Apple Health step) when not.
    static func visibleStepCount(for status: TreatmentStatus, healthAvailable: Bool) -> Int {
        visibleScreens(for: status, healthAvailable: healthAvailable).count
    }

    /// Per-branch step count, including the terminal `.close`, derived from
    /// `branchScreens` so it cannot drift from the live flow. Internal (not
    /// `private`) so the onboarding Definition-of-Done ratchet test can lock today's
    /// counts: see `GauravaTests/OnboardingDefinitionOfDoneTests.swift` and
    /// `docs/onboarding-definition-of-done.md`.
    static func branchStepCount(for status: TreatmentStatus) -> Int {
        branchScreens(for: status).count
    }

    /// The final branch step commits; everything before it advances.
    private var isFinishStep: Bool {
        step != .status && step == branchSteps(for: status ?? .unknown).last
    }

    /// The mandatory gate. Continue stays disabled until the visible step's required
    /// field is valid; optional/exempt/navigational steps are always satisfied.
    /// `numbersGoal` reads the (seeded-on-entry) goal value, so ruler mode satisfies
    /// it with zero taps while typed mode blocks on a cleared field.
    private func isSatisfied(_ screen: Screen) -> Bool {
        switch screen {
        case .status: return status != nil
        case .treatmentStart: return treatmentStartProvided
        case .numbersCurrent: return Self.positiveWeight(currentWeight) != nil
        case .numbersStarting: return Self.positiveWeight(startingWeight) != nil
        case .numbersGoal: return Self.positiveWeight(goalWeight) != nil
        default: return true
        }
    }

    /// VoiceOver hint (a localization key) for the disabled Continue, naming what is
    /// needed so the block is explained rather than read as a dead button. Nil when
    /// the visible step is already satisfied.
    private var primaryDisabledHint: String? {
        guard !isSatisfied(step) else { return nil }
        switch step {
        case .status: return "Choose where you are to continue."
        case .treatmentStart: return "Pick when you started to continue."
        case .numbersCurrent: return "Enter your current weight to continue."
        case .numbersStarting: return "Enter your starting weight, or tap Same as today, to continue."
        case .numbersGoal: return "Set a goal to continue."
        default: return nil
        }
    }

    private var primaryTitle: String {
        if step == .welcome { return "Begin setup" }
        if step == .close { return "Open Gaurava" }
        return isFinishStep ? "Finish" : "Continue"
    }

    private var primaryIcon: String {
        if step == .welcome { return AppSymbol.Action.next }
        if step == .close { return AppSymbol.Action.next }
        return isFinishStep ? AppSymbol.Action.save : AppSymbol.Action.next
    }

    private func primaryActionForCurrentStep() {
        if step == .welcome {
            advance(to: .status)
        } else {
            primaryAction()
        }
    }

    private func primaryAction() {
        focusedField = nil
        if step == .status {
            if let first = branchSteps(for: status ?? .unknown).first {
                advance(to: first)
            } else {
                commit()
            }
            return
        }
        let steps = branchSteps(for: status ?? .unknown)
        if let i = steps.firstIndex(of: step), i + 1 < steps.count {
            advance(to: steps[i + 1])
        } else {
            commit()
        }
    }

    private func advance(to next: Screen) {
        navigationDirection = .forward
        history.append(step)
        // Seed the mandatory goal ruler to its anchored default on first entry so
        // Continue is satisfied with zero taps and the committed goal equals what the
        // ruler shows. Only when empty, so returning via Back never clobbers a value
        // the user already chose or typed.
        if next == .numbersGoal, Self.positiveWeight(goalWeight) == nil {
            goalWeight = Self.seededGoalString(currentWeight: currentWeight, startingWeight: startingWeight)
        }
        step = next
    }

    private func back() {
        focusedField = nil
        if let previous = history.popLast() {
            navigationDirection = .backward
            step = previous
        }
    }

    /// Display name for a stored 0-based (Sunday == 0) weekday. Uses
    /// `effectiveCalendar` so the name follows the in-app picker, not the system
    /// locale (see AppLocalization).
    private static func weekdayName(_ day: Int) -> String {
        AppLocalization.effectiveCalendar.weekdaySymbols[max(min(day, 6), 0)]
    }

    private static func weekdayInitial(_ day: Int) -> String {
        String(AppLocalization.effectiveCalendar.shortWeekdaySymbols[max(min(day, 6), 0)].prefix(1))
    }

    private static func value(of flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func status(forBranchToken token: String) -> TreatmentStatus? {
        switch token {
        case "startingNow": return .startingNow
        case "active": return .active
        case "paused": return .paused
        default: return nil
        }
    }

    private struct StepCopy { let title: String; let why: String? }

    private func headerCopy(for step: Screen) -> StepCopy? {
        switch step {
        case .welcome:
            return nil
        case .status:
            return StepCopy(
                title: "Started GLP-1 yet?",
                why: nil
            )
        case .startMedicine:
            return StepCopy(
                title: "Medicine",
                why: nil
            )
        case .startDay:
            return StepCopy(
                title: "Planning day?",
                why: "Optional. A plan only, no countdown yet."
            )
        case .reminders:
            return StepCopy(
                title: "Dose reminders?",
                why: "Optional. A nudge the day before each dose."
            )
        case .treatmentStart:
            return StepCopy(
                title: "When did you start?",
                why: "Your history baseline counts from this day."
            )
        case .numbersHealth:
            return StepCopy(
                title: "Bring your weights",
                why: "Import what you've already logged. Gaurava keeps it on your device — no Gaurava server, no analytics."
            )
        case .numbersCurrent:
            return StepCopy(
                title: "Today's weight",
                why: "Where you are right now."
            )
        case .numbersStarting:
            return StepCopy(
                title: "Where you began",
                why: "So your progress has a baseline to measure from."
            )
        case .numbersGoal:
            return StepCopy(
                title: "Where you're headed",
                why: "A direction you set — adjust it anytime in Care."
            )
        case .activeLastDose:
            return StepCopy(
                title: "Latest dose",
                why: "Your schedule counts from this dose."
            )
        case .activeMedicine:
            return StepCopy(
                title: "Medicine",
                why: nil
            )
        case .pausedContext:
            return StepCopy(
                title: "Paused",
                why: "No reminders. Resume anytime."
            )
        case .close:
            return StepCopy(
                title: "You're set.",
                why: "Private and on-device."
            )
        }
    }

    private var closeModel: OnboardingCloseModel {
        let resolvedStatus = status ?? .unknown
        let state = TreatmentScheduleEngine.state(
            status: resolvedStatus,
            anchorDate: resolvedStatus == .active && lastDoseProvided && confirmLatestDose ? lastDoseDate : nil,
            newestInjectionDate: nil,
            preferredInjectionDay: resolvedStatus == .startingNow && injectionDayEnabled ? preferredInjectionDay : nil,
            isPaused: resolvedStatus == .paused
        )

        switch state {
        case .planned:
            return OnboardingCloseModel(
                stateLabel: "Plan only",
                message: String(
                    format: appLocalized("Planned for every %@. No countdown yet."),
                    Self.weekdayName(preferredInjectionDay)
                ),
                systemImage: AppSymbol.Health.schedule,
                tint: AppTheme.primary
            )
        case let .scheduled(next, _):
            return OnboardingCloseModel(
                stateLabel: "Scheduled",
                message: String(
                    format: appLocalized("Your next dose is %@."),
                    next.appFormatted(.dateTime.day().month(.abbreviated))
                ),
                systemImage: AppSymbol.Status.comingUp,
                tint: AppTheme.medication
            )
        case .needsConfirmation:
            return OnboardingCloseModel(
                stateLabel: "Needs confirmation",
                message: appLocalized("Confirm your latest dose to start your schedule."),
                systemImage: AppSymbol.Status.needsLogging,
                tint: AppTheme.amber
            )
        case .paused:
            return OnboardingCloseModel(
                stateLabel: "Paused",
                message: appLocalized("Your schedule is paused."),
                systemImage: AppSymbol.Status.notScheduled,
                tint: AppTheme.blue
            )
        case .idle:
            if resolvedStatus == .startingNow {
                return OnboardingCloseModel(
                    stateLabel: "No plan yet",
                    message: appLocalized("Log your first jab when you're ready."),
                    systemImage: AppSymbol.Health.injection,
                    tint: AppTheme.primary
                )
            }
            return OnboardingCloseModel(
                stateLabel: "Details later",
                message: appLocalized("Add details anytime in Care."),
                systemImage: AppSymbol.Health.profile,
                tint: AppTheme.primary
            )
        }
    }

    /// The "Your setup" recap rows on the close screen (Option 1): up to three
    /// facts the user actually entered, reflected back. Only populated rows appear;
    /// if nothing optional was entered the recap is empty and the close screen
    /// falls back to its bare confirmation + the "What happens next" card.
    private var closeRecapRows: [CloseRecapRow] {
        let resolvedStatus = status ?? .unknown
        let current = Self.positiveWeight(currentWeight)
        let starting = Self.positiveWeight(startingWeight)
        let goal = Self.positiveWeight(goalWeight)
        var rows: [CloseRecapRow] = []

        func medicineValue() -> String? {
            guard let med = medicationChoice else { return nil }
            if let dose = doseChoice {
                return "\(med.displayName) \(doseText(dose))"
            }
            return med.displayName
        }
        func medicineRow() {
            if let value = medicineValue() {
                rows.append(CloseRecapRow(label: "Medicine", value: value, systemImage: AppSymbol.Health.dose, tint: AppTheme.medication))
            }
        }
        func dateValue(_ date: Date) -> String {
            date.appFormatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }

        switch resolvedStatus {
        case .active:
            medicineRow()
            if lastDoseProvided && confirmLatestDose {
                rows.append(CloseRecapRow(label: "Last dose", value: dateValue(lastDoseDate), systemImage: AppSymbol.Health.injection, tint: AppTheme.medication))
            }
            if let delta = weightDelta(current: current, starting: starting) {
                rows.append(CloseRecapRow(label: "Since start", value: delta, systemImage: AppSymbol.Health.weight, tint: AppTheme.blue))
            }
        case .startingNow:
            medicineRow()
            if injectionDayEnabled {
                rows.append(CloseRecapRow(label: "Plan day", value: Self.weekdayName(preferredInjectionDay), systemImage: AppSymbol.Health.schedule, tint: AppTheme.primary))
            }
            if let goal {
                rows.append(CloseRecapRow(label: "Goal weight", value: weightText(goal), systemImage: AppSymbol.Health.goal, tint: AppTheme.success))
            }
        case .paused:
            medicineRow()
            if pausedLastDoseProvided {
                rows.append(CloseRecapRow(label: "Last dose", value: dateValue(pausedLastDoseDate), systemImage: AppSymbol.Health.injection, tint: AppTheme.blue))
            }
        case .unknown:
            if let current {
                rows.append(CloseRecapRow(label: "Current weight", value: weightText(current), systemImage: AppSymbol.Health.currentWeight, tint: AppTheme.blue))
            }
            if let goal {
                rows.append(CloseRecapRow(label: "Goal weight", value: weightText(goal), systemImage: AppSymbol.Health.goal, tint: AppTheme.success))
            }
        }
        return Array(rows.prefix(3))
    }

    /// Signed weight change from starting → current, e.g. "−3.2 kg". Nil unless
    /// both are present and differ by a meaningful amount. Reuses the shared
    /// "%@ kg" string so the unit stays localized.
    private func weightDelta(current: Double?, starting: Double?) -> String? {
        guard let current, let starting else { return nil }
        let delta = current - starting
        guard abs(delta) >= 0.05 else { return nil }
        let magnitude = abs(delta).formatted(.number.precision(.fractionLength(0...1)))
        let signed = "\(delta < 0 ? "−" : "+")\(magnitude)"
        return appLocalizedValue("\(signed) kg")
    }

    // MARK: - Persistence (UNCHANGED contract)

    /// Kick the deferred Apple Health import once first-run has completed. We never
    /// pull mid-onboarding (it would insert WeightEntry rows, flip `hasAnyData`, and
    /// eject the flow), so the connect step only set the opt-in; this runs the actual
    /// history import as the app opens. Self-gates on the per-device flag, so it is a
    /// no-op unless the user connected Apple Health during setup.
    private func importHealthAfterOnboarding() {
        Task { @MainActor in await HealthKitWeightSync.syncIfEnabled(context: modelContext) }
    }

    private func commit() {
        focusedField = nil

        let resolvedStatus = status ?? .unknown
        let current = Self.positiveWeight(currentWeight)
        // Starting weight falls back to current so the timeline has a baseline.
        let starting = Self.positiveWeight(startingWeight) ?? current
        let goal = Self.positiveWeight(goalWeight)

        // Build a profile only when a profile-level fact was actually given, so we
        // never write an all-zero TrackerProfile that would falsely report
        // `hasProfile`. A chosen status, medication, dose, the optional injection
        // day, or any anchor each counts as a profile-level fact.
        let providesProfile = resolvedStatus != .unknown
            || starting != nil
            || goal != nil
            || treatmentStartProvided
            || injectionDayEnabled
            || medicationChoice != nil
            || doseChoice != nil

        if providesProfile {
            let profile = TrackerProfile()
            if let starting { profile.startingWeightKg = starting }
            if let goal { profile.goalWeightKg = goal }
            if let medicationChoice { profile.medicationRaw = medicationChoice.rawValue }
            if let doseChoice {
                profile.plannedDoseMg = doseChoice
                profile.plannedDoseUpdatedAt = Date()
            }
            if resolvedStatus != .unknown { profile.treatmentStatus = resolvedStatus }
            if injectionDayEnabled { profile.preferredInjectionDay = preferredInjectionDay }

            applyStatusContract(to: profile, status: resolvedStatus)

            profile.updatedAt = Date()
            modelContext.insert(profile)
        }

        materializeWeights(starting: starting, current: current)
        materializeLatestDose(status: resolvedStatus)

        if resolvedStatus == .paused {
            modelContext.insert(TreatmentPause(startedAt: Date(), reason: "onboarding"))
        }

        ModelWriteService.save(modelContext)
        hasCompletedFirstRun = true
        importHealthAfterOnboarding()
    }

    /// Encode the schedule contract for the chosen status: the most recent
    /// CONFIRMED dose is the only thing allowed to anchor the schedule.
    private func applyStatusContract(to profile: TrackerProfile, status: TreatmentStatus) {
        switch status {
        case .startingNow:
            if injectionDayEnabled { profile.scheduleAnchorState = .plannedWeekday }
        case .active:
            if treatmentStartProvided {
                profile.treatmentStartDate = treatmentStartDate
                profile.treatmentStartProvided = true
            }
            if lastDoseProvided && confirmLatestDose {
                profile.scheduleAnchorDate = lastDoseDate
                profile.scheduleAnchorDoseMg = doseChoice
                profile.scheduleAnchorSite = OnboardingForm.resolvedSite(lastDoseSiteSelection)
                profile.scheduleAnchorUpdatedAt = Date()
                profile.scheduleAnchorState = .confirmedLatestDose
            } else {
                // On treatment but no confirmed recent dose: ask later, never overdue.
                profile.scheduleAnchorState = .unknown
            }
        case .paused:
            if pausedLastDoseProvided {
                profile.scheduleAnchorDate = pausedLastDoseDate
                profile.scheduleAnchorUpdatedAt = Date()
            }
            profile.scheduleAnchorState = .paused
        case .unknown:
            break
        }
    }

    /// Materialize honest, dated weight checkpoints so Results can chart the
    /// journey. The current weight becomes today's entry; the starting weight
    /// becomes a dated entry at the confirmed treatment start, collapsing a
    /// same-day duplicate so we never manufacture a second point just to force a
    /// chart. Runs only on a fresh install (the gate requires no existing data),
    /// so there is no imported baseline to overwrite.
    private func materializeWeights(starting: Double?, current: Double?) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let starting, treatmentStartProvided {
            let startDay = calendar.startOfDay(for: treatmentStartDate)
            let duplicatesToday = startDay == today
                && (current.map { abs($0 - starting) < 0.0001 } ?? false)
            if startDay < today && !duplicatesToday {
                modelContext.insert(WeightEntry(
                    weightKg: starting,
                    recordedAt: treatmentStartDate,
                    timeZoneIdentifier: TimeZone.current.identifier,
                    notes: nil,
                    clientMutationId: "onboarding-starting-weight"
                ))
            }
        }

        if let current {
            modelContext.insert(WeightEntry(
                weightKg: current,
                recordedAt: Date(),
                timeZoneIdentifier: TimeZone.current.identifier,
                clientMutationId: "onboarding-current-weight"
            ))
        }
    }

    /// Record the active user's CONFIRMED most-recent dose as a real jab so the Jabs
    /// timeline reflects the fact the user already gave us, instead of an empty "Log
    /// each jab to build your history" prompt sitting next to a live countdown. The
    /// date/site come from the Latest-dose screen and the dose from the Medicine
    /// screen. The schedule is unaffected: `applyStatusContract` still sets the
    /// confirmed-latest-dose anchor, and `TreatmentScheduleEngine` keys off
    /// `max(newestInjection, scheduleAnchorDate)` — both equal `lastDoseDate` here, so
    /// the countdown is identical (no double count). Gated on a KNOWN dose: without
    /// one we cannot write a truthful jab (`InjectionEntry.doseMg` is required), so we
    /// fall back to the prior anchor-only behavior. Runs only on a fresh install (the
    /// gate requires no existing data); a stable `clientMutationId` mirrors
    /// `materializeWeights` for idempotency.
    private func materializeLatestDose(status: TreatmentStatus) {
        guard status == .active,
              lastDoseProvided,
              confirmLatestDose,
              let dose = doseChoice else { return }

        modelContext.insert(InjectionEntry(
            doseMg: dose,
            injectionSite: OnboardingForm.resolvedSite(lastDoseSiteSelection) ?? "",
            injectionDate: lastDoseDate,
            timeZoneIdentifier: TimeZone.current.identifier,
            clientMutationId: "onboarding-latest-dose"
        ))
    }

    /// The goal ruler's anchored default as a stored string, so entering the
    /// mandatory goal screen satisfies Continue immediately and the committed goal
    /// equals what the ruler displays. Mirrors `GoalWeightRuler`'s reference
    /// precedence (current, else starting) via a shared static so the two never drift.
    private static func seededGoalString(currentWeight: String, startingWeight: String) -> String {
        let reference = positiveWeight(currentWeight) ?? positiveWeight(startingWeight)
        return String(format: "%.1f", GoalWeightRuler.anchoredDefaultKg(reference: reference))
    }

    private static func positiveWeight(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed > 0 else { return nil }
        return parsed
    }
}

private struct OnboardingStepSpec {
    let id: String
    let title: String?
    let body: String?
    let tint: Color
    let systemImage: String
    let showsHero: Bool
}

private struct OnboardingCloseModel {
    let stateLabel: String
    let message: String
    let systemImage: String
    let tint: Color
}

/// One reflected-back fact on the close screen's "Your setup" recap (Option 1).
/// `label` is a localization key; `value` is already display-ready (localized
/// medicine name, formatted date, or a formatted weight/delta).
private struct CloseRecapRow: Identifiable {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color
    var id: String { label }
}

private enum OnboardingProgressModel {
    case hidden
    case setup
    case steps(count: Int, index: Int)

    var isHidden: Bool {
        if case .hidden = self { return true }
        return false
    }
}

private struct OnboardingShell<Content: View>: View {
    let spec: OnboardingStepSpec
    let canGoBack: Bool
    let progress: OnboardingProgressModel
    let primaryTitle: String
    let primaryIcon: String
    let primaryIdentifier: String
    let primaryDisabled: Bool
    /// Localization key read by VoiceOver when Continue is disabled, so the block is
    /// explained rather than presented as a dead button. Nil when enabled.
    let primaryDisabledHint: String?
    let actionsHidden: Bool
    let navigationDirection: FirstRunSetupView.NavigationDirection
    let reduceMotion: Bool
    let back: () -> Void
    let primary: () -> Void
    let content: Content

    init(
        spec: OnboardingStepSpec,
        canGoBack: Bool,
        progress: OnboardingProgressModel,
        primaryTitle: String,
        primaryIcon: String,
        primaryIdentifier: String,
        primaryDisabled: Bool,
        primaryDisabledHint: String?,
        actionsHidden: Bool,
        navigationDirection: FirstRunSetupView.NavigationDirection,
        reduceMotion: Bool,
        back: @escaping () -> Void,
        primary: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.spec = spec
        self.canGoBack = canGoBack
        self.progress = progress
        self.primaryTitle = primaryTitle
        self.primaryIcon = primaryIcon
        self.primaryIdentifier = primaryIdentifier
        self.primaryDisabled = primaryDisabled
        self.primaryDisabledHint = primaryDisabledHint
        self.actionsHidden = actionsHidden
        self.navigationDirection = navigationDirection
        self.reduceMotion = reduceMotion
        self.back = back
        self.primary = primary
        self.content = content()
    }

    /// Approximate height the bottom action bar reserves, so the centered content
    /// region can sit in the visible band above it. The bar is now primary-only — the
    /// "Set up later" secondary was removed everywhere by the hard gate.
    private var bottomReserve: CGFloat { 80 }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if !progress.isHidden || canGoBack {
                            OnboardingTopBar(canGoBack: canGoBack, progress: progress, back: back)
                                .id("top")
                                .padding(.top, AppSpacing.xs)
                        } else {
                            Color.clear.frame(height: 1).id("top")
                        }

                        // Seat the step content in the upper third instead of pinned
                        // beneath the top bar. One flexible spacer above and TWO below
                        // split the free vertical space 1:2, so the hero block's top
                        // lands ~a third of the way down. This replaces the old fixed
                        // top gap, which read as a void above the Continue button once
                        // the weight step was split into one decision per screen (sparse
                        // content jammed under the progress bar). The min gap keeps the
                        // hero clear of the progress dots; Welcome/Close/Status keep their
                        // own centered, branded layout (a single spacer each → centered).
                        if spec.showsHero {
                            Spacer(minLength: AppSpacing.xxl)
                        } else {
                            Spacer(minLength: 20)
                        }

                        VStack(alignment: .leading, spacing: AppSpacing.xl) {
                            if spec.showsHero {
                                OnboardingHeroHeader(spec: spec)
                            }
                            content
                            if spec.showsHero {
                                Text("Change later in Care.")
                                    .font(AppFont.micro)
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, AppSpacing.xs)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(spec.id)
                        .transition(stepTransition)

                        Spacer(minLength: 20)
                        if spec.showsHero {
                            // The second half of the 1:2 split that biases hero steps to
                            // the upper third (see the leading spacer's note above).
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(minHeight: geo.size.height - bottomReserve, alignment: .top)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.sm)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) {
                    if !actionsHidden {
                        OnboardingActionBar(
                            primaryTitle: primaryTitle,
                            primaryIcon: primaryIcon,
                            primaryIdentifier: primaryIdentifier,
                            tint: AppTheme.primary,
                            primaryDisabled: primaryDisabled,
                            primaryDisabledHint: primaryDisabledHint,
                            primary: primary
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: actionsHidden)
                .onChange(of: spec.id) { _, _ in
                    guard spec.showsHero || spec.id == "close" else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertion: Edge = navigationDirection == .forward ? .trailing : .leading
        let removal: Edge = navigationDirection == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }
}

private struct OnboardingTopBar: View {
    let canGoBack: Bool
    let progress: OnboardingProgressModel
    let back: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if canGoBack {
                Button("Back", systemImage: "chevron.left", action: back)
                    .font(.body.weight(.semibold))
                    .labelStyle(.iconOnly)
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.glassSurface.opacity(0.72), in: Circle())
                    .overlay(Circle().stroke(AppTheme.stroke, lineWidth: 1))
                    .glassEffect(.regular.tint(AppTheme.primary.opacity(0.06)), in: .circle)
                    .accessibilityIdentifier("firstRunBack")
            } else {
                Color.clear.frame(width: 34, height: 34)
            }

            Spacer()
            progressView
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        switch progress {
        case .hidden:
            EmptyView()
        case .setup:
            Text("Setup")
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.muted)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(AppTheme.glassSurface.opacity(0.72), in: Capsule())
                .overlay(Capsule().stroke(AppTheme.stroke, lineWidth: 1))
                .glassEffect(.regular.tint(AppTheme.primary.opacity(0.06)), in: .capsule)
        case let .steps(count, index):
            HStack(spacing: AppSpacing.sm) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? AppTheme.primary : AppTheme.stroke)
                        .frame(width: i == index ? 22 : 7, height: 7)
                        .animation(.snappy(duration: 0.25), value: index)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

private struct OnboardingHeroHeader: View {
    let spec: OnboardingStepSpec

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Image(systemName: spec.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentForeground)
                .frame(width: 46, height: 46)
                .background(spec.tint.gradient, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .shadow(color: spec.tint.opacity(0.3), radius: 8, x: 0, y: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if let title = spec.title {
                    Text(appLocalized(title))
                        .font(.system(.title, design: .serif, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let body = spec.body {
                    Text(appLocalized(body))
                        .font(.body)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingActionBar: View {
    let primaryTitle: String
    let primaryIcon: String
    let primaryIdentifier: String
    let tint: Color
    let primaryDisabled: Bool
    let primaryDisabledHint: String?
    let primary: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            // System prominent Liquid Glass: pressed shimmer, disabled dimming,
            // and Reduce Transparency fallback all come from the platform.
            Button(action: primary) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: primaryIcon)
                        .font(AppFont.bodyStrong)
                        .accessibilityHidden(true)
                    Text(appLocalized(primaryTitle))
                        .font(AppFont.bodyStrong)
                }
                .foregroundStyle(AppTheme.accentForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .disabled(primaryDisabled)
            .accessibilityIdentifier(primaryIdentifier)
            .accessibilityHint(primaryDisabledHint.map { Text(appLocalized($0)) } ?? Text(verbatim: ""))
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.md)
        .background {
            // A soft fade to the page tone so scrolling form content reads cleanly
            // under the floating actions — no muddy tinted band.
            LinearGradient(
                colors: [AppTheme.healthSurface.opacity(0), AppTheme.healthSurface.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

private struct OnboardingCloseContent: View {
    let model: OnboardingCloseModel
    var recapRows: [CloseRecapRow] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sealArrived = false

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: AppSymbol.Status.verified)
                    .font(.system(size: AppIconSize.seal, weight: .semibold))
                    .foregroundStyle(AppTheme.success)
                    .symbolEffect(.bounce, options: .nonRepeating, value: sealArrived)
                    .frame(width: 76, height: 76)
                    .background(AppTheme.success.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(AppTheme.success.opacity(0.18), lineWidth: 1))
                    .glassEffect(.regular.tint(AppTheme.success.opacity(0.10)), in: .circle)
                    .accessibilityHidden(true)
                    .onAppear {
                        guard !reduceMotion else { return }
                        sealArrived = true
                    }

                VStack(spacing: AppSpacing.sm) {
                    Text(appLocalized("You're set."))
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(appLocalized("Private and on-device."))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !recapRows.isEmpty {
                HealthCard(tint: AppTheme.primary, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text(appLocalized("Your setup"))
                            .font(AppFont.micro)
                            .textCase(.uppercase)
                            .foregroundStyle(AppTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(recapRows) { row in
                            InfoRow(title: row.label, value: row.value, systemImage: row.systemImage, tint: row.tint)
                        }
                    }
                }
                .accessibilityIdentifier("firstRunCloseSetupRecap")
            }

            HealthCard(tint: model.tint, cornerRadius: AppRadius.card, padding: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
                        Text(appLocalized("What happens next"))
                            .font(AppFont.micro)
                            .textCase(.uppercase)
                            .foregroundStyle(AppTheme.textTertiary)
                        Spacer(minLength: 8)
                        Text(appLocalized(model.stateLabel))
                            .font(AppFont.micro)
                            .foregroundStyle(model.tint)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .background(model.tint.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(model.tint.opacity(0.18), lineWidth: 1))
                    }

                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        Image(systemName: model.systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(model.tint)
                            .frame(width: 36, height: 36)
                            .background(model.tint.opacity(0.12), in: Circle())
                            .accessibilityHidden(true)

                        Text(model.message)
                            .font(AppFont.body)
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("firstRunCloseNextState")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.sm)
        .accessibilityIdentifier("firstRunClose")
    }
}

/// The Status step, redesigned to the new arrangement: the question leads,
/// centered (the shared icon hero is skipped for this step), with the two choices
/// as large, full-width, centered rows below. Same copy, our palette/type — only
/// the layout/positioning changed. The shared `OnboardingChoiceRow` (used by the
/// Medicine step) is intentionally left untouched; this step uses its own row.
private struct StartingPointSelector: View {
    @Binding var selection: TreatmentStatus?

    private struct Option: Identifiable {
        let status: TreatmentStatus
        let token: String
        let title: String

        var id: String { token }
    }

    private let options = [
        Option(status: .startingNow, token: "startingNow", title: "Not yet"),
        Option(status: .active, token: "active", title: "Yes, I've started")
    ]

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: AppSpacing.md) {
                // Eyebrow + headline read as one unit (tight 8pt), the subtitle a
                // step below (12pt). The eyebrow uses the app's section-header idiom
                // (uppercase, tracked, tertiary), centered for this hero step.
                VStack(spacing: AppSpacing.sm) {
                    Text(appLocalized("A quick question"))
                        .font(AppFont.label)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.textTertiary)

                    questionHeadline
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                Text(appLocalized("This shapes your next few steps."))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.md) {
                ForEach(options) { option in
                    StatusChoiceRow(
                        title: appLocalized(option.title),
                        isSelected: selection == option.status,
                        accessibilityID: "firstRunTreatmentStatus-\(option.token)"
                    ) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selection = option.status
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The question headline with a serif-italic accent on the emphasised word. The
    /// copy is ONE localized string carrying its own emphasis marker —
    /// "Have you *started* GLP-1 yet?" — so each language emphasises its own word
    /// from a single catalog key. Splitting on "*" yields [head, accent, tail]; the
    /// accent run renders serif-italic in our primary green, the rest stays in the
    /// app's rounded ink title. A translation without a single "*…*" pair renders
    /// plain (full text, no accent) rather than dropping characters.
    ///
    /// Built as a concatenated `AttributedString` rather than `Text + Text`: under
    /// this target's strict build, `Text + Text` is deprecated (iOS 26) and the
    /// AttributedString dynamic-member attribute setters (`run.font = …`) are
    /// rejected as non-Sendable key-path captures (StrictConcurrency). The
    /// attribute-key-TYPE subscript used here forms no key path, so it compiles.
    private var questionHeadline: Text {
        let base = Font.system(.largeTitle, design: .serif, weight: .bold)
        let accent = Font.system(.largeTitle, design: .serif, weight: .semibold).italic()

        func styled(_ string: String, font: Font, color: Color) -> AttributedString {
            var piece = AttributedString(string)
            piece[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = font
            piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = color
            return piece
        }

        let raw = appLocalized("Have you *started* GLP-1 yet?")
        let parts = raw.components(separatedBy: "*")
        guard parts.count == 3 else {
            return Text(styled(raw.replacingOccurrences(of: "*", with: ""), font: base, color: AppTheme.ink))
        }
        var headline = styled(parts[0], font: base, color: AppTheme.ink)
        headline.append(styled(parts[1], font: accent, color: AppTheme.primary))
        headline.append(styled(parts[2], font: base, color: AppTheme.ink))
        return Text(headline)
    }
}

/// The Status step's "pick one" row: a large, full-width, centered choice with no
/// icon. Selection lifts it with the same tint-wash + border language as the rest
/// of onboarding, in our palette.
private struct StatusChoiceRow: View {
    let title: String
    let isSelected: Bool
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background {
                    shape.fill(AppTheme.healthSurface)
                    if isSelected {
                        shape.fill(
                            LinearGradient(
                                colors: [AppTheme.primary.opacity(0.16), AppTheme.primary.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .overlay(shape.stroke(isSelected ? AppTheme.primary.opacity(0.45) : AppTheme.stroke, lineWidth: isSelected ? 1.5 : 1))
                .shadow(color: AppTheme.shadow.opacity(isSelected ? 0.2 : 0.1), radius: isSelected ? 12 : 8, x: 0, y: isSelected ? 6 : 4)
                .contentShape(shape)
        }
        .buttonStyle(AppPressableButtonStyle())
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct OnboardingCardLabel: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Text(appLocalized(title))
                .font(AppFont.micro)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.textTertiary)
            Spacer(minLength: 8)
            if let detail {
                Text(appLocalized(detail))
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }
}

/// Small helpers shared by the onboarding form and its reused Care surface.
enum OnboardingForm {
    /// Sentinel selection meaning "I don't know the site" → persisted as nil.
    static let unknownSite = "__unknown__"

    static func resolvedSite(_ selection: String) -> String? {
        selection == unknownSite ? nil : selection
    }

    /// Stable accessibility token for a dose: 2.5 -> "2_5", 0.25 -> "0_25", 5 -> "5".
    static func doseToken(_ dose: Double) -> String {
        let base = dose == dose.rounded() ? String(Int(dose)) : String(dose)
        return base.replacingOccurrences(of: ".", with: "_")
    }

    /// Locale-aware "Today / Yesterday / 2 days ago" label for a day offset
    /// (0 = today, -1 = yesterday). Uses RelativeDateTimeFormatter's named style so
    /// it translates for free (verified, Dash docset v24703); the beginning-of-
    /// sentence context capitalizes it correctly for a standalone chip.
    static func relativeDayLabel(_ dayOffset: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.formattingContext = .beginningOfSentence
        return formatter.localizedString(from: DateComponents(day: dayOffset))
    }
}

/// One-tap recent-day chips for the latest-dose step: Today / Yesterday /
/// 2 days ago / Pick a date. Most users onboarding mid-treatment dosed within the
/// last few days, so presets beat a date picker. Tapping a preset sets the bound
/// date to the start of that day and marks it provided; "Pick a date" opens the
/// shared calendar sheet for anything older.
private struct DateQuickPickChips: View {
    @Binding var date: Date
    @Binding var provided: Bool
    let idPrefix: String
    var tint: Color = AppTheme.medication
    var range: ClosedRange<Date> = Date.distantPast...Date()
    /// Day offsets for the quick chips (0 = today). Default keeps the last-dose
    /// presets (today / yesterday / 2 days ago); the treatment-start screen passes a
    /// wider span. Chip a11y ids stay `\(idPrefix)Preset\(abs(offset))`.
    var presetOffsets: [Int] = [0, -1, -2]
    /// Title for the "Pick a date" calendar sheet (e.g. "Treatment start").
    var sheetTitle: String = "Most recent dose"

    @State private var showingCalendar = false
    private let calendar = Calendar.current

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 2),
            spacing: AppSpacing.sm
        ) {
            ForEach(presetOffsets, id: \.self) { offset in
                chip(
                    label: OnboardingForm.relativeDayLabel(offset),
                    selected: provided && isOffset(offset),
                    id: "\(idPrefix)Preset\(abs(offset))"
                ) {
                    if let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            date = day
                            provided = true
                        }
                    }
                }
            }
            chip(
                label: appLocalized("Pick a date"),
                selected: provided && !isAnyPreset,
                id: "\(idPrefix)Pick"
            ) {
                showingCalendar = true
            }
        }
        .sheet(isPresented: $showingCalendar) {
            OnboardingCalendarSheet(
                title: sheetTitle,
                date: $date,
                provided: $provided,
                range: range,
                idPrefix: idPrefix
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func isOffset(_ offset: Int) -> Bool {
        guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) else {
            return false
        }
        return calendar.isDate(date, inSameDayAs: day)
    }

    private var isAnyPreset: Bool {
        presetOffsets.contains { isOffset($0) }
    }

    private func chip(label: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(AppFont.label)
                .foregroundStyle(selected ? AppTheme.ink : AppTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(AppType.minScale)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    selected ? tint.opacity(0.20) : AppTheme.actionSurface.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(selected ? tint.opacity(0.5) : AppTheme.stroke.opacity(0.58), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }
}

/// A controlled date row that opens a graphical calendar in a sheet and tracks
/// "provided" separately from the bound Date. Replaces the inline DatePicker that
/// used to stay stuck open over the form. Because DatePicker binds only a Date
/// (verified, Dash docset v24703), selecting a day OR tapping Done both record
/// that the date was provided — so accepting today's default is never lost.
enum OnboardingDateRowStyle: Equatable {
    case card
    case embedded
}

struct OnboardingDateRow: View {
    let title: String
    let systemImage: String
    @Binding var date: Date
    @Binding var provided: Bool
    let idPrefix: String
    var range: ClosedRange<Date> = Date.distantPast...Date()
    var style: OnboardingDateRowStyle = .card

    @State private var showingCalendar = false

    var body: some View {
        Button {
            showingCalendar = true
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(provided ? AppTheme.primary : AppTheme.muted)
                    .frame(width: 36, height: 36)
                    .background((provided ? AppTheme.primary : AppTheme.muted).opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(appLocalized(title))
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.ink)
                    Text(provided ? date.appFormatted(.dateTime.month(.abbreviated).day().year()) : appLocalized("Not selected"))
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 8)
                if provided {
                    Image(systemName: AppSymbol.Status.selectedCircle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                } else {
                    Text("Choose")
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .padding(style == .card ? 12 : 0)
            .frame(minHeight: style == .embedded ? 56 : nil)
            .background(dateRowBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.control)
                    .stroke(dateRowStroke, lineWidth: style == .card ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(idPrefix)Row")
        .sheet(isPresented: $showingCalendar) {
            OnboardingCalendarSheet(
                title: title,
                date: $date,
                provided: $provided,
                range: range,
                idPrefix: idPrefix
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var dateRowBackground: Color {
        style == .card ? AppTheme.actionSurface.opacity(0.72) : .clear
    }

    private var dateRowStroke: Color {
        guard style == .card else { return .clear }
        return provided ? AppTheme.primary.opacity(0.35) : AppTheme.stroke
    }
}

/// The one onboarding modal: a graphical calendar with a visible Done. Selecting
/// a day auto-confirms and dismisses; Done is the fallback for accepting the
/// default date.
private struct OnboardingCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var date: Date
    @Binding var provided: Bool
    let range: ClosedRange<Date>
    let idPrefix: String

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    appLocalized(title),
                    selection: $date,
                    in: range,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(AppTheme.primary)
                .labelsHidden()
                .padding()
                .accessibilityIdentifier("\(idPrefix)Calendar")
                .onChange(of: date) { _, _ in
                    provided = true
                    dismiss()
                }
                Spacer(minLength: 0)
            }
            .background(AppBackground())
            .navigationTitle(appLocalized(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        provided = true
                        dismiss()
                    }
                    .accessibilityIdentifier("\(idPrefix)Done")
                }
            }
        }
    }
}

// MARK: - Welcome building block (brand + value only)

/// The first screen of onboarding. Same content, palette, and type as before —
/// only the layout was updated to the redesigned arrangement: the brand mark in a
/// circular badge, the name promoted to the title, the value line as a subtitle,
/// the privacy promise broken into three one-line trust rows, and the records-only
/// note in a calm pill. The primary action lives in the shared
/// `OnboardingActionBar`, so this view is content-only.
private struct WelcomeIdentityScreen: View {
    /// Brand moment: a calmer, more open rhythm than the standard AppSpacing scale
    /// (which tops out at 24). 32pt between the four groups (badge / identity /
    /// trust / safety) stays on the 8pt grid while giving the hero room to breathe;
    /// inside each group spacing stays small so the grouping reads by proximity.
    private let groupSpacing: CGFloat = 32

    var body: some View {
        VStack(spacing: groupSpacing) {
            brandBadge

            // Identity: the brand name leads, the value line sits under it (one group).
            VStack(spacing: AppSpacing.md) {
                Text("Gaurava")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("firstRunWelcomeBrand")

                Text(appLocalized("Private GLP-1 tracking."))
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("firstRunWelcomeHeadline")
            }

            // The same privacy promise, now one calm row per point.
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                trustRow(AppSymbol.Legal.privacy, "On your device")
                trustRow("icloud.fill", "Private iCloud sync")
                trustRow("person.fill", "No account")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("firstRunWelcomeTrustLine")

            // The records-only promise, contained in a quiet pill.
            Text(appLocalized("Records only. No dosing advice."))
                .font(AppFont.label)
                .foregroundStyle(AppTheme.medication)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppTheme.medication.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(AppTheme.medication.opacity(0.22), lineWidth: 1))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("firstRunWelcomeSafetyLine")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, AppSpacing.xl)
    }

    /// The brand mark in a circular badge, keeping the app's Liquid Glass depth
    /// language (the previous seal was a rounded rectangle).
    private var brandBadge: some View {
        GauravaBrandMark()
            .frame(width: 64, height: 64)
            .padding(AppSpacing.xxl)
            .glassEffect(.regular.tint(AppTheme.primary.opacity(0.12)), in: .circle)
            .overlay(Circle().stroke(AppTheme.stroke, lineWidth: 1))
            .shadow(color: AppTheme.shadow.opacity(0.18), radius: 18, x: 0, y: 10)
            .accessibilityHidden(true)
    }

    private func trustRow(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(appLocalized(text))
                .font(AppFont.body)
                .foregroundStyle(AppTheme.ink)
        }
    }
}
