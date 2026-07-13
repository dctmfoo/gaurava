import SwiftUI
import WidgetKit

// Gaurava watch complications — Phase 1 read-only glance.
//
// Reads the shared `GauravaGlanceSnapshot` from the on-device App Group file (the
// same `FileSnapshotStore` the watch app and the iOS widgets use; the watch's
// WCSession receiver writes it on every fresh snapshot and reloads these
// timelines) and renders the privacy-shaped `GlanceDisplay` across the watch
// accessory families — including the watch-only `accessoryCorner`. No SwiftData,
// no ActivityKit, no UIKit — `WatchTheme` only. Producer-side redaction already
// happened, so a complication renders only what survived: it can never leak a
// value the owner chose to hide, even on a public watch face.
@main
struct GauravaWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GauravaWatchGlanceWidget()
    }
}

struct GauravaWatchGlanceEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: GauravaGlanceSnapshot?
    /// Smart Stack relevance score, stored as a Sendable scalar; `relevance` is
    /// computed from it so the entry stays `Sendable` (WidgetKit's
    /// `TimelineEntryRelevance` is not Sendable and can't be a stored property).
    let relevanceScore: Float?

    var relevance: TimelineEntryRelevance? {
        relevanceScore.map { TimelineEntryRelevance(score: $0) }
    }
}

struct GauravaWatchGlanceProvider: TimelineProvider {
    private let store = AppGroupFileSnapshotStore()

    func placeholder(in context: Context) -> GauravaWatchGlanceEntry {
        GauravaWatchGlanceEntry(date: Date(), snapshot: nil, relevanceScore: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (GauravaWatchGlanceEntry) -> Void) {
        let snapshot = store.read()
        completion(GauravaWatchGlanceEntry(date: Date(), snapshot: snapshot, relevanceScore: relevanceScore(for: snapshot)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GauravaWatchGlanceEntry>) -> Void) {
        let now = Date()
        let snapshot = store.read()
        let entry = GauravaWatchGlanceEntry(date: now, snapshot: snapshot, relevanceScore: relevanceScore(for: snapshot))
        // Refresh at the next injection boundary if known, else hourly — mirrors
        // the iOS Care Glance widget so the wrist and phone stay in lockstep.
        let candidates = [snapshot?.nextAction?.nextInjectionDate, now.addingTimeInterval(3600)]
            .compactMap { $0 }
            .filter { $0 > now }
        let reloadAt = candidates.min() ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(reloadAt)))
    }

    // Smart Stack hint: surface the complication around dose time. The day count
    // survives every privacy mode, so this never depends on a hidden value.
    private func relevanceScore(for snapshot: GauravaGlanceSnapshot?) -> Float? {
        guard let days = snapshot?.nextAction?.daysUntilNextInjection else { return nil }
        return days <= 0 ? 100 : (days == 1 ? 70 : 10)
    }
}

struct GauravaWatchGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GauravaSurface.watchGlanceWidgetKind, provider: GauravaWatchGlanceProvider()) { entry in
            GauravaWatchGlanceView(entry: entry)
        }
        .configurationDisplayName(.watchWidgetGlanceDisplayName)
        .description(.watchWidgetGlanceDescription)
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

// MARK: - Family routing

private extension WidgetFamily {
    /// Map the watch families onto the shared low-detail accessory shapes. The
    /// watch-only `accessoryCorner` reuses the circular shape (status + safe day
    /// count + progress fraction); its curved layout is drawn below.
    var surfaceClass: SurfaceFamilyClass {
        switch self {
        case .accessoryRectangular: return .accessoryRectangular
        case .accessoryInline: return .accessoryInline
        case .accessoryCircular, .accessoryCorner: return .accessoryCircular
        @unknown default: return .accessoryCircular
        }
    }
}

struct GauravaWatchGlanceView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GauravaWatchGlanceEntry

    private var display: GlanceDisplay {
        GlanceDisplayModel.make(from: entry.snapshot, family: family.surfaceClass, asOf: entry.date)
    }

    var body: some View {
        switch family {
        case .accessoryCircular: CircularComplication(display: display)
        case .accessoryRectangular: RectangularComplication(display: display)
        case .accessoryInline: InlineComplication(display: display)
        case .accessoryCorner: CornerComplication(display: display)
        @unknown default: CircularComplication(display: display)
        }
    }
}

// MARK: - Per-family rendering

private struct CircularComplication: View {
    let display: GlanceDisplay

    var body: some View {
        if let days = display.dayCount {
            Gauge(value: display.progressFraction ?? 0) {
                Image(systemName: WatchSymbol.injection)
            } currentValueLabel: {
                Text("\(max(days, 0))")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(WatchTheme.healthPrimary)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: WatchSymbol.injection)
                    .foregroundStyle(WatchTheme.healthPrimary)
                    .widgetAccentable()
            }
        }
    }
}

private struct RectangularComplication: View {
    let display: GlanceDisplay

    var body: some View {
        // `statusPhrase` already encodes the day count ("Next dose in 4 days"),
        // so we never also render `dayCountCaption` here (it restates the same
        // fact). Filling the full height vertically centers the content instead of
        // pinning it to the top-left corner. Mirrors the iOS RectangularContent.
        VStack(alignment: .leading, spacing: 3) {
            Label(.watchWidgetBrandGaurava, systemImage: WatchSymbol.injection)
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text(display.statusPhrase)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct InlineComplication: View {
    let display: GlanceDisplay

    var body: some View {
        Label(display.inlineSummary, systemImage: WatchSymbol.injection)
    }
}

/// The watch-only corner family: compact content tucked into the screen corner
/// with a curved label along the bezel. The countdown (or brand glyph) sits in
/// the corner; the curved label carries the status, with a progress gauge when a
/// safe fraction survived redaction.
private struct CornerComplication: View {
    let display: GlanceDisplay

    var body: some View {
        cornerContent
            .widgetLabel {
                if let fraction = display.progressFraction {
                    Gauge(value: fraction) {
                        Text(display.statusPhrase)
                    } currentValueLabel: {
                        Text(display.progressPercentText ?? "")
                    }
                    .tint(WatchTheme.healthPrimary)
                } else {
                    Text(display.statusPhrase)
                }
            }
    }

    @ViewBuilder
    private var cornerContent: some View {
        if let days = display.dayCount {
            Text("\(max(days, 0))")
                .font(.title3.weight(.semibold))
                .widgetAccentable()
        } else {
            Image(systemName: WatchSymbol.injection)
                .foregroundStyle(WatchTheme.healthPrimary)
                .widgetAccentable()
        }
    }
}
