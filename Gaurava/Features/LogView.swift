import SwiftData
import SwiftUI

// The Log tab (v1). A near-effortless capture surface, not a diary:
//
//   • a one-glass mood question — the "good day is also one gesture" affordance;
//   • a compact side-effect entry point — the picker lives in a sheet so the
//     main card stays visually stable;
//   • a "+ note" freeform escape hatch.
//
// State is read from the immutable `DashboardSnapshot` (so a write anywhere flows
// back through the single SwiftData query) and every write goes through
// `LogCapture`, which upserts by day and republishes the glance / Live-Activity
// surfaces. Per the design foundations the chips and cards are STANDARD material
// (Liquid Glass is reserved for chrome + the one primary action); state is carried
// by shape + weight + color together, never color alone.
struct LogView: View {
    @Environment(\.modelContext) private var modelContext
    let snapshot: DashboardSnapshot

    @State private var noteDraft = ""
    @State private var isEditingNote = false
    @State private var isShowingSideEffects = false
    @FocusState private var isNoteFocused: Bool

    private var today: DayCaptureSnapshot? { snapshot.todayCapture }

    var body: some View {
        AppScreen(title: "Log", spacing: 14, ambientTint: AppTheme.screenIdentity) {
            if let line = doseContextLine {
                DoseContextLine(text: line, tint: doseTint)
                    .padding(.horizontal, 4)
            }

            captureCard

            SectionHeader(title: "Recent")
                .padding(.top, AppSpacing.sm)
            recentCard
        }
        .sheet(isPresented: $isShowingSideEffects) {
            sideEffectSheet
        }
    }

    // MARK: Capture card

