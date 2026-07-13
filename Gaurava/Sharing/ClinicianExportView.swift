import SwiftUI

// The clinician image, printable export document, and share sheet around them.
//
// The image is the default handoff because it is easier to share in a messaging
// flow. The PDF stays deliberately document-like: near-white background,
// high-contrast ink, text-forward rows so it stays legible when printed in
// monochrome. Both carry the self-reported disclaimer and label dose context as
// self-logged. No inferred interpretation.

private enum ExportInk {
    private static let tokens = SharedThemeTokens.brand

    static let pageTop = Color(shared: tokens.pageBackgroundTop.light)
    static let pageBottom = Color(shared: tokens.pageBackgroundBottom.light)
    static let paper = Color(shared: tokens.healthSurface.light)
    static let ink = Color(shared: tokens.textPrimary.light)
    static let muted = Color(shared: tokens.textSecondary.light)
    static let tertiary = Color(shared: tokens.textTertiary.light)
    static let bronze = Color(shared: tokens.healthPrimary.light)
    static let accentForeground = Color(shared: tokens.accentForeground.light)
    static let moss = Color(shared: tokens.success.light)
    static let hairline = Color(shared: tokens.separator.light)
    static let chip = Color(shared: tokens.elevatedHealthSurface.light)
    static let neutralDose = Color(shared: tokens.doseStarter.light)
}

private extension Color {
    init(shared face: SharedColorFace) {
        self.init(
            .sRGB,
            red: face.red,
            green: face.green,
            blue: face.blue,
            opacity: face.alpha
        )
    }
}

struct ClinicianExportDocument: View {
    let summary: ClinicianSummary
    let displayName: String

    private var period: String {
        let start = summary.periodStart.appFormatted(.dateTime.day().month(.abbreviated).year())
        let end = summary.periodEnd.appFormatted(.dateTime.day().month(.abbreviated).year())
        return appLocalizedValue("\(start) – \(end)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appLocalizedValue("Side effect summary"))
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(ExportInk.ink)
                Text(appLocalizedValue("Gaurava · \(displayName) · generated \(summary.generatedAt.appFormatted(.dateTime.day().month(.abbreviated).year()))"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ExportInk.muted)
                Text(appLocalizedValue("Period: \(period)"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ExportInk.muted)
            }

            Text(summary.summaryLine)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(ExportInk.ink)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ExportInk.chip, in: RoundedRectangle(cornerRadius: 8))

            if summary.hasData {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(appLocalizedValue("Date")).frame(width: 62, alignment: .leading)
                        Text(appLocalizedValue("Dose")).frame(width: 78, alignment: .leading)
                        Text(appLocalizedValue("Side effects and notes")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(appLocalizedValue("Mood")).frame(width: 52, alignment: .leading)
                    }
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(ExportInk.muted)
                    .textCase(.uppercase)
                    .padding(.bottom, 6)

                    Rectangle().fill(ExportInk.hairline).frame(height: 1)

                    ForEach(summary.rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.date.appFormatted(.dateTime.day().month(.abbreviated)))
                                .frame(width: 62, alignment: .leading)
                            Text(doseContextText(row.activeDoseMg))
                                .fontWeight(.semibold)
                                .frame(width: 78, alignment: .leading)
                            Text(entryText(row))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.mood?.label ?? appLocalizedValue("—"))
                                .frame(width: 52, alignment: .leading)
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(ExportInk.ink)
                        .padding(.vertical, 7)

                        Rectangle().fill(ExportInk.hairline).frame(height: 0.5)
                    }
                }
            }

            if let doseLine = summary.doseLine {
                Text(appLocalizedValue("Dose changes this period (self-logged): \(doseLine)"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(ExportInk.muted)
            }

            Text(appLocalizedValue("Self-reported. Not medical advice and not a diagnostic record. Counts, severities, notes, and dose context are entered by the patient."))
                .font(.system(size: 9.5))
                .foregroundStyle(ExportInk.muted)
                .padding(.top, 2)
        }
        .padding(22)
        .background(ExportInk.paper)
    }

    private func doseContextText(_ dose: Double?) -> String {
        dose.map(doseText) ?? appLocalizedValue("No logged dose")
    }

    private func entryText(_ row: ClinicianExportRow) -> String {
        let symptoms = symptomText(row.symptoms)
        let note = row.note.map { appLocalizedValue("Note: \($0)") }
        switch (symptoms, note) {
        case let (symptoms?, note?):
            return appLocalizedValue("\(symptoms) · \(note)")
        case let (symptoms?, nil):
            return symptoms
        case let (nil, note?):
            return note
        case (nil, nil):
            return appLocalizedValue("—")
        }
    }

    private func symptomText(_ symptoms: [SymptomCapture]) -> String? {
        guard !symptoms.isEmpty else { return nil }
        return symptoms
            .map { symptom in
                if let sev = symptom.severity { return appLocalizedValue("\(symptom.kind.label) (\(sev.label))") }
                return symptom.kind.label
            }
            .joined(separator: ", ")
    }
}

