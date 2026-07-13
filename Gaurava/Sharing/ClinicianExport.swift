import SwiftUI
import UIKit

// Clinician export (Log v1.1): a pre-generated, shareable side-effect summary.
//
// A byproduct of capturing, not the motivation — so it is built instantly from
// the data already on device and one-tap shareable as a clinician image, with a
// printable PDF fallback. It tells the literal truth: dated symptom/note entries
// plus the active self-logged dose for each entry. There is NO inferred clinical
// interpretation and NO fabricated "dose week" model (the schema has only
// per-shot doses), and every dose figure is labelled self-logged. The disclaimer
// states it is self-reported and not a diagnostic record.

/// One day in the export.
struct ClinicianExportRow: Identifiable {
    var id: Date { date }
    var date: Date
    var symptoms: [SymptomCapture]
    var mood: MoodValence?
    var note: String?
    var activeDoseMg: Double?
}

struct ClinicianDoseChange: Identifiable {
    var doseMg: Double
    var startDate: Date

    var id: String { "\(doseMg)-\(startDate.timeIntervalSince1970)" }
}

/// The full export model, derived purely from the snapshot.
struct ClinicianSummary {
    var generatedAt: Date
    var periodStart: Date
    var periodEnd: Date
    var rows: [ClinicianExportRow]
    var symptomTotals: [(kind: SideEffectKind, count: Int)]
    var doseLine: String?
    var doseChanges: [ClinicianDoseChange]
    var currentDoseMg: Double?
    var hiddenAllClearCount: Int

    var hasData: Bool { !rows.isEmpty }
    var loggedDayCount: Int { rows.count + hiddenAllClearCount }

    /// A plain-English headline a clinician can read without studying the table.
    var summaryLine: String {
        guard hasData else {
            if hiddenAllClearCount == 1 {
                return appLocalizedValue("No side effects were recorded in this period. 1 all-clear check-in was summarized, not listed.")
            }
            if hiddenAllClearCount > 1 {
                return appLocalizedValue("No side effects were recorded in this period. \(hiddenAllClearCount) all-clear check-ins were summarized, not listed.")
            }
            return appLocalizedValue("No side effects were recorded in this period.")
        }
        let top = symptomTotals.filter { $0.count > 0 }
        let phrase = top.isEmpty
            ? appLocalizedValue("notes without side effects")
            : top.map { "\($0.kind.label.lowercased()) ×\($0.count)" }.joined(separator: ", ")
        let entryPhrase = rows.count == 1
            ? appLocalizedValue("1 entry over the period: \(phrase).")
            : appLocalizedValue("\(rows.count) entries over the period: \(phrase).")

        if hiddenAllClearCount == 1 {
            return appLocalizedValue("\(entryPhrase) 1 all-clear check-in summarized, not listed.")
        }
        if hiddenAllClearCount > 1 {
            return appLocalizedValue("\(entryPhrase) \(hiddenAllClearCount) all-clear check-ins summarized, not listed.")
        }
        return entryPhrase
    }
}

enum ClinicianExport {
    /// Build the summary from the dashboard. Bounded to the last `days` days.
    static func summary(
        from dashboard: DashboardSnapshot,
        days: Int = 90,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ClinicianSummary {
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -days, to: end) ?? end

        let periodCaptures = dashboard.dayCaptures
            .filter { $0.logDate >= start && $0.logDate <= now }
            .sorted { $0.logDate > $1.logDate }

        let orderedInjections = dashboard.injections
            .sorted { $0.injectionDate < $1.injectionDate }

        let rows = periodCaptures
            .filter { hasClinicalSignal($0) }
            .map {
                ClinicianExportRow(
                    date: $0.logDate,
                    symptoms: $0.symptoms,
                    mood: $0.mood,
                    note: normalizedNote($0.note),
                    activeDoseMg: activeDose(on: $0.logDate, injections: orderedInjections, calendar: calendar)
                )
            }

        let hiddenAllClearCount = periodCaptures
            .filter { $0.allClear && $0.symptoms.isEmpty && normalizedNote($0.note) == nil }
            .count

        let totals = SideEffectKind.allCases.map { kind in
            (kind: kind, count: rows.reduce(0) { $0 + ($1.symptoms.contains { $0.kind == kind } ? 1 : 0) })
        }

        let periodInjections = orderedInjections
            .filter { $0.injectionDate >= start && $0.injectionDate <= now }
        let doseChanges = makeDoseChanges(periodInjections)
        let doseLine = doseChangeLine(doseChanges)
        let currentDoseMg = activeDose(on: now, injections: orderedInjections, calendar: calendar)

        return ClinicianSummary(
            generatedAt: now,
            periodStart: start,
            periodEnd: end,
            rows: rows,
            symptomTotals: totals,
            doseLine: doseLine,
            doseChanges: doseChanges,
            currentDoseMg: currentDoseMg,
            hiddenAllClearCount: hiddenAllClearCount
        )
    }