    private var captureCard: some View {
        // Keep the parent capture surface quiet; mood state lives in the
        // question control and the action surfaces below.
        HealthCard(tint: today?.mood?.moodQuestionTint ?? AppTheme.primary, cornerRadius: AppRadius.hero, padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(Date().appFormatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.muted)
                }

                moodQuestion
                    .padding(.top, 2)
                sideEffectAffordance
                noteAffordance

            }
        }
        .accessibilityIdentifier("log-capture-card")
    }

    private var moodQuestion: some View {
        OneGlassMoodQuestion(selection: today?.mood) { mood in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                LogCapture.setMood(mood, on: Date(), in: modelContext)
            }
        }
    }

    private var sideEffectAffordance: some View {
        Button {
            isShowingSideEffects = true
        } label: {
            let tint = hasRecordedSideEffects ? AppTheme.success : AppTheme.primary
            ThemedActionSurface(tint: tint, isActive: hasRecordedSideEffects, cornerRadius: 18) { surface in
                HStack(spacing: 10) {
                    Image(systemName: hasRecordedSideEffects ? AppSymbol.Status.selectedCircle : AppSymbol.Action.add)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(surface.iconForeground)
                        .frame(width: 30, height: 30)
                        .background(surface.iconBackground, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLocalized("Anything else?"))
                            .font(AppFont.bodyStrong)
                            .foregroundStyle(surface.foreground)
                        Text(sideEffectSummaryText)
                            .font(AppFont.micro)
                            .foregroundStyle(surface.secondaryForeground)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: AppSymbol.Action.disclosure)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(surface.disclosureForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appLocalized("Anything else? Side effects"))
        .accessibilityValue(sideEffectSummaryText)
        .accessibilityHint(appLocalized("Double tap to open side effects"))
        .accessibilityIdentifier("side-effect-entry-button")
    }

    private var sideEffectSheet: some View {
        NavigationStack {
            SideEffectPicker(
                symptoms: today?.symptoms ?? [],
                allClear: today?.allClear ?? false,
                onToggleSymptom: { kind in
                    LogCapture.toggleSideEffect(kind, on: Date(), in: modelContext)
                },
                onSetSeverity: { kind, severity in
                    LogCapture.recordSideEffect(kind, severity: severity, on: Date(), in: modelContext)
                },
                onToggleAllClear: {
                    LogCapture.setAllClear(!(today?.allClear ?? false), day: Date(), in: modelContext)
                }
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingSideEffects = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("log-side-effect-sheet")
    }

    @ViewBuilder
    private var noteAffordance: some View {
        if isEditingNote {
            VStack(alignment: .leading, spacing: 9) {
                AppTextFieldShell(systemImage: AppSymbol.Health.note, tint: AppTheme.primary) {
                    TextField("Anything the chips don't cover…", text: $noteDraft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isNoteFocused)
                        .accessibilityIdentifier("log-note-text-editor")
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") {
                        isNoteFocused = false
                        isEditingNote = false
                    }
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.muted)
                        .frame(minHeight: 44)
                    Button("Save") {
                        isNoteFocused = false
                        LogCapture.appendNote(noteDraft, on: Date(), in: modelContext)
                        noteDraft = ""
                        isEditingNote = false
                    }
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(AppTheme.accentForeground)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(AppTheme.primary, in: Capsule())
                }
            }
            .padding(.top, 10)
            // Raise the keyboard as soon as the inline editor appears, so adding
            // a note is one tap, not two. `Task.yield()` lets the field install
            // first (matches AddDailyLogSheet's focus idiom).
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                isNoteFocused = true
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isNoteFocused = false }
                }
            }
        } else {
            Button {
                noteDraft = ""
                isEditingNote = true
            } label: {
                ThemedActionSurface(tint: AppTheme.primary, cornerRadius: 14, minHeight: 44) { surface in
                    Label(today?.note?.isEmpty == false ? appLocalized("Add another note") : appLocalized("Add a note"),
                          systemImage: today?.note?.isEmpty == false ? AppSymbol.Health.note : AppSymbol.Action.add)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(surface.iconForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(today?.note?.isEmpty == false ? appLocalized("Add another note") : appLocalized("Add a note"))
            .accessibilityIdentifier("log-note-entry-button")
            .padding(.top, 12)
        }
    }

    // MARK: Recent

    private var recentCard: some View {
        HealthCard(tint: AppTheme.primary, cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                if snapshot.dayCaptures.isEmpty {
                    Text("Nothing logged yet. That's completely fine.")
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                        .italic()
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(snapshot.dayCaptures.enumerated()), id: \.element.id) { index, day in
                        DayCaptureRow(day: day)
                        if index < snapshot.dayCaptures.count - 1 {
                            Divider().overlay(AppTheme.stroke)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("log-recent-card")
    }

    // MARK: Helpers

    private var hasRecordedSideEffects: Bool {
        today?.allClear == true || !(today?.symptoms ?? []).isEmpty
    }

    private var sideEffectSummaryText: String {
        if today?.allClear == true {
            return appLocalized("No side effects recorded")
        }
        let symptoms = today?.symptoms ?? []
        if symptoms.isEmpty {
            return appLocalized("Side effects, only if something changed")
        }
        if symptoms.count == 1, let first = symptoms.first {
            return first.severity.map { appLocalizedValue("\(appLocalized(first.kind.label)) · \(appLocalized($0.short))") } ?? appLocalized(first.kind.label)
        }
        return appLocalizedValue("\(symptoms.count) side effects recorded")
    }

    private var doseContextLine: String? {
        if let last = snapshot.lastInjection {
            let date = last.injectionDate.appFormatted(.dateTime.day().month(.abbreviated))
            let count = snapshot.injectionCount
            if count == 1 {
                return appLocalizedValue("Last dose: \(doseText(last.doseMg)), logged \(date) · 1 injection recorded")
            }
            return appLocalizedValue("Last dose: \(doseText(last.doseMg)), logged \(date) · \(count) injections recorded")
        }
        // Already-going (bucket C) with no jab logged yet: surface the dose the user
        // confirmed during onboarding (the schedule anchor) as a thin context line.
        if let anchorDate = snapshot.profile.scheduleAnchorDate,
           let anchorDose = snapshot.profile.scheduleAnchorDoseMg {
            let date = anchorDate.appFormatted(.dateTime.day().month(.abbreviated))
            return appLocalizedValue("Last dose: \(doseText(anchorDose)), \(date)")
        }
        return nil
    }

    private var doseTint: Color {
        doseColor(snapshot.lastInjection?.doseMg ?? snapshot.profile.scheduleAnchorDoseMg)
    }
}

private struct DoseContextLine: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 9, height: 9)
            Text(appLocalized(text))
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent timeline row

private struct DayCaptureRow: View {
    let day: DayCaptureSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(appLocalized(rail))
                .font(AppFont.micro)
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 56, alignment: .leading)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                FlowChips(spacing: 6) {
                    ForEach(day.symptoms) { symptom in
                        TimelineTag(
                            text: symptom.severity.map { appLocalizedValue("\(appLocalized(symptom.kind.label)) · \(appLocalized($0.short))") } ?? appLocalized(symptom.kind.label),
                            systemImage: symptom.severity?.logSymbol ?? symptom.kind.systemImage,
                            tint: symptom.severity?.logTint ?? symptom.kind.logTint
                        )
                    }
                    if day.allClear {
                        TimelineTag(text: "All clear", systemImage: AppSymbol.Status.onTrack, tint: AppTheme.success)
                    }
                    if let mood = day.mood {
                        TimelineTag(text: mood.label, systemImage: mood.logSymbol, tint: mood.logTint)
                            .accessibilityIdentifier("log-recent-mood-\(mood.rawValue)")
                    }
                    if day.hasSystemSource {
                        TimelineTag(text: "from Lock Screen", systemImage: "lock.iphone", tint: AppTheme.weight)
                    }
                }

                if let note = day.note, !note.isEmpty {
                    Text(note)
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var rail: String {
        if Calendar.current.isDateInToday(day.logDate) { return appLocalized("Today") }
        if Calendar.current.isDateInYesterday(day.logDate) { return appLocalized("Yesterday") }
        return day.logDate.appFormatted(.dateTime.day().month(.abbreviated))
    }
}

private struct TimelineTag: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: AppIconSize.chip, weight: .bold))
            Text(appLocalized(text)).font(AppFont.micro)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Wrapping chip layout

/// A simple wrapping HStack for chips/tags using the iOS 16+ `Layout` API is
/// overkill here; SwiftUI's native `FlowLayout` isn't public, so we wrap with a
/// flexible grid-free approach: a `WrapHStack` built on `Layout`.
struct FlowChips<Content: View>: View {
    var spacing: CGFloat = 9
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayout(spacing: spacing) { content }
    }
}

