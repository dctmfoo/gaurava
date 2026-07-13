import SwiftUI

/// The unified quick-add entry point: a `tabViewBottomAccessory` bar riding the
/// floating tab bar on every tab, so the two most frequent actions (log a jab,
/// log a weight) plus a daily note are always one tap away. Taps route through
/// the same state the `gaurava://` deep links set, so the existing sheets and
/// tab-selection behavior are reused unchanged (see issue #13 and
/// docs/quick-add-entry-design.html).
struct QuickAddBar: View {
    /// System placement: `.inline` when the tab bar collapses on scroll, where
    /// horizontal space is tight and the chips drop their text labels.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let select: (QuickAddAction) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(QuickAddAction.allCases) { action in
                chip(for: action)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .frame(maxWidth: .infinity)
    }

    private func chip(for action: QuickAddAction) -> some View {
        Button {
            select(action)
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: action.systemImage)
                    .font(.caption.weight(.bold))
                if placement != .inline {
                    Text(appLocalized(action.title))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(AppType.minScale)
                }
            }
            .foregroundStyle(action.tint)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(action.tint.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(AppPressableButtonStyle())
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }
}

/// The quick-add bar's actions, ordered by logging frequency. Each maps onto an
/// existing capture surface; the bar introduces no new capture UI.
enum QuickAddAction: CaseIterable, Identifiable {
    case jab
    case weight
    case note

    var id: Self { self }

    var title: String {
        switch self {
        case .jab: "Injection"
        case .weight: "Weight"
        case .note: "Daily note"
        }
    }

    var systemImage: String {
        switch self {
        case .jab: AppSymbol.Health.injection
        case .weight: AppSymbol.Health.weight
        case .note: AppSymbol.Health.dailyNote
        }
    }

    var tint: Color {
        switch self {
        case .jab: AppTheme.medication
        case .weight: AppTheme.blue
        case .note: AppTheme.primary
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .jab: "quickAdd-jab"
        case .weight: "quickAdd-weight"
        case .note: "quickAdd-note"
        }
    }
}