    private static func doseChangeLine(_ changes: [ClinicianDoseChange]) -> String? {
        guard !changes.isEmpty else { return nil }
        return changes
            .map { change in
                let date = change.startDate.appFormatted(.dateTime.day().month(.abbreviated))
                return appLocalizedValue("\(doseText(change.doseMg)) from \(date)")
            }
            .joined(separator: ", ")
    }

    private static func makeDoseChanges(_ injections: [InjectionSnapshot]) -> [ClinicianDoseChange] {
        var previousDose: Double?
        var changes: [ClinicianDoseChange] = []
        for injection in injections {
            guard previousDose.map({ abs($0 - injection.doseMg) < 0.001 }) != true else { continue }
            previousDose = injection.doseMg
            changes.append(ClinicianDoseChange(doseMg: injection.doseMg, startDate: injection.injectionDate))
        }
        return changes
    }

    private static func hasClinicalSignal(_ capture: DayCaptureSnapshot) -> Bool {
        !capture.symptoms.isEmpty || normalizedNote(capture.note) != nil
    }

    private static func normalizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func activeDose(
        on date: Date,
        injections: [InjectionSnapshot],
        calendar: Calendar
    ) -> Double? {
        let targetDay = calendar.startOfDay(for: date)
        return injections
            .last { calendar.startOfDay(for: $0.injectionDate) <= targetDay }?
            .doseMg
    }

    /// Render the export document to a single-page PDF and return its file URL.
    @MainActor
    static func makePDF(_ summary: ClinicianSummary, displayName: String) -> URL? {
        let document = ClinicianExportDocument(summary: summary, displayName: displayName)
            .frame(width: 540)
        let renderer = ImageRenderer(content: document)
        renderer.scale = 2

        let url = ShareExportFilename.temporaryFileURL(
            baseName: appLocalizedValue("Gaurava-Side-Effects"),
            fileExtension: "pdf"
        )

        var produced = false
        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            produced = true
        }
        return produced ? url : nil
    }

    /// Render the appointment-card export as a fixed 4:5 PNG.
    @MainActor
    static func makeImage(_ summary: ClinicianSummary, displayName: String) throws -> ShareCardRenderedAsset {
        guard summary.hasData else {
            throw ClinicianExportRenderError.noRenderableRows
        }

        let canvas = ShareCardCanvas.portrait
        let content = ClinicianExportImageCard(summary: summary, displayName: displayName)
            .frame(width: canvas.points.width, height: canvas.points.height)
            .environment(\.colorScheme, .light)
            .dynamicTypeSize(.medium)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: canvas.points.width, height: canvas.points.height)
        renderer.scale = canvas.scale
        renderer.isOpaque = true
        renderer.colorMode = .nonLinear

        guard let image = renderer.uiImage, let cgImage = image.cgImage else {
            throw ClinicianExportRenderError.renderFailed
        }

        guard cgImage.width == Int(canvas.pixels.width), cgImage.height == Int(canvas.pixels.height) else {
            throw ClinicianExportRenderError.unexpectedSize(
                actual: CGSize(width: cgImage.width, height: cgImage.height),
                expected: canvas.pixels
            )
        }

        guard let pngData = image.pngData() else {
            throw ClinicianExportRenderError.pngEncodingFailed
        }

        let fileURL = ShareExportFilename.temporaryFileURL(
            baseName: appLocalizedValue("Gaurava-Clinician"),
            fileExtension: "png"
        )
        try pngData.write(to: fileURL, options: .atomic)

        return ShareCardRenderedAsset(image: image, pngData: pngData, fileURL: fileURL)
    }
}

enum ClinicianExportRenderError: LocalizedError {
    case noRenderableRows
    case renderFailed
    case pngEncodingFailed
    case unexpectedSize(actual: CGSize, expected: CGSize)

    var errorDescription: String? {
        switch self {
        case .noRenderableRows:
            appLocalizedValue("Add a side effect or appointment note before sharing a clinician image.")
        case .renderFailed:
            appLocalizedValue("The clinician image could not be rendered.")
        case .pngEncodingFailed:
            appLocalizedValue("The clinician image could not be prepared as a PNG.")
        case let .unexpectedSize(actual, expected):
            appLocalizedValue("The clinician image rendered at \(Int(actual.width))x\(Int(actual.height)), expected \(Int(expected.width))x\(Int(expected.height)).")
        }
    }
}
