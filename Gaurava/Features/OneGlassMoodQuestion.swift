import SwiftUI

/// "How's today?" mood capture.
///
/// Both states live in one `GlassEffectContainer` and share a namespace, so the
/// glass material of the chosen face blends (via `glassEffectID`) into the single
/// confirmed mood orb instead of hard-cutting. Colour is one teal hue rising in
/// chroma (no traffic-light palette), and the weather glyph Magic-Replaces.
///
/// The two states are NOT given explicit `.transition` modifiers: an earlier
/// version scaled the whole bead row toward centre (`.scale(anchor: .center)`)
/// on a fast 0.15s curve while the orb sprang in over ~0.46s, so the two
/// competing motions read as a glitchy "snap to centre." Letting the container +
/// `glassEffectID` drive the change (only the `withAnimation` spring below)
/// produces one calm crossfade.
struct OneGlassMoodQuestion: View {
    let selection: MoodValence?
    let onCommit: (MoodValence?) -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var moodNamespace
    @State private var visualSelection: MoodValence?
    @State private var hasSyncedSelection = false
    @State private var isChoosing = false
    @State private var commitFeedback = 0

    private var activeSelection: MoodValence? {
        hasSyncedSelection ? visualSelection : selection
    }

    private var shouldShowConfirmation: Bool {
        activeSelection != nil && !isChoosing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PromptSymbol(mood: activeSelection)

                Text(appLocalized("How's today?"))
                    .font(AppFont.heroTitle)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScale)
            }

            GlassEffectContainer(spacing: 22) {
                // Fixed height + top alignment so the surrounding card never
                // resizes between the bead row and the (taller) orb state — the
                // chosen face grows into the orb in place instead of pushing the
                // box open.
                ZStack(alignment: .top) {
                    if let activeSelection, shouldShowConfirmation {
                        MoodOrbConfirmation(
                            mood: activeSelection,
                            namespace: moodNamespace,
                            differentiateWithoutColor: differentiateWithoutColor,
                            action: beginChoosing
                        )
                        .accessibilityIdentifier("mood-confirmation-pill")
                    } else {
                        MoodBeadRow(
                            active: activeSelection,
                            namespace: moodNamespace,
                            differentiateWithoutColor: differentiateWithoutColor,
                            onPick: { commit($0) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .top)
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: commitFeedback)
        .onAppear(perform: syncSelectionFromModel)
        .onChange(of: selection?.rawValue) { _, _ in
            syncSelectionFromModel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("one-glass-mood-question")
    }

    private func beginChoosing() {
        let shouldClearPersistedSelection = activeSelection != nil

        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84)) {
            visualSelection = nil
            hasSyncedSelection = true
            isChoosing = true
        }

        if shouldClearPersistedSelection {
            onCommit(nil)
        }
    }

    private func commit(_ mood: MoodValence?) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.82)) {
            visualSelection = mood
            hasSyncedSelection = true
            isChoosing = false
        }
        onCommit(mood)
        if mood != nil {
            commitFeedback += 1
        }
    }

    private func syncSelectionFromModel() {
        guard !isChoosing else { return }
        guard visualSelection != selection || !hasSyncedSelection else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visualSelection = selection
            hasSyncedSelection = true
        }
    }
}

// MARK: - Prompt symbol

private struct PromptSymbol: View {
    let mood: MoodValence?

    var body: some View {
        Image(systemName: mood?.moodQuestionSymbol ?? "face.smiling")
            .font(.system(size: AppIconSize.large, weight: .semibold))
            .foregroundStyle(mood?.moodQuestionTint ?? AppTheme.primary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 42, height: 42)
            .background((mood?.moodQuestionTint ?? AppTheme.primary).opacity(0.13), in: Circle())
            .overlay(Circle().stroke((mood?.moodQuestionTint ?? AppTheme.primary).opacity(0.25), lineWidth: 1))
            // No always-on `.breathe` here: a continuously active symbol effect
            // keeps a ViewGraph display link alive, and every tick re-renders the
            // hero-card subtree — including re-dashing the note button's stroke
            // for shadow resolution — which competed with scrolling (profiled:
            // CG::dasher under updateShadow on every frame while idle).
            .accessibilityHidden(true)
    }
}

