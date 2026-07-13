import SwiftUI

/// Ruler picker for choosing a goal weight during onboarding.
///
/// Goal weight is a decision, not a reported fact, so it gets an explorable
/// control where current/starting weight stay typed fields. Three contracts:
///
///   • Nothing is committed until the user moves the ruler — onboarding's goal
///     stays optional, and an untouched ruler writes no value.
///   • The caption anchors the choice to today ("11.5 kg below today"), never
///     to an abstract ideal.
///   • Built on native ScrollView physics (momentum + `viewAligned` snapping
///     to 0.5 kg ticks) with a selection tick per snap; VoiceOver gets a
///     standard adjustable element instead of the scroll surface.
struct GoalWeightRuler: View {
    /// The chosen goal in kilograms. nil until the user interacts.
    @Binding var valueKg: Double?
    /// Today's weight (current, else starting) used for the caption anchor and
    /// the ruler's initial position.
    var referenceKg: Double?

    @State private var centeredTick: Int?
    @State private var hasInteracted = false

    private static let minKg = 35.0
    private static let maxKg = 250.0
    private static let stepKg = 0.5
    private static let tickSpacing: CGFloat = 12
    private static let tickCount = Int(((maxKg - minKg) / stepKg).rounded())

    var body: some View {
        VStack(alignment: .center, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                if let valueKg {
                    Text(valueKg.formatted(.number.precision(.fractionLength(1))))
                        .font(AppFont.display)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                        .contentTransition(.numericText())
                        .animation(.default, value: valueKg)
                    Text("kg")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.muted)
                } else {
                    // Untouched: show "Not set" rather than the resting number, so
                    // the parked ruler can never read as a chosen goal. The user
                    // must slide to commit a value (goal stays genuinely optional).
                    Text(appLocalized("Not set"))
                        .font(AppFont.display)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(AppType.minScale)
                }
            }
            .frame(maxWidth: .infinity)

            Text(caption)
                .font(AppFont.micro)
                .foregroundStyle(valueKg == nil ? AppTheme.textTertiary : AppTheme.primary)
                .lineLimit(1)
                .minimumScaleFactor(AppType.minScale)
                .frame(maxWidth: .infinity)

            ruler
        }
        .sensoryFeedback(.selection, trigger: centeredTick) { _, _ in hasInteracted }
        .onAppear {
            if centeredTick == nil {
                centeredTick = Self.tick(for: valueKg ?? defaultCandidateKg)
            }
        }
        .onChange(of: centeredTick) { _, tick in
            guard hasInteracted, let tick else { return }
            valueKg = Self.kg(for: tick)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appLocalized("Goal weight"))
        .accessibilityValue(valueKg.map { weightText($0) } ?? appLocalized("Not set"))
        .accessibilityHint(appLocalized("Swipe up or down to adjust"))
        .accessibilityAdjustableAction { direction in
            let base = valueKg ?? defaultCandidateKg
            let next = direction == .increment ? base + Self.stepKg : base - Self.stepKg
            let clamped = min(max(next, Self.minKg), Self.maxKg)
            hasInteracted = true
            valueKg = clamped
            centeredTick = Self.tick(for: clamped)
        }
        .accessibilityIdentifier("firstRunGoalRuler")
    }

    private var ruler: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0...Self.tickCount, id: \.self) { tick in
                        TickMark(tick: tick)
                            .id(tick)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredTick, anchor: .center)
            .contentMargins(.horizontal, max(0, (proxy.size.width - Self.tickSpacing) / 2), for: .scrollContent)
            .simultaneousGesture(
                DragGesture(minimumDistance: 1).onChanged { _ in hasInteracted = true }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppTheme.primary)
                    .frame(width: 3, height: 30)
                    .allowsHitTesting(false)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .frame(height: 64)
    }

    private var caption: String {
        guard let valueKg else {
            return appLocalized("Optional — slide to choose")
        }
        guard let referenceKg else {
            return appLocalized("Goal set")
        }
        let delta = referenceKg - valueKg
        if abs(delta) < Self.stepKg / 2 {
            return appLocalized("At today's weight")
        }
        return delta > 0
            ? appLocalizedValue("\(weightText(delta)) below today")
            : appLocalizedValue("\(weightText(abs(delta))) above today")
    }

    /// Where the ruler rests before any interaction: 10% under today's weight when
    /// known (a common, modest first framing), else mid-range. Static so onboarding's
    /// mandatory goal screen can seed exactly the value the ruler will show and
    /// commit — the two must not drift.
    static func anchoredDefaultKg(reference: Double?) -> Double {
        guard let reference else { return 75 }
        let candidate = (reference * 0.9 / stepKg).rounded() * stepKg
        return min(max(candidate, minKg), maxKg)
    }

    private var defaultCandidateKg: Double {
        Self.anchoredDefaultKg(reference: referenceKg)
    }

    private static func kg(for tick: Int) -> Double {
        minKg + Double(tick) * stepKg
    }

    private static func tick(for kg: Double) -> Int {
        let clamped = min(max(kg, minKg), maxKg)
        return Int(((clamped - minKg) / stepKg).rounded())
    }
}

/// One 0.5 kg ruler tick: tall with a numeral every 5 kg, medium on whole
/// kilograms, short otherwise.
private struct TickMark: View {
    let tick: Int

    private var kg: Double { 35.0 + Double(tick) * 0.5 }
    private var isMajor: Bool { tick % 10 == 0 }
    private var isWhole: Bool { tick % 2 == 0 }

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 0.75)
                .fill(isMajor ? AppTheme.textTertiary : AppTheme.separator)
                .frame(width: 1.5, height: isMajor ? 22 : (isWhole ? 14 : 8))
                .frame(height: 22, alignment: .bottom)

            Text(isMajor ? "\(Int(kg))" : " ")
                .font(AppFont.micro)
                .monospacedDigit()
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize()
                .frame(width: 1)
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}

#Preview("Goal ruler") {
    struct Host: View {
        @State var value: Double?
        var body: some View {
            VStack(spacing: 30) {
                GoalWeightRuler(valueKg: $value, referenceKg: 86.5)
                GoalWeightRuler(valueKg: .constant(75), referenceKg: 86.5)
            }
            .padding()
            .background(AppBackground())
        }
    }
    return Host()
}
