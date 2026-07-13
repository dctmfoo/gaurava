import SwiftUI

// Gaurava on the wrist — Phase 1 read-only glance, schedule-forward direction.
//
// The glance answers "when is my next dose?" by sharing the widget hero words:
// "Today", "Tomorrow", or the day count. Dose and site stay as supporting
// details beneath the hero, and weight progress is a quiet hairline strip at the
// foot. One hero, no competing ring, fits a 42mm screen below the clock. Flat
// layout in a `ScrollView` for Digital Crown
// scrolling (only needed for large Dynamic Type) — never a nested `TabView`
// (a documented watchOS memory leak). `WatchTheme` only; no UIKit.
//
// Graceful degradation as slices drop out of the privacy-shaped display:
//   • dose hidden, schedule known → countdown number becomes the hero instead
//   • no snapshot      → "Open Gaurava"     (placeholder)
//   • expired snapshot → "Open to refresh"  (never silently-stale numbers)
//   • no schedule yet  → "No dose scheduled"
//   • due / overdue    → status reads "dose due"; site/progress shown if present
struct WatchRootView: View {
    let store: WatchGlanceStore

    private var display: GlanceDisplay {
        GlanceDisplayModel.make(from: store.snapshot, family: .systemSmall)
    }

    var body: some View {
        ScrollView {
            WatchGlanceBody(display: display)
        }
        .background(WatchSurfaceBackground())
    }
}

/// The scrollable glance content, factored out of `WatchRootView` so it can be
/// rendered without the enclosing `ScrollView` — `ImageRenderer` collapses a
/// `ScrollView` to zero height, so the marketing surface-snapshot target renders
/// this directly over `WatchSurfaceBackground`. No behaviour change for the app.
struct WatchGlanceBody: View {
    let display: GlanceDisplay

    var body: some View {
        VStack(spacing: 12) {
            Hero(display: display)
            if let fraction = display.progressFraction {
                ProgressStrip(
                    fraction: fraction,
                    percentText: display.progressPercentText ?? "",
                    weightText: display.currentWeightText
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

/// Schedule-forward hero. Prefers "Today" / "Tomorrow" / day count so the wrist
/// mirrors the widget glance; dose and site remain visible as supporting facts.
/// With no schedule (or a stale/placeholder snapshot) it collapses to a single
/// calm status line.
private struct Hero: View {
    let display: GlanceDisplay

    var body: some View {
        if let hero = display.heroDayText {
            VStack(spacing: 4) {
                kicker(display.dayCountCaption ?? display.statusPhrase)
                Text(hero)
                    .font(WatchFont.hero(hero.count > 2 ? 30 : 44))
                    .foregroundStyle(display.isDoseDue ? WatchTheme.attention : WatchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                if let dose = display.doseText {
                    Text(dose)
                        .font(WatchFont.metric)
                        .foregroundStyle(WatchTheme.medication)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if let site = display.siteText {
                    SiteChip(text: site)
                }
            }
            .accessibilityElement(children: .combine)
        } else if let dose = display.doseText {
            VStack(spacing: 6) {
                kicker(display.statusPhrase)
                Text(dose)
                    .font(WatchFont.hero(40))
                    .foregroundStyle(WatchTheme.medication)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let site = display.siteText {
                    SiteChip(text: site)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(display.statusPhrase)
                .font(WatchFont.cardTitle)
                .foregroundStyle(WatchTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
    }

    private func kicker(_ text: String) -> some View {
        Label(text, systemImage: WatchSymbol.injection)
            .font(WatchFont.caption)
            .foregroundStyle(WatchTheme.attention)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// The suggested site, as a quiet pill beneath the hero.
private struct SiteChip: View {
    let text: String

    var body: some View {
        Label(text, systemImage: WatchSymbol.site)
            .font(WatchFont.metric)
            .foregroundStyle(WatchTheme.healthPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(WatchTheme.healthPrimary.opacity(0.14), in: Capsule())
    }
}

/// Weight progress as a hairline strip at the foot: a slim bar with the percent
/// and (Full tier only) the absolute weight inline beneath it. The fraction is
/// always safe to show (0…1, non-identifying); the weight appears only when the
/// producer's redaction left it.
private struct ProgressStrip: View {
    let fraction: Double
    let percentText: String
    let weightText: String?

    var body: some View {
        VStack(spacing: 5) {
            Capsule()
                .fill(WatchTheme.glassSurface)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(WatchTheme.healthPrimary)
                            .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 6)
            HStack(spacing: 4) {
                Text(percentText)
                    .foregroundStyle(WatchTheme.textPrimary)
                Text(.watchProgressToGoal)
                    .foregroundStyle(WatchTheme.textTertiary)
                Spacer(minLength: 4)
                if let weightText {
                    Text(weightText)
                        .foregroundStyle(WatchTheme.weight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .font(WatchFont.caption)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: .watchProgressToGoalAccessibility(percentText)))
    }
}