/// Minimal flow layout: lays children left-to-right, wrapping to the next line
/// when the row would overflow. Keeps chips at their intrinsic size and reflows
/// at large Dynamic Type sizes (Foundations §3). Subview sizes are measured once
/// into the layout cache — measuring inside both `sizeThatFits` and
/// `placeSubviews` showed up as per-frame work while scrolling the Log timeline.
struct FlowLayout: Layout {
    var spacing: CGFloat = 9

    struct Cache {
        var sizes: [CGSize]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for size in cache.sizes {
            if x + size.width > maxWidth, !(rows[rows.count - 1].isEmpty) {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        let height = rows.reduce(0) { partial, row in
            partial + (row.map(\.height).max() ?? 0) + spacing
        } - spacing
        return CGSize(width: maxWidth == .infinity ? rowWidth(rows) : maxWidth, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for (subview, size) in zip(subviews, cache.sizes) {
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rowWidth(_ rows: [[CGSize]]) -> CGFloat {
        rows.map { row in row.map(\.width).reduce(0) { $0 + $1 + spacing } }.max() ?? 0
    }
}

// MARK: - System capture sheet (v1.1 route-then-confirm)

// Presented when a `gaurava://log-symptom` deep link arrives from the single
// system entry point (Action button / Control Center / Lock Screen). The user
// taps the symptom HERE, in-app — which writes the record (source "system" so it
// carries a "from Lock Screen" tag in the timeline). The widget/extension never
// writes; this sheet is the "confirm" half of route-then-confirm.
struct LogCaptureSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let snapshot: DashboardSnapshot

    private var today: DayCaptureSnapshot? { snapshot.todayCapture }

    var body: some View {
        NavigationStack {
            SideEffectPicker(
                symptoms: today?.symptoms ?? [],
                allClear: today?.allClear ?? false,
                onToggleSymptom: { kind in
                    LogCapture.toggleSideEffect(kind, on: Date(), source: "system", in: modelContext)
                },
                onSetSeverity: { kind, severity in
                    LogCapture.recordSideEffect(kind, severity: severity, on: Date(), source: "system", in: modelContext)
                },
                onToggleAllClear: {
                    LogCapture.setAllClear(!(today?.allClear ?? false), day: Date(), in: modelContext)
                }
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("log-capture-sheet")
    }
}

private extension MoodValence {
    var logTint: Color {
        switch self {
        case .rough: return AppTheme.danger
        case .low: return AppTheme.attention
        case .okay: return AppTheme.profile
        case .good: return AppTheme.weight
        case .great: return AppTheme.success
        }
    }

    var logSymbol: String {
        switch self {
        case .rough: return "cloud.rain.fill"
        case .low: return "cloud.fill"
        case .okay: return "circle.lefthalf.filled"
        case .good: return "sun.min.fill"
        case .great: return "sun.max.fill"
        }
    }
}

#Preview {
    NavigationStack {
        LogView(snapshot: .preview)
    }
}