struct ClinicianExportImageCard: View {
    let summary: ClinicianSummary
    let displayName: String

    private let canvas = ShareCardCanvas.portrait

    private var period: String {
        let start = summary.periodStart.appFormatted(.dateTime.day().month(.abbreviated))
        let end = summary.periodEnd.appFormatted(.dateTime.day().month(.abbreviated).year())
        return appLocalizedValue("\(start) – \(end)")
    }

    private var visibleRows: [ClinicianExportRow] {
        Array(summary.rows.prefix(4))
    }

    private var hiddenRowsCount: Int {
        max(summary.rows.count - visibleRows.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            headline
            metricStrip
            doseChanges
            entryList
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(width: canvas.points.width, height: canvas.points.height, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    ExportInk.pageTop,
                    ExportInk.pageBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appLocalizedValue("Gaurava"))
                    .font(.system(size: 15, weight: .heavy, design: .serif))
                    .foregroundStyle(ExportInk.ink)
                Text(displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ExportInk.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(appLocalizedValue("Clinician handoff"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ExportInk.accentForeground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(ExportInk.bronze, in: Capsule())
                Text(period)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(ExportInk.muted)
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(appLocalizedValue("Side effects for review"))
                .font(.system(size: 24, weight: .heavy, design: .serif))
                .foregroundStyle(ExportInk.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(summaryLineForCard)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ExportInk.muted)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 7) {
            imageMetric(
                title: appLocalizedValue("Entries"),
                value: summary.rows.count.formatted(),
                tint: ExportInk.bronze
            )
            imageMetric(
                title: appLocalizedValue("Current dose"),
                value: doseContextText(summary.currentDoseMg),
                tint: doseTint(summary.currentDoseMg)
            )
            imageMetric(
                title: appLocalizedValue("All-clear"),
                value: allClearMetric,
                tint: ExportInk.moss
            )
        }
    }

    private var doseChanges: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appLocalizedValue("Dose context, self-logged"))
                .font(.system(size: 9.5, weight: .heavy))
                .foregroundStyle(ExportInk.muted)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                ForEach(summary.doseChanges.prefix(3)) { change in
                    Text(doseChangeLabel(change))
                        .font(.system(size: 9.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(doseBadgeForeground(change.doseMg, colorScheme: .light))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(doseTint(change.doseMg), in: Capsule())
                }

                if summary.doseChanges.isEmpty {
                    Text(doseContextText(summary.currentDoseMg))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(ExportInk.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(ExportInk.paper.opacity(0.78), in: Capsule())
                } else if summary.doseChanges.count > 3 {
                    Text(appLocalizedValue("+\(summary.doseChanges.count - 3) more"))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(ExportInk.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(ExportInk.paper.opacity(0.78), in: Capsule())
                }
            }
        }
        .padding(10)
        .background(ExportInk.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(visibleRows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.date.appFormatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 10.5, weight: .heavy))
                        .foregroundStyle(ExportInk.ink)
                        .frame(width: 45, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(compactEntryText(row))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ExportInk.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                        if let mood = row.mood {
                            Text(appLocalizedValue("Mood: \(mood.label)"))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(ExportInk.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    Text(doseContextText(row.activeDoseMg))
                        .font(.system(size: 9.5, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(row.activeDoseMg.map { doseBadgeForeground($0, colorScheme: .light) } ?? ExportInk.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .frame(width: 58)
                        .background(row.activeDoseMg.map { doseTint($0) } ?? ExportInk.chip, in: Capsule())
                }
                .padding(8)
                .background(ExportInk.paper.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if hiddenRowsCount > 0 {
                Text(appLocalizedValue("+\(hiddenRowsCount) more entries in the printable PDF"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ExportInk.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var footer: some View {
        Text(appLocalizedValue("Self-reported. Not medical advice or a diagnostic record. Dose context is from the patient's logged injections."))
            .font(.system(size: 8.8, weight: .semibold))
            .foregroundStyle(ExportInk.muted)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
    }

    private var summaryLineForCard: String {
        if summary.hiddenAllClearCount == 1 {
            return appLocalizedValue("Symptom and note entries only. 1 all-clear check-in summarized, not listed.")
        }
        if summary.hiddenAllClearCount > 1 {
            return appLocalizedValue("Symptom and note entries only. \(summary.hiddenAllClearCount) all-clear check-ins summarized, not listed.")
        }
        return appLocalizedValue("Symptom and note entries only.")
    }

    private var allClearMetric: String {
        summary.hiddenAllClearCount > 0 ? summary.hiddenAllClearCount.formatted() : appLocalizedValue("None")
    }

    private func imageMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8.8, weight: .heavy))
                .foregroundStyle(ExportInk.tertiary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .serif))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ExportInk.paper.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func doseChangeLabel(_ change: ClinicianDoseChange) -> String {
        let date = change.startDate.appFormatted(.dateTime.day().month(.abbreviated))
        return appLocalizedValue("\(doseText(change.doseMg)) · \(date)")
    }

    private func doseContextText(_ dose: Double?) -> String {
        dose.map(doseText) ?? appLocalizedValue("No dose")
    }

    private func doseTint(_ dose: Double?) -> Color {
        dose.map(doseColor) ?? ExportInk.neutralDose
    }

    private func compactEntryText(_ row: ClinicianExportRow) -> String {
        let symptoms = row.symptoms
            .prefix(2)
            .map { symptom -> String in
                if let severity = symptom.severity {
                    return appLocalizedValue("\(symptom.kind.label) (\(severity.label))")
                }
                return symptom.kind.label
            }
            .joined(separator: ", ")

        let suffix = row.symptoms.count > 2 ? appLocalizedValue(" +\(row.symptoms.count - 2) more") : ""
        let symptomLine = symptoms.isEmpty ? nil : appLocalizedValue("\(symptoms)\(suffix)")
        let noteLine = row.note.map { appLocalizedValue("Note: \($0)") }
        switch (symptomLine, noteLine) {
        case let (symptomLine?, noteLine?):
            return appLocalizedValue("\(symptomLine) · \(noteLine)")
        case let (symptomLine?, nil):
            return symptomLine
        case let (nil, noteLine?):
            return noteLine
        case (nil, nil):
            return appLocalizedValue("Note logged")
        }
    }
}

// The Care sheet: preview the image + one-tap share. Generated instantly on
// appear, so there is no spinner at the appointment.
struct ClinicianExportSheet: View {
    let snapshot: DashboardSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var imageAsset: ShareCardRenderedAsset?
    @State private var pdfURL: URL?
    @State private var renderError: String?

    private var summary: ClinicianSummary { ClinicianExport.summary(from: snapshot) }
    private var displayName: String {
        snapshot.profile.displayName.isEmpty ? "Gaurava" : snapshot.profile.displayName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(appLocalizedValue("Ready to hand over — built from your own notes. You can read every line before you send it."))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.muted)

                    if summary.hasData {
                        previewSurface
                        shareControls
                    } else {
                        EmptyStateCard(
                            title: appLocalizedValue("Nothing to export yet"),
                            message: emptyExportMessage,
                            systemImage: AppSymbol.Health.symptomNote,
                            tint: AppTheme.primary
                        )
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle(appLocalizedValue("Share with clinician"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLocalizedValue("Done")) { dismiss() }
                }
            }
            .task {
                renderExportAssetsIfNeeded()
            }
        }
        .accessibilityIdentifier("clinician-export-sheet")
    }

    private var emptyExportMessage: String {
        if summary.hiddenAllClearCount == 1 {
            return appLocalizedValue("You have 1 all-clear check-in in this period. It is summarized, not listed as a clinician row. Add a side effect or appointment note to create a shareable handoff.")
        }
        if summary.hiddenAllClearCount > 1 {
            return appLocalizedValue("You have \(summary.hiddenAllClearCount) all-clear check-ins in this period. They are summarized, not listed as clinician rows. Add a side effect or appointment note to create a shareable handoff.")
        }
        return appLocalizedValue("Once you've noted a side effect or appointment note, a summary you can share with a clinician will appear here.")
    }

    @ViewBuilder
    private var previewSurface: some View {
        Group {
            if let imageAsset {
                Image(uiImage: imageAsset.image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.healthSurface)
                    ProgressView()
                        .tint(AppTheme.primary)
                }
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.stroke, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 12, y: 6)
    }

    @ViewBuilder
    private var shareControls: some View {
        VStack(spacing: 10) {
            if let imageAsset {
                ShareLink(item: imageAsset.fileURL, preview: SharePreview(appLocalizedValue("Clinician summary image"))) {
                    Label(appLocalizedValue("Share clinician image"), systemImage: AppSymbol.Action.share)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.accentForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.primary, in: Capsule())
                        .glassEffect(.regular.tint(AppTheme.primary.opacity(0.18)).interactive(), in: .capsule)
                }
                .accessibilityIdentifier("clinician-export-share")
            } else if let renderError {
                Text(renderError)
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.rose)
                    .frame(maxWidth: .infinity)
            } else {
                Text(appLocalizedValue("Preparing share files…"))
                    .font(AppFont.micro)
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity)
            }

            if let pdfURL {
                ShareLink(item: pdfURL, preview: SharePreview(appLocalizedValue("Printable clinician PDF"))) {
                    Label(appLocalizedValue("Share printable PDF"), systemImage: "doc.richtext")
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.healthSurface, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(AppTheme.stroke, lineWidth: 1)
                        )
                }
                .accessibilityIdentifier("clinician-export-pdf-share")
            }
        }
    }

    @MainActor
    private func renderExportAssetsIfNeeded() {
        guard summary.hasData else { return }
        if imageAsset == nil, renderError == nil {
            do {
                imageAsset = try ClinicianExport.makeImage(summary, displayName: displayName)
            } catch {
                renderError = error.localizedDescription
            }
        }
        if pdfURL == nil {
            pdfURL = ClinicianExport.makePDF(summary, displayName: displayName)
        }
    }
}
