import SwiftUI

struct SideEffectBoard: View {
    let symptoms: [SymptomCapture]
    let allClear: Bool
    let onToggleSymptom: (SideEffectKind) -> Void
    let onSetSeverity: (SideEffectKind, SeverityLevel?) -> Void
    let onToggleAllClear: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var hasRecordedDetails: Bool {
        allClear || !symptoms.isEmpty
    }

    private var shouldShowBody: Bool {
        isExpanded || hasRecordedDetails
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggleExpanded) {
                let tint = hasRecordedDetails ? AppTheme.success : AppTheme.primary
                ThemedActionSurface(tint: tint, isActive: hasRecordedDetails, cornerRadius: 18, minHeight: nil) { surface in
                    HStack(spacing: 10) {
                        Image(systemName: hasRecordedDetails ? AppSymbol.Status.selectedCircle : AppSymbol.Action.add)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(surface.iconForeground)
                            .frame(width: 30, height: 30)
                            .background(surface.iconBackground, in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            // Reuses the Log-tab "Anything else?" title key (identical text +
                            // translations); a disambiguated duplicate key collides with the
                            // "Anything else? Side effects" a11y label at the String Catalog
                            // symbol level (STRING_CATALOG_GENERATE_SYMBOLS), breaking a clean build.
                            Text(appLocalized("Anything else?"))
                                .font(AppFont.bodyStrong)
                                .foregroundStyle(surface.foreground)
                            Text(summaryText)
                                .font(AppFont.micro)
                                .foregroundStyle(surface.secondaryForeground)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: AppSymbol.Action.disclosure)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(surface.disclosureForeground)
                            .rotationEffect(.degrees(shouldShowBody ? 90 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appLocalized("Anything else? Side effects"))
            .accessibilityValue(summaryText)
            .accessibilityHint(shouldShowBody ? appLocalized("Double tap to collapse side effects") : appLocalized("Double tap to add side effects"))
            .accessibilityIdentifier("side-effect-disclosure")

            if shouldShowBody {
                VStack(alignment: .leading, spacing: 10) {
                    PickerAllClearRow(isOn: allClear, action: onToggleAllClear)

                    VStack(spacing: 9) {
                        ForEach(SideEffectKind.allCases) { kind in
                            let capture = symptoms.first { $0.kind == kind }
                            SideEffectPickerRow(
                                kind: kind,
                                severity: capture?.severity,
                                isOn: capture != nil,
                                differentiateWithoutColor: differentiateWithoutColor,
                                onToggle: {
                                    onToggleSymptom(kind)
                                },
                                onSetSeverity: { severity in
                                    onSetSeverity(kind, severity)
                                }
                            )
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: symptoms.map(\.kind.rawValue))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: symptoms.map { $0.severity?.rawValue ?? "" })
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: allClear)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isExpanded)
    }

    private var summaryText: String {
        if allClear {
            return appLocalized("No side effects recorded")
        }
        if symptoms.isEmpty {
            return appLocalized("Optional, only if something changed")
        }
        if symptoms.count == 1, let first = symptoms.first {
            return appLocalized(first.kind.label)
        }
        return appLocalizedValue("\(symptoms.count) side effects recorded")
    }

    private func toggleExpanded() {
        isExpanded.toggle()
    }
}

struct SideEffectPicker: View {
    let symptoms: [SymptomCapture]
    let allClear: Bool
    let onToggleSymptom: (SideEffectKind) -> Void
    let onSetSeverity: (SideEffectKind, SeverityLevel?) -> Void
    let onToggleAllClear: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Side effects")
                        .font(AppFont.heroTitle)
                        .foregroundStyle(AppTheme.ink)
                    Text("Choose only what changed today. Severity can stay blank.")
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.bottom, 4)

                PickerAllClearRow(isOn: allClear, action: onToggleAllClear)

                VStack(spacing: 9) {
                    ForEach(SideEffectKind.allCases) { kind in
                        let capture = symptoms.first { $0.kind == kind }
                        SideEffectPickerRow(
                            kind: kind,
                            severity: capture?.severity,
                            isOn: capture != nil,
                            differentiateWithoutColor: differentiateWithoutColor,
                            onToggle: {
                                onToggleSymptom(kind)
                            },
                            onSetSeverity: { severity in
                                onSetSeverity(kind, severity)
                            }
                        )
                    }
                }
            }
            .padding(20)
        }
        .background(AppBackground())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: symptoms.map(\.kind.rawValue))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: symptoms.map { $0.severity?.rawValue ?? "" })
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: allClear)
        .accessibilityIdentifier("side-effect-picker")
    }
}

