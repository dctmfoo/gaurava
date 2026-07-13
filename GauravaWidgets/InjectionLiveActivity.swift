import ActivityKit
import SwiftUI
import WidgetKit

// Injection-day Live Activity presentation (Build 4).
//
// Renders the app-owned GauravaInjectionActivityAttributes on the Lock Screen,
// in the Dynamic Island (compact / minimal / expanded), and Smart-Stack-friendly
// banners. The extension only RENDERS: the app starts / updates / ends the
// activity and bakes privacy into the state, so a hidden dose/site simply isn't
// present here. Brand styling reuses the widget-local WidgetTheme — no app-target
// design tokens (the extension is a separate module).
//
// The completion action is a pure route: a `Link` (and the whole-activity
// `widgetURL`) to `gaurava://jab-confirm`, which opens the app to the prefilled
// Add Injection confirmation. Per Apple's interactivity guidance, opening the
// app uses Link/widgetURL rather than Button(intent:). It writes nothing
// clinical; the user taps Save in the app.
struct GauravaInjectionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GauravaInjectionActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(WidgetTheme.healthSurface.opacity(0.92))
                .activitySystemActionForegroundColor(WidgetTheme.healthPrimary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(.widgetBrandGaurava, systemImage: WidgetSymbol.injection)
                        .font(WidgetFont.header)
                        .foregroundStyle(WidgetTheme.healthPrimary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.shortStatusLabel)
                        .font(WidgetFont.metric)
                        .foregroundStyle(state.isCompleted ? WidgetTheme.success : WidgetTheme.medication)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.localizedStatusPhrase)
                        .font(WidgetFont.cardTitle)
                        .foregroundStyle(WidgetTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.isCompleted {
                        DetailRow(state: state)
                    } else {
                        VStack(spacing: 8) {
                            DetailRow(state: state)
                            CompletionLink()
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: WidgetSymbol.injection)
                    .foregroundStyle(WidgetTheme.medication)
            } compactTrailing: {
                Text(state.shortStatusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.isCompleted ? WidgetTheme.success : WidgetTheme.medication)
            } minimal: {
                Image(systemName: state.isCompleted ? "checkmark.circle.fill" : WidgetSymbol.injection)
                    .foregroundStyle(state.isCompleted ? WidgetTheme.success : WidgetTheme.medication)
            }
            .widgetURL(GauravaScreen.jabConfirm.url)
            .keylineTint(WidgetTheme.healthPrimary)
        }
    }
}

// MARK: - Lock Screen / banner

private struct LockScreenView: View {
    let state: GauravaInjectionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(.widgetBrandGaurava, systemImage: WidgetSymbol.injection)
                    .font(WidgetFont.header)
                    .foregroundStyle(WidgetTheme.healthPrimary)
                Spacer(minLength: 0)
                Text(state.lockScreenStatusLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WidgetTheme.textSecondary)
            }

            Text(state.localizedStatusPhrase)
                .font(WidgetFont.cardTitle)
                .foregroundStyle(WidgetTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            DetailRow(state: state)

            if !state.isCompleted {
                CompletionLink()
            }
        }
        .padding(16)
    }
}

// MARK: - Shared pieces

// Dose + suggested site, each shown only when the producer included it (privacy).
private struct DetailRow: View {
    let state: GauravaInjectionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            if let dose = state.doseMg {
                Label(doseText(dose), systemImage: WidgetSymbol.dose)
                    .foregroundStyle(WidgetTheme.medication)
            }
            if let site = state.suggestedSite {
                Label(site, systemImage: WidgetSymbol.site)
                    .foregroundStyle(WidgetTheme.healthPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if state.doseMg == nil && state.suggestedSite == nil {
                Text(.liveActivityOpenDetails)
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .font(WidgetFont.metric)
    }

    private func doseText(_ dose: Double) -> String {
        let formatted = dose.formatted(.number.precision(.fractionLength(0...2)))
        return String(localized: .liveActivityDoseMg(formatted))
    }
}

// "Mark done" — a pure route to the prefilled in-app confirmation.
private struct CompletionLink: View {
    var body: some View {
        Link(destination: GauravaScreen.jabConfirm.url) {
            Text(.liveActivityMarkDone)
                .font(WidgetFont.metric)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(WidgetTheme.healthPrimary.opacity(0.16), in: Capsule())
                .foregroundStyle(WidgetTheme.healthPrimary)
        }
    }
}

private extension GauravaInjectionActivityAttributes.ContentState {
    var shortStatusLabel: LocalizedStringResource {
        isCompleted ? .liveActivityLabelDone : .liveActivityLabelDue
    }

    var lockScreenStatusLabel: LocalizedStringResource {
        isCompleted ? .liveActivityLabelLogged : .liveActivityLabelInjectionDay
    }
}