// MARK: - Choosing state (five glass beads)

private struct MoodBeadRow: View {
    let active: MoodValence?
    let namespace: Namespace.ID
    let differentiateWithoutColor: Bool
    let onPick: (MoodValence) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MoodValence.allCases) { mood in
                MoodBead(
                    mood: mood,
                    isSelected: active == mood,
                    namespace: namespace,
                    differentiateWithoutColor: differentiateWithoutColor,
                    action: { onPick(mood) }
                )
                .accessibilityIdentifier("mood-face-\(mood.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MoodBead: View {
    let mood: MoodValence
    let isSelected: Bool
    let namespace: Namespace.ID
    let differentiateWithoutColor: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: mood.moodQuestionSymbol)
                    .font(.system(size: AppIconSize.large, weight: .semibold))
                    .foregroundStyle(mood.moodQuestionTint)
                    .frame(width: 46, height: 46)
                    .glassEffect(
                        .regular.tint(mood.moodQuestionTint.opacity(isSelected ? 0.30 : 0.16)),
                        in: .circle
                    )
                    .glassEffectID("mood-\(mood.rawValue)", in: namespace)
                    .overlay(alignment: .topTrailing) {
                        if differentiateWithoutColor && isSelected {
                            Circle()
                                .fill(mood.moodQuestionTint)
                                .frame(width: 7, height: 7)
                                .offset(x: -1, y: 1)
                        }
                    }

                Text(appLocalized(mood.label))
                    .font(AppFont.micro)
                    .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScaleTight)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appLocalized(mood.label))
        .accessibilityHint(isSelected ? appLocalized("Double tap to keep this sense of day") : appLocalized("Double tap to log this sense of day"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Confirmed state (centered mood orb)

private struct MoodOrbConfirmation: View {
    let mood: MoodValence
    let namespace: Namespace.ID
    let differentiateWithoutColor: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                MoodOrb(
                    mood: mood,
                    size: 62,
                    namespace: namespace,
                    differentiateWithoutColor: differentiateWithoutColor
                )

                Text(appLocalized(mood.label))
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(AppType.minScale)

                Text(appLocalized("Tap to change"))
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(appLocalizedValue("Logged, \(appLocalized(mood.label))"))
        .accessibilityHint(appLocalized("Double tap to show the mood choices"))
    }
}

private struct MoodOrb: View {
    let mood: MoodValence
    let size: CGFloat
    let namespace: Namespace.ID
    let differentiateWithoutColor: Bool

    var body: some View {
        Image(systemName: mood.moodQuestionSymbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(mood.moodQuestionTint)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(mood.moodQuestionTint.opacity(0.26)), in: .circle)
            .glassEffectID("mood-\(mood.rawValue)", in: namespace)
            .overlay(alignment: .topTrailing) {
                if differentiateWithoutColor {
                    Circle()
                        .fill(mood.moodQuestionTint)
                        .frame(width: 8, height: 8)
                        .offset(x: -2, y: 2)
                }
            }
            .shadow(color: AppTheme.shadow.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Mood visual mapping

extension MoodValence {
    /// Single calm teal valence ramp (see `AppTheme.mood*`). Deliberately not a
    /// red→green palette — see the app design rules.
    var moodQuestionTint: Color {
        switch self {
        case .rough: return AppTheme.moodRough
        case .low: return AppTheme.moodLow
        case .okay: return AppTheme.moodOkay
        case .good: return AppTheme.moodGood
        case .great: return AppTheme.moodGreat
        }
    }

    var moodQuestionSymbol: String {
        switch self {
        case .rough: return "cloud.rain.fill"
        case .low: return "cloud.fill"
        case .okay: return "circle.lefthalf.filled"
        case .good: return "sun.min.fill"
        case .great: return "sun.max.fill"
        }
    }
}

#Preview("One Glass Mood") {
    VStack(spacing: 28) {
        OneGlassMoodQuestion(selection: nil) { _ in }
        OneGlassMoodQuestion(selection: .good) { _ in }
        OneGlassMoodQuestion(selection: .great) { _ in }
    }
    .padding()
    .background(AppBackground())
}
