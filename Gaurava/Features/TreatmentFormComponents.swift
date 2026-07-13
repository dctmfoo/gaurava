import SwiftUI

// Reusable treatment-form building blocks, authored once and surfaced in both
// first-run onboarding and the Care > Treatment "update details" sheet, so there
// is one calm component vocabulary (see docs/onboarding-issues-and-fixes.html,
// "Onboarding Flow & Surfaces"). The accessibility identifiers keep the
// firstRun* names the plan's test hooks expect; only one of these surfaces is on
// screen at a time, so the shared identifiers never collide.

/// The three soft, selectable treatment-status rows. A nil binding means nothing
/// is chosen — a calm un-nagged state, not an error.
struct TreatmentStatusSelector: View {
    @Binding var selection: TreatmentStatus?
    /// Onboarding appends an explicit "I'm not sure" row (→ `.unknown`) so a
    /// dignified "decide later" is a visible choice, not just an empty Continue.
    /// Care's update-details sheet leaves this off (default).
    var includeUnsure: Bool = false

    private struct Option: Identifiable {
        let value: TreatmentStatus
        let title: String
        let subtitle: String
        let token: String
        let systemImage: String
        let tint: Color
        var id: String { token }
    }

    private var options: [Option] {
        var rows: [Option] = [
            Option(
                value: .startingNow,
                title: "Just starting",
                subtitle: "No dose logged yet",
                token: "startingNow",
                systemImage: AppSymbol.Health.start,
                tint: AppTheme.primary
            ),
            Option(
                value: .active,
                title: "Already on treatment",
                subtitle: "I've taken at least one dose",
                token: "active",
                systemImage: AppSymbol.Health.injection,
                tint: AppTheme.medication
            ),
            Option(
                value: .paused,
                title: "Taking a break",
                subtitle: "Paused for now",
                token: "paused",
                systemImage: "pause.circle",
                tint: AppTheme.blue
            )
        ]
        if includeUnsure {
            rows.append(Option(
                value: .unknown,
                title: "Not sure yet",
                subtitle: "Keep setup unscheduled",
                token: "unsure",
                systemImage: AppSymbol.Status.notScheduled,
                tint: AppTheme.muted
            ))
        }
        return rows
    }

    var body: some View {
        // NOTE: no container-level accessibilityIdentifier here — on a container it
        // propagates down and overrides each row's own `firstRunTreatmentStatus-<token>`
        // identifier (verified via the XCUITest a11y hierarchy), which breaks
        // per-row selection in UI tests.
        VStack(spacing: 8) {
            ForEach(options) { option in
                row(option)
            }
        }
    }

    private func row(_ option: Option) -> some View {
        let selected = selection == option.value
        return Button {
            withAnimation(.easeInOut(duration: 0.24)) {
                selection = selected ? nil : option.value
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(option.tint)
                    .frame(width: 40, height: 40)
                    .background(option.tint.opacity(selected ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(appLocalized(option.title))
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.ink)
                    Text(appLocalized(option.subtitle))
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? AppSymbol.Status.selectedCircle : AppSymbol.Status.unselectedCircle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? option.tint : AppTheme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? option.tint.opacity(0.12) : AppTheme.actionSurface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? option.tint.opacity(0.42) : AppTheme.stroke, lineWidth: 1)
            )
            .scaleEffect(selected ? 0.992 : 1)
        }
        .buttonStyle(.plain)
        // Combine the icon + title + subtitle into one button element so XCUITest
        // can resolve the row by its identifier (a plain Button with a multi-element
        // label is otherwise exposed as an `.other`, not a queryable `.button`).
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appLocalized(option.title)), \(appLocalized(option.subtitle))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("firstRunTreatmentStatus-\(option.token)")
    }
}

/// A large, tappable "pick one" row — the calm choice idiom shared by the
/// onboarding Status and Medicine steps so the two read as one interaction (the
/// hero-wash + circle-check language, see docs/onboarding-redesign-mockups.html).
/// Callers pass display-ready strings (already localized, or brand proper nouns).
struct OnboardingChoiceRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        Button(action: action) {
            HStack(spacing: AppSpacing.lg) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(isSelected ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(verbatim: title)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(AppFont.micro)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: isSelected ? AppSymbol.Status.selectedCircle : AppSymbol.Status.unselectedCircle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? tint : AppTheme.textTertiary.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(AppTheme.healthSurface)
                if isSelected {
                    // Same wash language as HeroCard: choosing lifts the card into
                    // the hero tier.
                    shape.fill(
                        LinearGradient(
                            colors: [tint.opacity(0.16), tint.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .overlay(shape.stroke(isSelected ? tint.opacity(0.45) : AppTheme.stroke, lineWidth: isSelected ? 1.5 : 1))
            .shadow(color: AppTheme.shadow.opacity(isSelected ? 0.2 : 0.1), radius: isSelected ? 12 : 8, x: 0, y: isSelected ? 6 : 4)
            .contentShape(shape)
        }
        .buttonStyle(AppPressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(accessibilityID)
    }
}

/// Two-option medication picker with no pre-pick (nil = unknown). Tapping the
/// chosen medicine again clears it so unknown stays reachable. Redesigned from a
/// skinny segmented control to two `OnboardingChoiceRow`s so it matches the
/// Status step's "pick one" idiom and gives the decision real presence.
struct MedicationSegment: View {
    @Binding var selection: Medication?
    /// Called after the selection changes — e.g. to reset a dependent dose.
    var onChange: () -> Void = {}

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(Medication.allCases) { med in
                OnboardingChoiceRow(
                    title: med.displayName,
                    subtitle: Self.brandExamples(med),
                    systemImage: AppSymbol.Health.dose,
                    tint: AppTheme.medication,
                    isSelected: selection == med,
                    accessibilityID: "firstRunMedication-\(med.rawValue)"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = (selection == med) ? nil : med
                        onChange()
                    }
                }
            }
        }
    }

    /// Common brand names per molecule. Proper nouns — intentionally NOT localized
    /// (rendered verbatim) — they only help the user recognize their medicine.
    private static func brandExamples(_ med: Medication) -> String {
        switch med {
        case .tirzepatide: return "Mounjaro · Zepbound"
        case .semaglutide: return "Ozempic · Wegovy"
        }
    }
}

/// Dose-ladder chips for a medication, with no pre-selected value (nil = unknown).
struct DoseChips: View {
    let medication: Medication
    @Binding var selection: Double?

    var body: some View {
        LazyVGrid(columns: doseColumns, spacing: 8) {
            ForEach(medication.dosePresets, id: \.self) { dose in
                chip(dose)
            }
        }
    }

    private var doseColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    }

    private func chip(_ dose: Double) -> some View {
        let selected = selection.map { abs($0 - dose) < 0.0001 } ?? false
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection = selected ? nil : dose
            }
        } label: {
            Text(doseText(dose))
                .font(AppFont.label)
                .foregroundStyle(selected ? AppTheme.ink : AppTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    selected ? AppTheme.medication.opacity(0.20) : AppTheme.actionSurface.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? AppTheme.medication.opacity(0.50) : AppTheme.stroke.opacity(0.58), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("firstRunDose-\(OnboardingForm.doseToken(dose))")
    }
}

/// Horizontal chips that wrap to a vertical stack when they will not fit. Shared
/// by onboarding, the welcome hero, and the Care treatment sheet.
struct TreatmentFlowWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    content(item)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    content(item)
                }
            }
        }
    }
}