private struct SideEffectActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(appLocalized(title), systemImage: systemImage)
                .font(AppFont.bodyStrong)
                .foregroundStyle(isSelected ? AppTheme.accentForeground : tint)
                .lineLimit(1)
                .minimumScaleFactor(AppType.minScale)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(isSelected ? tint : tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(isSelected ? 0.0 : 0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

private struct SideEffectSummaryPill: View {
    let symptom: SymptomCapture

    private var tint: Color {
        symptom.severity?.logTint ?? symptom.kind.logTint
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symptom.severity?.logSymbol ?? symptom.kind.systemImage)
                .font(.system(size: AppIconSize.chip, weight: .bold))
            Text(title)
                .font(AppFont.micro)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
    }

    private var title: String {
        guard let severity = symptom.severity else {
            return appLocalized(symptom.kind.label)
        }
        return appLocalizedValue("\(appLocalized(symptom.kind.label)) · \(appLocalized(severity.short))")
    }
}

private struct PickerAllClearRow: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isOn ? AppSymbol.Status.selectedCircle : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isOn ? AppTheme.success : AppTheme.textTertiary)

                Text(appLocalized("No side effects"))
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(isOn ? AppTheme.success : AppTheme.ink)

                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? AppTheme.success.opacity(0.10) : AppTheme.healthSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? AppTheme.success.opacity(0.40) : AppTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(isOn ? appLocalized("No side effects, recorded") : appLocalized("No side effects"))
        .accessibilityHint(appLocalized("Double tap to record no side effects today"))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("side-effect-all-clear")
    }
}

private struct SideEffectPickerRow: View {
    let kind: SideEffectKind
    let severity: SeverityLevel?
    let isOn: Bool
    let differentiateWithoutColor: Bool
    let onToggle: () -> Void
    let onSetSeverity: (SeverityLevel?) -> Void

    private var rowTint: Color {
        severity?.logTint ?? AppTheme.primary
    }

