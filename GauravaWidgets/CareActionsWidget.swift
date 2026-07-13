import SwiftUI
import WidgetKit

// Care Actions — an interactive medium widget of quick shortcuts (Build 3).
//
// All actions are pure navigation, so they use `Link` (per Apple's guidance
// that a widget interaction which only opens the app should use Link/widgetURL,
// not Button(intent:)). Weight / Jab / Note open the in-app entry sheet via the
// gaurava:// deep link, routed by the same parser as `.onOpenURL`.
//
// NOTE: there is intentionally no in-widget privacy toggle. A Button(intent:)
// privacy toggle runs in the widget-extension process and can only reliably
// reload the widget that contains it — refreshing the SEPARATE read-only Care
// Glance widget depends on a WidgetCenter reload that WidgetKit budget-limits
// when the app is backgrounded (see "Keeping a widget up to date"). Widget
// privacy is therefore owned by the in-app Care > Widget Privacy picker, which
// runs while the app is foreground and reliably republishes + reloads all
// surfaces. Brand styling mirrors WidgetTheme; no app-target import.

struct CareActionsEntry: TimelineEntry, Sendable {
    let date: Date
    let statusPhrase: String
    let localeIdentifier: String

    var surfaceLocale: Locale { Locale(identifier: localeIdentifier) }
}

struct CareActionsProvider: TimelineProvider {
    private let store = AppGroupFileSnapshotStore()

    func placeholder(in context: Context) -> CareActionsEntry {
        let localeIdentifier = GauravaSurface.surfaceLocaleIdentifier()
        let locale = Locale(identifier: localeIdentifier)
        return CareActionsEntry(
            date: Date(),
            statusPhrase: GlanceDisplayModel.placeholderDisplay(locale: locale).statusPhrase,
            localeIdentifier: localeIdentifier
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CareActionsEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CareActionsEntry>) -> Void) {
        let entry = makeEntry()
        // Action-first widget: a quiet hourly refresh is plenty.
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(3600))))
    }

    private func makeEntry() -> CareActionsEntry {
        let snapshot = store.read()
        let now = Date()
        let localeIdentifier = GauravaSurface.surfaceLocaleIdentifier()
        let locale = Locale(identifier: localeIdentifier)
        let display = GlanceDisplayModel.make(
            from: snapshot,
            family: .systemMedium,
            asOf: now,
            locale: locale
        )
        return CareActionsEntry(
            date: now,
            statusPhrase: display.statusPhrase,
            localeIdentifier: localeIdentifier
        )
    }
}

struct CareActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GauravaSurface.careActionsWidgetKind, provider: CareActionsProvider()) { entry in
            CareActionsView(entry: entry)
                .containerBackground(for: .widget) { GlanceSurfaceBackground() }
        }
        .configurationDisplayName(.widgetCareActionsDisplayName)
        .description(.widgetCareActionsDescription)
        .supportedFamilies([.systemMedium])
    }
}

struct CareActionsView: View {
    let entry: CareActionsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(.widgetBrandGaurava, systemImage: WidgetSymbol.injection)
                    .font(WidgetFont.header)
                    .foregroundStyle(WidgetTheme.healthPrimary)
                Spacer(minLength: 0)
                Text(entry.statusPhrase)
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                ActionTile(
                    title: .widgetCareActionsWeight,
                    systemImage: WidgetSymbol.weight,
                    tint: WidgetTheme.weight,
                    destination: GauravaScreen.addWeight.url
                )
                ActionTile(
                    title: .widgetCareActionsJab,
                    systemImage: WidgetSymbol.injection,
                    tint: WidgetTheme.medication,
                    destination: GauravaScreen.addInjection.url
                )
                ActionTile(
                    title: .widgetCareActionsNote,
                    systemImage: "square.and.pencil",
                    tint: WidgetTheme.healthPrimary,
                    destination: GauravaScreen.dailyNote.url
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.locale, entry.surfaceLocale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Tile

private struct ActionTile: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WidgetTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(WidgetTheme.glassSurface.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(WidgetTheme.stroke, lineWidth: 1)
            )
        }
    }
}