    private var statusSystemImage: String {
        guard isOn else { return "plus.circle" }
        return severity == nil ? "minus.circle" : AppSymbol.Status.selectedCircle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 11) {
                    SymptomOrb(
                        systemImage: kind.systemImage,
                        symptomTint: kind.logTint,
                        selectedTint: rowTint,
                        isOn: isOn,
                        hasSeverity: severity != nil,
                        differentiateWithoutColor: differentiateWithoutColor
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLocalized(kind.label))
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(AppTheme.ink)
                        if let severity {
                            Text(appLocalized(severity.label))
                                .font(AppFont.micro)
                                .foregroundStyle(severity.logTint)
                        } else if isOn {
                            Text(appLocalized("No severity chosen"))
                                .font(AppFont.micro)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: statusSystemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isOn ? rowTint : AppTheme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isOn)
            .accessibilityLabel(appLocalized(kind.label))
            .accessibilityValue(accessibilityValueText)
            .accessibilityHint(isOn ? appLocalized("Double tap to clear") : appLocalized("Double tap to note"))
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("side-effect-chip-\(kind.rawValue)")

            if isOn {
                HStack(spacing: 8) {
                    ForEach(SeverityLevel.allCases) { choice in
                        SeverityChoiceButton(
                            severity: choice,
                            isSelected: severity == choice,
                            action: {
                                onSetSeverity(severity == choice ? nil : choice)
                            }
                        )
                        .accessibilityIdentifier("severity-choice-\(kind.rawValue)-\(choice.rawValue)")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(rowStroke, lineWidth: isOn ? 1.25 : 1)
        )
        .shadow(color: AppTheme.shadow.opacity(isOn ? 0.10 : 0.04), radius: isOn ? 7 : 3, x: 0, y: 3)
        .accessibilityElement(children: .contain)
    }

    private var rowBackground: Color {
        guard isOn else { return AppTheme.healthSurface }
        guard let severity else { return AppTheme.actionSurface.opacity(0.75) }
        return severity.logTint.opacity(0.08)
    }

    private var rowStroke: Color {
        guard isOn else { return AppTheme.stroke }
        guard let severity else { return AppTheme.primary.opacity(0.24) }
        return severity.logTint.opacity(0.34)
    }

    private var accessibilityValueText: String {
        guard isOn else { return appLocalized("Not noted") }
        guard let severity else { return appLocalized("Noted, no severity chosen") }
        return appLocalizedValue("Noted, \(appLocalized(severity.label))")
    }
}

private struct SymptomOrb: View {
    let systemImage: String
    let symptomTint: Color
    let selectedTint: Color
    let isOn: Bool
    let hasSeverity: Bool
    let differentiateWithoutColor: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(orbFill)
            Circle()
                .strokeBorder(orbStroke, lineWidth: 1)
            Image(systemName: systemImage)
                .font(.system(size: AppIconSize.small, weight: .semibold))
                .foregroundStyle(isOn ? symptomTint : AppTheme.textTertiary)
            if differentiateWithoutColor && isOn {
                Circle()
                    .fill(hasSeverity ? selectedTint : AppTheme.primary)
                    .frame(width: 5, height: 5)
                    .offset(x: 10, y: -10)
            }
        }
        .frame(width: 38, height: 38)
    }

    private var orbFill: Color {
        guard isOn else { return AppTheme.actionSurface }
        return hasSeverity ? selectedTint.opacity(0.18) : AppTheme.healthSurface
    }

    private var orbStroke: Color {
        guard isOn else { return AppTheme.stroke }
        return hasSeverity ? selectedTint.opacity(0.40) : AppTheme.primary.opacity(0.28)
    }
}

private struct SeverityChoiceButton: View {
    let severity: SeverityLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: severity.logSymbol)
                    .font(.system(size: AppIconSize.chip, weight: .bold))
                    .foregroundStyle(isSelected ? AppTheme.accentForeground : severity.logTint)
                Text(appLocalized(severity.short))
                    .font(AppFont.micro)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScale)
                    .foregroundStyle(isSelected ? AppTheme.accentForeground : AppTheme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(isSelected ? severity.logTint : AppTheme.healthSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : AppTheme.stroke, lineWidth: 1))
            .shadow(color: AppTheme.shadow.opacity(isSelected ? 0.10 : 0.0), radius: isSelected ? 5 : 0, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(appLocalized(severity.label))
        .accessibilityHint(isSelected ? appLocalized("Double tap to clear intensity") : appLocalized("Double tap to record this intensity"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension SideEffectKind {
    var systemImage: String {
        switch self {
        case .nausea: return "face.dashed"
        case .vomiting: return "drop.triangle"
        case .constipation: return "timer"
        case .diarrhea: return "waveform.path.ecg"
        }
    }

    var logTint: Color {
        switch self {
        case .nausea: return AppTheme.medication
        case .vomiting: return AppTheme.danger
        case .constipation: return AppTheme.attention
        case .diarrhea: return AppTheme.weight
        }
    }
}

extension SeverityLevel {
    var logTint: Color {
        switch self {
        case .mild: return AppTheme.medication
        case .moderate: return AppTheme.attention
        case .severe: return AppTheme.danger
        }
    }

    var logSymbol: String {
        switch self {
        case .mild: return "circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .severe: return "exclamationmark.triangle.fill"
        }
    }
}
