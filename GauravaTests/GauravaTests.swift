import CoreGraphics
import SwiftData
import UIKit
import XCTest
@testable import Gaurava

final class GauravaTests: XCTestCase {
    func testModelContainerCanBeCreatedInMemory() throws {
        let container = GauravaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let profile = TrackerProfile(
            legacyServerId: "profile-1",
            startingWeightKg: 98.0,
            goalWeightKg: 82.0,
            plannedDoseMg: 7.5
        )

        context.insert(profile)
        try context.save()

        let descriptor = FetchDescriptor<TrackerProfile>()
        let profiles = try context.fetch(descriptor)

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.legacyServerId, "profile-1")
        XCTAssertEqual(profiles.first?.plannedDoseMg, 7.5)
        XCTAssertEqual(profiles.first?.medication, .tirzepatide)

        let preference = UserPreference()
        preference.preferredInjectionSites = ["Thigh - Left", "Thigh - Right"]
        context.insert(preference)
        try context.save()

        let savedPreference = try XCTUnwrap(context.fetch(FetchDescriptor<UserPreference>()).first)
        XCTAssertEqual(savedPreference.preferredInjectionSites, ["Thigh - Left", "Thigh - Right"])
    }

    func testCloudKitContainerIdentifierIsExplicit() {
        XCTAssertEqual(CloudKitConfiguration.containerIdentifier, "iCloud.com.nags.gaurava")
    }

    // Month labels must sit AT the month-start gridline, and a sliver first
    // month (three visible December days) gets no label at all — a midpoint
    // "Jan" once rendered under a Jan-25 dose-change line and read as "the new
    // dose started at Jan".
    func testResultsChartUsesTightDomainAndAnchorsLabelsAtMonthStarts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 28)))
        let last = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)))
        let firstMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 1)))
        let january = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        let domain = ResultsChartScale.xDomain(first: first, last: last, calendar: calendar)
        let gridDates = ResultsChartScale.monthGridDates(first: first, last: last, domain: domain, calendar: calendar)
        let labelTicks = ResultsChartScale.monthLabelTicks(first: first, last: last, domain: domain, calendar: calendar)
        let firstLabel = try XCTUnwrap(labelTicks.first)

        XCTAssertEqual(domain.lowerBound, first)
        XCTAssertEqual(domain.upperBound, last)
        XCTAssertFalse(gridDates.contains(firstMonth))
        // Sliver December is dropped; January through May label their gridlines.
        XCTAssertEqual(firstLabel.monthStart, january)
        XCTAssertEqual(firstLabel.date, january)
        XCTAssertEqual(labelTicks.count, 5)
        XCTAssertEqual(labelTicks.map(\.date), labelTicks.map(\.monthStart))
    }

    // A first month with real visible width keeps its label, clamped to the
    // domain edge so it still marks where the data starts.
    func testResultsChartKeepsClampedLabelForWideFirstMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 5)))
        let last = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 28)))
        let firstMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 1)))

        let domain = ResultsChartScale.xDomain(first: first, last: last, calendar: calendar)
        let labelTicks = ResultsChartScale.monthLabelTicks(first: first, last: last, domain: domain, calendar: calendar)
        let firstLabel = try XCTUnwrap(labelTicks.first)

        XCTAssertEqual(firstLabel.monthStart, firstMonth)
        XCTAssertEqual(firstLabel.date, first)
    }

    // Regression: the x-domain once grew a trailing pad while dose labels were
    // visible, so toggling them re-scaled and shifted the whole trend line.
    func testResultsChartDomainStaysTightRegardlessOfOverlays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 28)))
        let last = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)))

        let domain = ResultsChartScale.xDomain(first: first, last: last, calendar: calendar)

        XCTAssertEqual(domain.lowerBound, first)
        XCTAssertEqual(domain.upperBound, last)
    }

    func testMedicationPresetsAndInferenceStayDisjoint() {
        XCTAssertEqual(Medication.tirzepatide.dosePresets, [2.5, 5, 7.5, 10, 12.5, 15])
        XCTAssertEqual(Medication.semaglutide.dosePresets, [0.25, 0.5, 1, 1.7, 2, 2.4, 7.2])
        XCTAssertEqual(Medication.tirzepatide.starterDose, 2.5)
        XCTAssertEqual(Medication.semaglutide.starterDose, 0.25)
        XCTAssertEqual(Medication.inferred(fromMg: nil), .tirzepatide)

        for dose in Medication.tirzepatide.dosePresets {
            XCTAssertEqual(Medication.inferred(fromMg: dose), .tirzepatide, "\(dose) should infer tirzepatide")
        }
        for dose in Medication.semaglutide.dosePresets {
            XCTAssertEqual(Medication.inferred(fromMg: dose), .semaglutide, "\(dose) should infer semaglutide")
        }

        XCTAssertEqual(Medication.inferred(fromMg: 7.2), .semaglutide)
        XCTAssertEqual(Medication.inferred(fromMg: 7.5), .tirzepatide)
    }

    func testApplyMedicationClearsIncompatiblePlannedDoseAndBumpsTimestamp() {
        let oldTimestamp = Self.fixtureDate(days: 1)
        let newTimestamp = Self.fixtureDate(days: 2)
        let profile = TrackerProfile(
            plannedDoseMg: 7.5,
            medicationRaw: Medication.tirzepatide.rawValue,
            plannedDoseUpdatedAt: oldTimestamp,
            updatedAt: oldTimestamp
        )

        profile.applyMedication(.semaglutide, now: newTimestamp)

        XCTAssertEqual(profile.medication, .semaglutide)
        XCTAssertNil(profile.plannedDoseMg)
        XCTAssertEqual(profile.plannedDoseUpdatedAt, newTimestamp)
        XCTAssertEqual(profile.updatedAt, newTimestamp)
    }

    func testApplyMedicationKeepsCompatibleSemaglutidePlannedDose() {
        let timestamp = Self.fixtureDate(days: 3)
        let profile = TrackerProfile(
            plannedDoseMg: 2.4,
            medicationRaw: Medication.tirzepatide.rawValue,
            plannedDoseUpdatedAt: timestamp
        )

        profile.applyMedication(.semaglutide, now: Self.fixtureDate(days: 4))

        XCTAssertEqual(profile.medication, .semaglutide)
        XCTAssertEqual(try XCTUnwrap(profile.plannedDoseMg), 2.4, accuracy: 0.001)
        XCTAssertEqual(profile.plannedDoseUpdatedAt, timestamp)
    }

    func testApplyMedicationRoundTripKeepsMedicationConsistent() {
        let profile = TrackerProfile(medicationRaw: Medication.tirzepatide.rawValue)

        profile.applyMedication(.semaglutide, now: Self.fixtureDate(days: 5))
        XCTAssertEqual(profile.medication, .semaglutide)

        profile.applyMedication(.tirzepatide, now: Self.fixtureDate(days: 6))
        XCTAssertEqual(profile.medication, .tirzepatide)
    }

    func testApplyMedicationDoesNotMutateInjectionHistory() {
        let profile = TrackerProfile(
            plannedDoseMg: 7.5,
            medicationRaw: Medication.tirzepatide.rawValue
        )
        let injections = [
            InjectionEntry(doseMg: 5, injectionDate: Self.fixtureDate(days: 1)),
            InjectionEntry(doseMg: 10, injectionDate: Self.fixtureDate(days: 8))
        ]
        let originalDoses = injections.map(\.doseMg)

        profile.applyMedication(.semaglutide, now: Self.fixtureDate(days: 9))

        XCTAssertEqual(profile.medication, .semaglutide)
        XCTAssertEqual(injections.map(\.doseMg), originalDoses)
    }

    func testDoseFormattingKeepsSemaglutidePrecision() {
        XCTAssertEqual(doseInputText(0.25), "0.25")
        XCTAssertEqual(doseText(0.25), "0.25 mg")
        XCTAssertEqual(doseText(2.5), "2.5 mg")
        XCTAssertEqual(doseText(10), "10 mg")
        XCTAssertEqual(doseOptionValues(for: .semaglutide), [0.25, 0.5, 1, 1.7, 2, 2.4, 7.2])
        XCTAssertEqual(doseOptionValues(for: .semaglutide, including: 7.5), [0.25, 0.5, 1, 1.7, 2, 2.4, 7.2, 7.5])
    }

    func testDoseColorBandsInferMedicationByDoseLadder() {
        XCTAssertEqual(Medication.tirzepatide.dosePresets.compactMap { doseColorBandIndex($0) }, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(doseColorBandIndex(0.25), 0)
        XCTAssertEqual(doseColorBandIndex(2.4), 4)
        XCTAssertEqual(doseColorBandIndex(7.2), 5)
        XCTAssertEqual(doseColorBandIndex(7.5), 2)
    }

    func testMedicationVerificationSampleScenariosCoverDoseStates() {
        let now = Self.fixtureDate(days: 200)
        let tirzepatide = DashboardSnapshot.medicationVerificationSeed(.tirzepatide, now: now)
        let semaglutide = DashboardSnapshot.medicationVerificationSeed(.semaglutide, now: now)
        let mixed = DashboardSnapshot.medicationVerificationSeed(.mixed, now: now)

        XCTAssertEqual(tirzepatide.profile.medication, .tirzepatide)
        XCTAssertEqual(tirzepatide.injections.map(\.doseMg), Medication.tirzepatide.dosePresets)
        XCTAssertEqual(semaglutide.profile.medication, .semaglutide)
        XCTAssertEqual(semaglutide.injections.map(\.doseMg), Medication.semaglutide.dosePresets)
        XCTAssertEqual(mixed.profile.medication, .tirzepatide)
        XCTAssertEqual(mixed.injections.map(\.doseMg), [0.25, 0.5, 1, 1.7, 2.4, 5, 10])
        XCTAssertEqual(mixed.injections.map { Medication.inferred(fromMg: $0.doseMg) }, [.semaglutide, .semaglutide, .semaglutide, .semaglutide, .semaglutide, .tirzepatide, .tirzepatide])
    }

    // MARK: - Log capture (v1)

    func testSideEffectToggleIsIdempotentUpsert() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()

        XCTAssertTrue(LogCapture.toggleSideEffect(.nausea, on: day, in: context))
        // A second "note" of the same symptom must not create a duplicate row.
        XCTAssertEqual(LogCapture.sideEffects(on: day, in: context).count, 1)

        // Toggling again clears it — one row max, never a double count.
        XCTAssertFalse(LogCapture.toggleSideEffect(.nausea, on: day, in: context))
        XCTAssertEqual(LogCapture.sideEffects(on: day, in: context).count, 0)
    }

    func testSeverityCyclesAndIsOptional() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()
        LogCapture.toggleSideEffect(.vomiting, on: day, in: context)

        XCTAssertNil(LogCapture.sideEffect(.vomiting, on: day, in: context)?.severity)
        LogCapture.cycleSeverity(for: .vomiting, on: day, in: context)
        XCTAssertEqual(LogCapture.sideEffect(.vomiting, on: day, in: context)?.severity, "mild")
        LogCapture.cycleSeverity(for: .vomiting, on: day, in: context)
        LogCapture.cycleSeverity(for: .vomiting, on: day, in: context)
        XCTAssertEqual(LogCapture.sideEffect(.vomiting, on: day, in: context)?.severity, "severe")
        LogCapture.cycleSeverity(for: .vomiting, on: day, in: context)
        XCTAssertNil(LogCapture.sideEffect(.vomiting, on: day, in: context)?.severity)
    }

    func testSeverityCanBeSetDirectlyAndCleared() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()
        LogCapture.toggleSideEffect(.nausea, on: day, in: context)

        LogCapture.setSeverity(.moderate, for: .nausea, on: day, in: context)
        XCTAssertEqual(LogCapture.sideEffect(.nausea, on: day, in: context)?.severity, "moderate")

        LogCapture.setSeverity(nil, for: .nausea, on: day, in: context)
        XCTAssertNil(LogCapture.sideEffect(.nausea, on: day, in: context)?.severity)
    }

    func testDirectSeveritySelectionCreatesSideEffectAndClearsAllClear() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()

        LogCapture.setAllClear(true, day: day, in: context)
        XCTAssertTrue(LogCapture.checkIn(on: day, in: context)?.allClear ?? false)

        LogCapture.recordSideEffect(.diarrhea, severity: .severe, on: day, in: context)

        XCTAssertEqual(LogCapture.sideEffect(.diarrhea, on: day, in: context)?.severity, "severe")
        XCTAssertFalse(LogCapture.checkIn(on: day, in: context)?.allClear ?? true)
    }

    func testLocalizedLabelsDoNotChangeStoredRawVocabulary() {
        XCTAssertEqual(SideEffectKind.allCases.map(\.rawValue), ["nausea", "vomiting", "constipation", "diarrhea"])
        XCTAssertEqual(SeverityLevel.allCases.map(\.rawValue), ["mild", "moderate", "severe"])
        XCTAssertEqual(MoodValence.allCases.map(\.rawValue), ["rough", "low", "okay", "good", "great"])
        XCTAssertEqual(
            InjectionSiteRotation.allSites,
            [
                "Abdomen - Left",
                "Abdomen - Right",
                "Thigh - Left",
                "Thigh - Right",
                "Upper Arm - Left",
                "Upper Arm - Right"
            ]
        )
    }

    func testAllClearAndSymptomsAreMutuallyExclusive() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()

        LogCapture.toggleSideEffect(.diarrhea, on: day, in: context)
        LogCapture.setAllClear(true, day: day, in: context)
        XCTAssertEqual(LogCapture.sideEffects(on: day, in: context).count, 0, "All clear removes noted symptoms")
        XCTAssertEqual(LogCapture.checkIn(on: day, in: context)?.allClear, true)

        // Noting a symptom afterwards must lift the all-clear flag.
        LogCapture.toggleSideEffect(.diarrhea, on: day, in: context)
        XCTAssertEqual(LogCapture.checkIn(on: day, in: context)?.allClear, false)
    }

    func testMoodAndNoteUpsertSingleCheckInPerDay() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()

        LogCapture.setMood(.good, on: day, in: context)
        LogCapture.setNote("felt steady", on: day, in: context)
        LogCapture.setMood(.great, on: day, in: context)

        let checkIns = try context.fetch(FetchDescriptor<DailyCheckIn>())
        XCTAssertEqual(checkIns.count, 1, "One DailyCheckIn per day, upserted")
        XCTAssertEqual(checkIns.first?.moodValence, "great")
        XCTAssertEqual(checkIns.first?.note, "felt steady")
    }

    func testAppendingNotesPreservesEarlierDailyNote() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Self.fixtureDate(days: 1)

        LogCapture.appendNote("Log tab note", on: day, in: context)
        LogCapture.appendNote("Summary daily note", on: day, in: context)

        let checkIns = try context.fetch(FetchDescriptor<DailyCheckIn>())
        XCTAssertEqual(checkIns.count, 1, "Appending notes must keep one DailyCheckIn per day")
        XCTAssertEqual(checkIns.first?.note, "Log tab note\n\nSummary daily note")
    }

    func testAppendingNotesPreservesEarlierDailyNoteInReverseOrder() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Self.fixtureDate(days: 2)

        LogCapture.appendNote("Summary daily note", on: day, in: context)
        LogCapture.appendNote("Log tab note", on: day, in: context)

        let checkIn = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyCheckIn>()).first)
        XCTAssertEqual(checkIn.note, "Summary daily note\n\nLog tab note")
    }

    func testAppendingPreloadedNoteDraftDoesNotDuplicateExistingNote() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Self.fixtureDate(days: 3)

        LogCapture.appendNote("Summary daily note", on: day, in: context)
        LogCapture.appendNote("Summary daily note\n\nLog tab note", on: day, in: context)

        let checkIn = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyCheckIn>()).first)
        XCTAssertEqual(checkIn.note, "Summary daily note\n\nLog tab note")
    }

    func testSetNoteKeepsExplicitReplaceSemantics() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Self.fixtureDate(days: 4)

        LogCapture.appendNote("Earlier note", on: day, in: context)
        LogCapture.setNote("Replacement note", on: day, in: context)

        let checkIn = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyCheckIn>()).first)
        XCTAssertEqual(checkIn.note, "Replacement note")
    }

    func testDayCaptureSnapshotAggregatesSymptomsAndCheckIn() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()
        LogCapture.toggleSideEffect(.nausea, on: day, in: context)
        LogCapture.cycleSeverity(for: .nausea, on: day, in: context)
        LogCapture.setMood(.okay, on: day, in: context)

        let captures = DashboardSnapshot.dayCaptureSnapshots(
            sideEffects: try context.fetch(FetchDescriptor<SideEffectEntry>()),
            checkIns: try context.fetch(FetchDescriptor<DailyCheckIn>())
        )
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures.first?.symptoms.first?.kind, .nausea)
        XCTAssertEqual(captures.first?.symptoms.first?.severity, .mild)
        XCTAssertEqual(captures.first?.mood, .okay)
    }

    func testStructuredLogNoteProjectsIntoDayCapture() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()

        LogCapture.toggleSideEffect(.nausea, on: day, in: context)
        LogCapture.setMood(.okay, on: day, in: context)
        LogCapture.setNote("Summary note visible in Log", on: day, in: context)

        let captures = DashboardSnapshot.dayCaptureSnapshots(
            sideEffects: try context.fetch(FetchDescriptor<SideEffectEntry>()),
            checkIns: try context.fetch(FetchDescriptor<DailyCheckIn>())
        )

        let capture = try XCTUnwrap(captures.first)
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(capture.symptoms.first?.kind, .nausea)
        XCTAssertEqual(capture.mood, .okay)
        XCTAssertEqual(capture.note, "Summary note visible in Log")
    }

    func testClearingOnlyMoodRemovesEmptyDayCapture() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()

        LogCapture.setMood(.okay, on: day, in: context)
        var captures = DashboardSnapshot.dayCaptureSnapshots(
            sideEffects: try context.fetch(FetchDescriptor<SideEffectEntry>()),
            checkIns: try context.fetch(FetchDescriptor<DailyCheckIn>())
        )
        XCTAssertEqual(captures.first?.mood, .okay)

        LogCapture.setMood(nil, on: day, in: context)

        let checkIn = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyCheckIn>()).first)
        XCTAssertNil(checkIn.moodValence)

        captures = DashboardSnapshot.dayCaptureSnapshots(
            sideEffects: try context.fetch(FetchDescriptor<SideEffectEntry>()),
            checkIns: try context.fetch(FetchDescriptor<DailyCheckIn>())
        )
        XCTAssertTrue(captures.isEmpty, "A day with only a cleared mood should disappear from Recent")
    }

    func testClearingMoodKeepsOtherDayCaptureDetails() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()

        LogCapture.toggleSideEffect(.nausea, on: day, in: context)
        LogCapture.setMood(.okay, on: day, in: context)
        LogCapture.setMood(nil, on: day, in: context)

        let captures = DashboardSnapshot.dayCaptureSnapshots(
            sideEffects: try context.fetch(FetchDescriptor<SideEffectEntry>()),
            checkIns: try context.fetch(FetchDescriptor<DailyCheckIn>())
        )

        let capture = try XCTUnwrap(captures.first)
        XCTAssertNil(capture.mood)
        XCTAssertEqual(capture.symptoms.first?.kind, .nausea)
    }

    // MARK: - Log capture (v1.1 system surfaces)

    func testLogSymptomDeepLinkRoutesToLogAndFlags() {
        let url = GauravaScreen.logSymptom.url
        XCTAssertEqual(url.absoluteString, "gaurava://log-symptom")
        XCTAssertEqual(DeepLinkRoute.tab(for: url), .log)
        XCTAssertTrue(DeepLinkRoute.isLogSymptom(url))
        XCTAssertFalse(DeepLinkRoute.isInjectionConfirmation(url))
    }

    func testLogSideEffectIntentRoutesToLogSymptomScreen() {
        XCTAssertEqual(LogSideEffectIntent().screen, .logSymptom)
    }

    func testSystemSourcedCaptureIsTaggedInTimeline() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()
        LogCapture.toggleSideEffect(.nausea, on: day, source: "system", in: context)

        let captures = DashboardSnapshot.dayCaptureSnapshots(
            sideEffects: try context.fetch(FetchDescriptor<SideEffectEntry>()),
            checkIns: try context.fetch(FetchDescriptor<DailyCheckIn>())
        )
        XCTAssertEqual(captures.first?.hasSystemSource, true)
    }

    func testClinicianExportSummarizesCapturesTruthfully() throws {
        let context = ModelContext(GauravaModelContainer.make(inMemory: true))
        let day = Date()
        LogCapture.toggleSideEffect(.nausea, on: day, in: context)
        LogCapture.cycleSeverity(for: .nausea, on: day, in: context)
        LogCapture.setMood(.okay, on: day, in: context)

        var dashboard = DashboardSnapshot.empty
        dashboard.dayCaptures = DashboardSnapshot.dayCaptureSnapshots(
            sideEffects: try context.fetch(FetchDescriptor<SideEffectEntry>()),
            checkIns: try context.fetch(FetchDescriptor<DailyCheckIn>())
        )

        let summary = ClinicianExport.summary(from: dashboard)
        XCTAssertTrue(summary.hasData)
        XCTAssertEqual(summary.rows.count, 1)
        XCTAssertEqual(summary.symptomTotals.first { $0.kind == .nausea }?.count, 1)
        XCTAssertEqual(summary.symptomTotals.first { $0.kind == .vomiting }?.count, 0)
        XCTAssertTrue(summary.summaryLine.contains("nausea"))
    }

    func testClinicianExportMapsDoseAndHidesAllClearRows() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Self.fixtureDate(days: 50)
        func day(_ value: Int) -> Date {
            calendar.startOfDay(for: Self.fixtureDate(days: value))
        }

        var dashboard = DashboardSnapshot.empty
        dashboard.injections = [
            InjectionSnapshot(doseMg: 2.5, injectionSite: "Abdomen - Left", injectionDate: day(10), batchNumber: nil, notes: nil),
            InjectionSnapshot(doseMg: 5, injectionSite: "Abdomen - Right", injectionDate: day(20), batchNumber: nil, notes: nil),
            InjectionSnapshot(doseMg: 2.5, injectionSite: "Thigh - Left", injectionDate: day(30), batchNumber: nil, notes: nil)
        ]
        dashboard.dayCaptures = [
            DayCaptureSnapshot(
                logDate: day(23),
                symptoms: [],
                mood: .good,
                allClear: true,
                note: nil
            ),
            DayCaptureSnapshot(
                logDate: day(22),
                symptoms: [],
                mood: nil,
                allClear: true,
                note: nil
            ),
            DayCaptureSnapshot(
                logDate: day(21),
                symptoms: [SymptomCapture(kind: .nausea, severity: .mild, fromSystem: false)],
                mood: .okay,
                allClear: false,
                note: nil
            ),
            DayCaptureSnapshot(
                logDate: day(12),
                symptoms: [],
                mood: nil,
                allClear: false,
                note: "ask about hydration"
            ),
            DayCaptureSnapshot(
                logDate: day(5),
                symptoms: [SymptomCapture(kind: .vomiting, severity: nil, fromSystem: false)],
                mood: nil,
                allClear: false,
                note: nil
            )
        ]

        let summary = ClinicianExport.summary(from: dashboard, now: now, calendar: calendar)

        XCTAssertTrue(summary.hasData)
        XCTAssertEqual(summary.rows.count, 3)
        XCTAssertEqual(summary.hiddenAllClearCount, 2)
        XCTAssertEqual(summary.loggedDayCount, 5)
        XCTAssertEqual(summary.rows.map(\.date), [day(21), day(12), day(5)])
        XCTAssertEqual(summary.rows[0].activeDoseMg, 5)
        XCTAssertEqual(summary.rows[1].activeDoseMg, 2.5)
        XCTAssertNil(summary.rows[2].activeDoseMg)
        XCTAssertEqual(summary.symptomTotals.first { $0.kind == .nausea }?.count, 1)
        XCTAssertEqual(summary.symptomTotals.first { $0.kind == .vomiting }?.count, 1)
        XCTAssertEqual(summary.doseChanges.map(\.doseMg), [2.5, 5, 2.5])
        XCTAssertTrue(summary.doseLine?.contains(doseText(2.5)) ?? false)
        XCTAssertEqual(summary.currentDoseMg, 2.5)
        XCTAssertTrue(summary.summaryLine.contains("all-clear"))

        dashboard.dayCaptures = [
            DayCaptureSnapshot(
                logDate: day(24),
                symptoms: [],
                mood: nil,
                allClear: true,
                note: nil
            )
        ]
        let allClearOnly = ClinicianExport.summary(from: dashboard, now: now, calendar: calendar)
        XCTAssertFalse(allClearOnly.hasData)
        XCTAssertEqual(allClearOnly.hiddenAllClearCount, 1)
        XCTAssertTrue(allClearOnly.summaryLine.contains("all-clear"))
    }

    func testPreviewSnapshotHasCoreTabsData() {
        let snapshot = DashboardSnapshot.preview

        XCTAssertNotNil(snapshot.currentWeight)
        XCTAssertFalse(snapshot.injections.isEmpty)
        XCTAssertFalse(snapshot.dailyLogs.isEmpty)
        XCTAssertGreaterThan(snapshot.progress, 0)
    }

    func testShareCardSnapshotBuildsDoseAwareJourneyData() {
        let dashboard = Self.shareCardFixture()
        let cardSnapshot = ShareCardSnapshot(
            dashboard: dashboard,
            now: Self.fixtureDate(days: 70),
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(cardSnapshot.weekCount, 11)
        XCTAssertEqual(cardSnapshot.currentDoseMg, 5)
        XCTAssertEqual(cardSnapshot.doseSteps.map(\.doseMg), [2.5, 5])
        XCTAssertEqual(cardSnapshot.weightPoints.last?.doseMg, 5)
        XCTAssertEqual(cardSnapshot.totalLostKg ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(cardSnapshot.percentLost ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(cardSnapshot.progressToGoal ?? 0, 0.5, accuracy: 0.001)
    }

    func testShareCardFormatterHonorsPrivacyAndUnitChoices() {
        let cardSnapshot = ShareCardSnapshot(
            dashboard: Self.shareCardFixture(),
            now: Self.fixtureDate(days: 70),
            calendar: Calendar(identifier: .gregorian)
        )

        let exactPounds = ShareCardFormatter(
            snapshot: cardSnapshot,
            configuration: ShareCardConfiguration(
                template: .story,
                colorScheme: .light,
                privacyMode: .exact,
                dateVisibility: .show,
                unit: .lb
            )
        )
        XCTAssertEqual(exactPounds.loss(), "-22.0 lb")
        XCTAssertEqual(exactPounds.weight(cardSnapshot.currentWeightKg), "198.4 lb")

        let percentOnly = ShareCardFormatter(
            snapshot: cardSnapshot,
            configuration: ShareCardConfiguration(
                template: .story,
                colorScheme: .light,
                privacyMode: .percentOnly,
                dateVisibility: .hide,
                unit: .kg
            )
        )
        XCTAssertEqual(percentOnly.loss(), "-10.0%")
        XCTAssertEqual(percentOnly.weight(cardSnapshot.currentWeightKg), "90.0%")
    }

    func testShareCardWeeklyRateReconcilesWithWeekCount() {
        let cardSnapshot = ShareCardSnapshot(
            dashboard: Self.shareCardFixture(),
            now: Self.fixtureDate(days: 70),
            calendar: Calendar(identifier: .gregorian)
        )

        // The Weekly rate must average the total change over the exact week
        // count the card prints on the "Weeks" tile, so loss / Weeks == Weekly.
        let expectedWeekly = (cardSnapshot.totalLostKg ?? 0) / Double(cardSnapshot.weekCount)
        XCTAssertEqual(cardSnapshot.weeklyAverageLossKg ?? 0, expectedWeekly, accuracy: 0.0001)

        let percentOnly = ShareCardFormatter(
            snapshot: cardSnapshot,
            configuration: ShareCardConfiguration(
                template: .dataSheet,
                colorScheme: .light,
                privacyMode: .percentOnly,
                dateVisibility: .hide,
                unit: .kg
            )
        )
        // 10% lost over 11 weeks -> 0.91%/wk, which reconciles with -10.0% / 11.
        XCTAssertEqual(percentOnly.weeklyAverage(), "0.91%/wk")
        XCTAssertEqual((cardSnapshot.percentLost ?? 0) / Double(cardSnapshot.weekCount), 0.909_090, accuracy: 0.0001)
    }

    func testShareCardLossProgressFramingInPercentMode() {
        let cardSnapshot = ShareCardSnapshot(
            dashboard: Self.shareCardFixture(),
            now: Self.fixtureDate(days: 70),
            calendar: Calendar(identifier: .gregorian)
        )

        let percentOnly = ShareCardFormatter(
            snapshot: cardSnapshot,
            configuration: ShareCardConfiguration(
                template: .dataSheet,
                colorScheme: .light,
                privacyMode: .percentOnly,
                dateVisibility: .hide,
                unit: .kg
            )
        )
        // Loss + progress framing: no "% of starting weight remaining" anywhere.
        // start 100, current 90, goal 80 -> lost 10%, 50% of the way, goal -20%.
        XCTAssertEqual(percentOnly.progressToGoalText(), "50%")
        XCTAssertEqual(percentOnly.goalTarget(), "-20.0%")

        let exact = ShareCardFormatter(
            snapshot: cardSnapshot,
            configuration: ShareCardConfiguration(
                template: .dataSheet,
                colorScheme: .light,
                privacyMode: .exact,
                dateVisibility: .show,
                unit: .kg
            )
        )
        // Exact mode keeps the literal goal weight.
        XCTAssertEqual(exact.goalTarget(), "80.0 kg")
    }

    func testShareCardCanvasSizesMatchExportSpecs() {
        XCTAssertEqual(ShareCardTemplate.allCases.map(\.rawValue), ["story", "milestone", "dataSheet"])
        XCTAssertEqual(ShareCardCanvas.portrait.pixels, CGSize(width: 1080, height: 1350))
        XCTAssertEqual(ShareCardCanvas.portrait.points, CGSize(width: 360, height: 450))

        for template in ShareCardTemplate.allCases {
            XCTAssertEqual(template.canvas.pixels, CGSize(width: 1080, height: 1920))
            XCTAssertEqual(template.canvas.points, CGSize(width: 360, height: 640))
        }
    }

    @MainActor
    func testShareCardRendererProducesVerticalAssetsForEveryTemplate() throws {
        let dashboard = Self.shareCardArtifactFixture()

        for template in ShareCardTemplate.allCases {
            let asset = try ShareCardRenderer.render(
                dashboard: dashboard,
                configuration: ShareCardConfiguration(
                    template: template,
                    colorScheme: .light,
                    privacyMode: .exact,
                    dateVisibility: .show,
                    unit: .kg
                )
            )

            let image = try XCTUnwrap(asset.image.cgImage)
            XCTAssertEqual(image.width, 1080)
            XCTAssertEqual(image.height, 1920)
            XCTAssertFalse(asset.pngData.isEmpty)
            try? FileManager.default.removeItem(at: asset.fileURL)
        }
    }

    @MainActor
    func testShareAndClinicianArtifactsRenderWithSafeFilenames() throws {
        let fileManager = FileManager.default
        let dashboard = Self.shareCardArtifactFixture()
        let artifactDirectory = ProcessInfo.processInfo.environment["GAURAVA_PHASE4_ARTIFACT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.temporaryDirectory.appendingPathComponent("GauravaPhase4Artifacts", isDirectory: true)
        try? fileManager.removeItem(at: artifactDirectory)
        try fileManager.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        for template in ShareCardTemplate.allCases {
            let asset = try ShareCardRenderer.render(
                dashboard: dashboard,
                configuration: ShareCardConfiguration(
                    template: template,
                    colorScheme: .light,
                    privacyMode: .exact,
                    dateVisibility: .show,
                    unit: .kg
                )
            )

            XCTAssertTrue(asset.fileURL.lastPathComponent.hasPrefix("Gaurava-Journey-"))
            XCTAssertTrue(Self.isSafeShareExportFilename(asset.fileURL.lastPathComponent))

            let output = artifactDirectory.appendingPathComponent("share-card-\(template.rawValue).png")
            try? fileManager.removeItem(at: output)
            try asset.pngData.write(to: output, options: .atomic)

            try? fileManager.removeItem(at: asset.fileURL)
        }

        var clinicianDashboard = dashboard
        let logDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -6, to: Date()) ?? Date()
        clinicianDashboard.dayCaptures = [
            DayCaptureSnapshot(
                logDate: logDate,
                symptoms: [
                    SymptomCapture(kind: .nausea, severity: .mild, fromSystem: false),
                    SymptomCapture(kind: .constipation, severity: nil, fromSystem: false)
                ],
                mood: .okay,
                allClear: false,
                note: "review at appointment"
            )
        ]

        let summary = ClinicianExport.summary(
            from: clinicianDashboard,
            now: Date(),
            calendar: Calendar(identifier: .gregorian)
        )
        let clinicianImage = try ClinicianExport.makeImage(summary, displayName: "Gaurava")
        let renderedImage = try XCTUnwrap(clinicianImage.image.cgImage)
        XCTAssertEqual(renderedImage.width, 1080)
        XCTAssertEqual(renderedImage.height, 1350)
        XCTAssertFalse(clinicianImage.pngData.isEmpty)
        XCTAssertTrue(clinicianImage.fileURL.lastPathComponent.hasPrefix("Gaurava-Clinician-"))
        XCTAssertTrue(Self.isSafeShareExportFilename(clinicianImage.fileURL.lastPathComponent))

        let clinicianImageOutput = artifactDirectory.appendingPathComponent("clinician-summary-image.png")
        try? fileManager.removeItem(at: clinicianImageOutput)
        try clinicianImage.pngData.write(to: clinicianImageOutput, options: .atomic)

        let pdfURL = try XCTUnwrap(ClinicianExport.makePDF(summary, displayName: "Gaurava"))
        XCTAssertTrue(pdfURL.lastPathComponent.hasPrefix("Gaurava-Side-Effects-"))
        XCTAssertTrue(Self.isSafeShareExportFilename(pdfURL.lastPathComponent))
        XCTAssertGreaterThan(try XCTUnwrap(fileManager.attributesOfItem(atPath: pdfURL.path)[.size] as? NSNumber).intValue, 0)

        let output = artifactDirectory.appendingPathComponent("clinician-side-effects.pdf")
        try? fileManager.removeItem(at: output)
        try fileManager.copyItem(at: pdfURL, to: output)

        try? fileManager.removeItem(at: clinicianImage.fileURL)
        try? fileManager.removeItem(at: pdfURL)
    }

    func testEmptySnapshotHasNoOwnerData() {
        let snapshot = DashboardSnapshot.empty

        XCTAssertFalse(snapshot.hasProfile)
        XCTAssertFalse(snapshot.hasAnyData)
        XCTAssertNil(snapshot.currentWeight)
        XCTAssertTrue(snapshot.injections.isEmpty)
        XCTAssertTrue(snapshot.dailyLogs.isEmpty)
    }

    func testGauravaDataExporterIncludesCoreRecords() throws {
        let generatedAt = Self.fixtureDate(days: 12)
        let profile = TrackerProfile(legacyServerId: "profile-1", age: 42, startingWeightKg: 98.0, goalWeightKg: 82.0)
        let preference = UserPreference(legacyServerId: "preference-1", weightUnit: "kg", heightUnit: "cm")
        preference.preferredInjectionSites = ["Abdomen - Left", "Thigh - Right"]
        let weight = WeightEntry(legacyServerId: "weight-1", weightKg: 98.4, recordedAt: generatedAt)
        let injection = InjectionEntry(legacyServerId: "jab-1", doseMg: 7.5, injectionSite: "Abdomen - Left", injectionDate: generatedAt)
        let pause = TreatmentPause(legacyServerId: "pause-1", startedAt: generatedAt, reason: "Travel")
        let log = DailyLog(legacyServerId: "log-1", logDate: generatedAt, notes: "Steady")
        let entry = DailyLogEntry(legacyServerId: "entry-1", logDate: generatedAt, entryText: "Hydration on track")
        let receipt = SeedImportReceipt(sourceEmail: "verification@example.com", importedAt: generatedAt, status: "completed")

        let data = try GauravaDataExporter.makeExportData(
            profiles: [profile],
            preferences: [preference],
            weights: [weight],
            injections: [injection],
            treatmentPauses: [pause],
            dailyLogs: [log],
            dailyLogEntries: [entry],
            receipts: [receipt],
            generatedAt: generatedAt
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try XCTUnwrap(object["metadata"] as? [String: Any])

        XCTAssertEqual(metadata["cloudKitContainerIdentifier"] as? String, "iCloud.com.nags.gaurava")
        XCTAssertEqual((object["profiles"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object["preferences"] as? [[String: Any]])?.first?["preferredInjectionSites"] as? [String], ["Abdomen - Left", "Thigh - Right"])
        XCTAssertEqual((object["weights"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object["injections"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object["treatmentPauses"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object["dailyLogs"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object["dailyLogEntries"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object["receipts"] as? [[String: Any]])?.count, 1)
    }

    func testSeedImporterIsIdempotentForCoreRecords() throws {
        let container = GauravaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let importer = SeedImporter(context: context)
        let data = Data(Self.syntheticSeedJSON.utf8)

        let firstSummary = try importer.importSeed(data: data)
        let secondSummary = try importer.importSeed(data: data)

        XCTAssertEqual(firstSummary, secondSummary)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrackerProfile>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserPreference>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InjectionEntry>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TreatmentPause>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyLog>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyLogEntry>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SeedImportReceipt>()).count, 1)

        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<TrackerProfile>()).first)
        XCTAssertEqual(profile.legacyServerId, "profile-1")
        XCTAssertEqual(profile.sourceUserId, "user-1")
        XCTAssertEqual(profile.plannedDoseMg, 7.5)
        XCTAssertEqual(profile.medication, .tirzepatide)

        let weight = try XCTUnwrap(context.fetch(FetchDescriptor<WeightEntry>()).first)
        XCTAssertEqual(weight.clientMutationId, "client-weight-1")
        XCTAssertEqual(weight.weightKg, 90.8)

        let receipt = try XCTUnwrap(context.fetch(FetchDescriptor<SeedImportReceipt>()).first)
        XCTAssertEqual(receipt.sourceEmail, "verification@example.com")
        XCTAssertEqual(receipt.status, "imported")
        XCTAssertTrue(receipt.countsJSON.contains("\"weightEntries\":1"))

        let snapshot = DashboardSnapshot.fromModels(
            profiles: try context.fetch(FetchDescriptor<TrackerProfile>()),
            preferences: try context.fetch(FetchDescriptor<UserPreference>()),
            weights: try context.fetch(FetchDescriptor<WeightEntry>()),
            injections: try context.fetch(FetchDescriptor<InjectionEntry>()),
            dailyLogs: try context.fetch(FetchDescriptor<DailyLog>()),
            dailyLogEntries: try context.fetch(FetchDescriptor<DailyLogEntry>()),
            sideEffects: try context.fetch(FetchDescriptor<SideEffectEntry>()),
            checkIns: try context.fetch(FetchDescriptor<DailyCheckIn>()),
            receipts: try context.fetch(FetchDescriptor<SeedImportReceipt>())
        )
        XCTAssertEqual(snapshot.weights.count, 1)
        XCTAssertEqual(snapshot.injections.count, 1)
        XCTAssertEqual(snapshot.dailyLogs.count, 1)
        XCTAssertEqual(snapshot.receiptEmail, "verification@example.com")
    }

    func testMedicationSeedFixturesImportIdempotently() throws {
        let fixtureCases: [(fixture: String, medication: Medication, doses: [Double], inferred: [Medication], sideEffects: Int, checkIns: Int)] = [
            (
                "seed-semaglutide-titration",
                .semaglutide,
                [0.25, 0.5, 1, 1.7, 2, 2.4, 7.2],
                Array(repeating: .semaglutide, count: 7),
                2,
                2
            ),
            (
                "seed-tirzepatide",
                .tirzepatide,
                [2.5, 5, 7.5, 10, 12.5, 15],
                Array(repeating: .tirzepatide, count: 6),
                0,
                0
            ),
            (
                "seed-mixed-switch",
                .tirzepatide,
                [0.25, 0.5, 1, 1.7, 2.4, 5, 10],
                [.semaglutide, .semaglutide, .semaglutide, .semaglutide, .semaglutide, .tirzepatide, .tirzepatide],
                1,
                1
            )
        ]

        for fixtureCase in fixtureCases {
            let container = GauravaModelContainer.make(inMemory: true)
            let context = ModelContext(container)
            let importer = SeedImporter(context: context)
            let data = try Self.seedFixtureData(named: fixtureCase.fixture)

            let firstSummary = try importer.importSeed(data: data)
            let secondSummary = try importer.importSeed(data: data)

            XCTAssertEqual(firstSummary, secondSummary, fixtureCase.fixture)
            XCTAssertEqual(try context.fetch(FetchDescriptor<TrackerProfile>()).count, 1, fixtureCase.fixture)
            XCTAssertEqual(try context.fetch(FetchDescriptor<UserPreference>()).count, 1, fixtureCase.fixture)
            XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).count, fixtureCase.fixture == "seed-tirzepatide" ? 1 : 2, fixtureCase.fixture)
            XCTAssertEqual(try context.fetch(FetchDescriptor<InjectionEntry>()).count, fixtureCase.doses.count, fixtureCase.fixture)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SideEffectEntry>()).count, fixtureCase.sideEffects, fixtureCase.fixture)
            XCTAssertEqual(try context.fetch(FetchDescriptor<DailyCheckIn>()).count, fixtureCase.checkIns, fixtureCase.fixture)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SeedImportReceipt>()).count, 1, fixtureCase.fixture)

            let profile = try XCTUnwrap(context.fetch(FetchDescriptor<TrackerProfile>()).first)
            XCTAssertEqual(profile.medication, fixtureCase.medication, fixtureCase.fixture)

            let injections = try context.fetch(FetchDescriptor<InjectionEntry>())
                .sorted { $0.injectionDate < $1.injectionDate }
            for (actual, expected) in zip(injections.map(\.doseMg), fixtureCase.doses) {
                XCTAssertEqual(actual, expected, accuracy: 0.001, fixtureCase.fixture)
            }
            XCTAssertEqual(injections.map { Medication.inferred(fromMg: $0.doseMg) }, fixtureCase.inferred, fixtureCase.fixture)
        }
    }

    func testSeedImportSummaryCanBePreviewedBeforeImport() throws {
        let envelope = try JSONDecoder().decode(SeedImportEnvelope.self, from: Data(Self.syntheticSeedJSON.utf8))
        let summary = SeedImportSummary(data: envelope.data)

        XCTAssertEqual(envelope.meta.subjectEmail, "verification@example.com")
        XCTAssertEqual(summary.totalRecords, 7)
        XCTAssertEqual(summary.displayText, "1 profile, 1 preference, 1 weights, 1 jabs, 1 pauses, 1 daily logs, 1 log entries")
    }

    func testOwnerImportUIRequiresExplicitGate() {
        XCTAssertFalse(OwnerImportGate.isUserInterfaceEnabled(arguments: [], environment: [:]))
        XCTAssertTrue(OwnerImportGate.isUserInterfaceEnabled(arguments: ["--gaurava-owner-import-ui"], environment: [:]))
        XCTAssertTrue(OwnerImportGate.isUserInterfaceEnabled(arguments: [], environment: ["GAURAVA_OWNER_IMPORT_UI": "1"]))
        XCTAssertTrue(OwnerImportGate.isUserInterfaceEnabled(arguments: [], environment: ["GAURAVA_OWNER_IMPORT_UI": "true"]))
    }

    func testPreferredInjectionSitesDriveSuggestedSiteRotation() {
        let preference = UserPreference()
        preference.preferredInjectionSites = ["Thigh - Left", "Thigh - Right"]
        let lastInjection = InjectionEntry(
            doseMg: 7.5,
            injectionSite: "Thigh - Left",
            injectionDate: Date()
        )

        let snapshot = DashboardSnapshot.fromModels(
            profiles: [],
            preferences: [preference],
            weights: [],
            injections: [lastInjection],
            dailyLogs: [],
            dailyLogEntries: [],
            sideEffects: [],
            checkIns: [],
            receipts: []
        )

        XCTAssertEqual(snapshot.preferences.preferredInjectionSites, ["Thigh - Left", "Thigh - Right"])
        XCTAssertEqual(snapshot.suggestedInjectionSite, "Thigh - Right")
    }

    func testPreferredInjectionSiteRotationFallsBackWhenLastSiteIsOutsidePreference() {
        let preference = UserPreference()
        preference.preferredInjectionSites = ["Abdomen - Left", "Abdomen - Right"]
        let lastInjection = InjectionEntry(
            doseMg: 7.5,
            injectionSite: "Upper Arm - Left",
            injectionDate: Date()
        )

        let snapshot = DashboardSnapshot.fromModels(
            profiles: [],
            preferences: [preference],
            weights: [],
            injections: [lastInjection],
            dailyLogs: [],
            dailyLogEntries: [],
            sideEffects: [],
            checkIns: [],
            receipts: []
        )

        XCTAssertEqual(snapshot.suggestedInjectionSite, "Abdomen - Left")
    }

    func testPrivateOwnerSeedDecodesAndImportsWhenAvailable() throws {
        let seedURL = URL(fileURLWithPath: Self.privateOwnerSeedPath)
        guard FileManager.default.fileExists(atPath: seedURL.path) else {
            throw XCTSkip("Private owner seed JSON is not available on this machine.")
        }

        let container = GauravaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let importer = SeedImporter(context: context)
        let data = try Data(contentsOf: seedURL)

        let firstSummary = try importer.importSeed(data: data)
        let secondSummary = try importer.importSeed(data: data)

        XCTAssertEqual(firstSummary, secondSummary)
        XCTAssertEqual(firstSummary.profiles, 1)
        XCTAssertEqual(firstSummary.preferences, 2)
        XCTAssertEqual(firstSummary.weightEntries, 15)
        XCTAssertEqual(firstSummary.injections, 23)
        XCTAssertEqual(firstSummary.treatmentPauses, 1)
        XCTAssertEqual(firstSummary.dailyLogs, 38)
        XCTAssertEqual(firstSummary.dailyLogEntries, 8)

        XCTAssertEqual(try context.fetch(FetchDescriptor<TrackerProfile>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserPreference>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).count, 15)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InjectionEntry>()).count, 23)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TreatmentPause>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyLog>()).count, 38)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyLogEntry>()).count, 8)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SeedImportReceipt>()).count, 1)
        XCTAssertEqual(try XCTUnwrap(context.fetch(FetchDescriptor<TrackerProfile>()).first).medication, .tirzepatide)

        let preferences = try context.fetch(FetchDescriptor<UserPreference>())
        XCTAssertTrue(preferences.contains { $0.preferredInjectionSites == ["Abdomen - Left", "Abdomen - Right"] })

        let entries = try context.fetch(FetchDescriptor<DailyLogEntry>())
        XCTAssertTrue(entries.contains { $0.entryText == "Hello" })
    }

    private static let privateOwnerSeedPath = PrivateOwnerSeed.path

    private static func seedFixtureData(named name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
            .appendingPathExtension("json")
        return try Data(contentsOf: url)
    }

    private static func shareCardFixture() -> DashboardSnapshot {
        DashboardSnapshot(
            profile: ProfileSnapshot(
                displayName: "Gaurava",
                email: "profile@example.com",
                age: 0,
                gender: "",
                heightCm: 180,
                startingWeightKg: 100,
                goalWeightKg: 80,
                treatmentStartDate: fixtureDate(days: 0),
                plannedDoseMg: 5,
                medication: .tirzepatide,
                preferredInjectionDay: nil,
                reminderDaysBefore: 1
            ),
            preferences: PreferenceSnapshot(
                weightUnit: "kg",
                heightUnit: "cm",
                dateFormat: "DD/MM/YYYY",
                weekStartsOn: 1,
                theme: "system",
                preferredInjectionSites: InjectionSiteRotation.allSites
            ),
            weights: [
                WeightSnapshot(weightKg: 100, recordedAt: fixtureDate(days: 0), notes: nil),
                WeightSnapshot(weightKg: 95, recordedAt: fixtureDate(days: 35), notes: nil),
                WeightSnapshot(weightKg: 90, recordedAt: fixtureDate(days: 70), notes: nil)
            ],
            injections: [
                InjectionSnapshot(doseMg: 2.5, injectionSite: "Abdomen - Left", injectionDate: fixtureDate(days: 0), batchNumber: nil, notes: nil),
                InjectionSnapshot(doseMg: 5, injectionSite: "Abdomen - Right", injectionDate: fixtureDate(days: 28), batchNumber: nil, notes: nil)
            ],
            dailyLogs: [],
            hasProfile: true,
            receiptEmail: nil
        )
    }

    private static func shareCardArtifactFixture(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> DashboardSnapshot {
        let start = calendar.date(byAdding: .day, value: -70, to: now) ?? now
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: start) ?? start
        }

        var dashboard = shareCardFixture()
        dashboard.profile.treatmentStartDate = day(0)
        dashboard.weights = [
            WeightSnapshot(weightKg: 100, recordedAt: day(0), notes: nil),
            WeightSnapshot(weightKg: 95, recordedAt: day(35), notes: nil),
            WeightSnapshot(weightKg: 90, recordedAt: day(70), notes: nil)
        ]
        dashboard.injections = [
            InjectionSnapshot(doseMg: 2.5, injectionSite: "Abdomen - Left", injectionDate: day(0), batchNumber: nil, notes: nil),
            InjectionSnapshot(doseMg: 5, injectionSite: "Abdomen - Right", injectionDate: day(28), batchNumber: nil, notes: nil)
        ]
        return dashboard
    }

    private static func fixtureDate(days: Int) -> Date {
        Date(timeIntervalSince1970: Double(days) * 86_400)
    }

    private static func isSafeShareExportFilename(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return !value.isEmpty && value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static let syntheticSeedJSON = """
    {
      "meta": {
        "sourceProduct": "mounjaro-tracker-web",
        "targetProduct": "gaurava-ios",
        "subjectEmail": "verification@example.com",
        "exportedAt": "2026-05-31T08:02:51.715Z",
        "version": "1.0",
        "sha256": "synthetic-checksum"
      },
      "account": {
        "id": "user-1",
        "email": "verification@example.com"
      },
      "data": {
        "profiles": [
          {
            "id": "profile-1",
            "user_id": "user-1",
            "age": 44,
            "gender": "male",
            "height_cm": "178.0",
            "starting_weight_kg": "98.0",
            "goal_weight_kg": "82.0",
            "treatment_start_date": "2026-03-01",
            "planned_dose_mg": "7.5",
            "planned_dose_updated_at": "2026-05-20T10:00:00.000Z",
            "preferred_injection_day": 6,
            "reminder_days_before": 1,
            "created_at": "2026-03-01T10:00:00.000Z",
            "updated_at": "2026-05-20T10:00:00.000Z"
          }
        ],
        "userPreferences": [
          {
            "id": "preferences-1",
            "user_id": "user-1",
            "weight_unit": "kg",
            "height_unit": "cm",
            "date_format": "DD/MM/YYYY",
            "week_starts_on": 1,
            "theme": "system",
            "created_at": "2026-03-01T10:00:00.000Z",
            "updated_at": "2026-05-20T10:00:00.000Z"
          }
        ],
        "weightEntries": [
          {
            "id": "weight-1",
            "user_id": "user-1",
            "weight_kg": "90.8",
            "recorded_at": "2026-05-28T08:00:00.000Z",
            "time_zone_identifier": "Asia/Kolkata",
            "notes": "Synthetic fixture",
            "client_mutation_id": "client-weight-1",
            "source_daily_log_entry_id": "daily-entry-1",
            "source_chat_message_id": "chat-message-1",
            "created_at": "2026-05-28T08:00:00.000Z",
            "updated_at": "2026-05-28T08:00:00.000Z"
          }
        ],
        "injections": [
          {
            "id": "injection-1",
            "user_id": "user-1",
            "dose_mg": "7.5",
            "injection_site": "Abdomen - Left",
            "injection_date": "2026-05-24T08:00:00.000Z",
            "time_zone_identifier": "Asia/Kolkata",
            "batch_number": "batch-1",
            "notes": "Synthetic fixture",
            "client_mutation_id": "client-injection-1",
            "source_chat_message_id": "chat-message-2",
            "created_at": "2026-05-24T08:00:00.000Z",
            "updated_at": "2026-05-24T08:00:00.000Z"
          }
        ],
        "treatmentPauses": [
          {
            "id": "pause-1",
            "user_id": "user-1",
            "started_at": "2026-04-01T08:00:00.000Z",
            "ended_at": "2026-04-08T08:00:00.000Z",
            "reason": "Synthetic fixture",
            "resumed_on_date": "2026-04-09",
            "created_at": "2026-04-01T08:00:00.000Z"
          }
        ],
        "dailyLogs": [
          {
            "id": "daily-log-1",
            "user_id": "user-1",
            "log_date": "2026-05-28",
            "created_at": "2026-05-28T08:00:00.000Z",
            "updated_at": "2026-05-28T08:00:00.000Z"
          }
        ],
        "dailyLogEntries": [
          {
            "id": "daily-entry-1",
            "user_id": "user-1",
            "log_date": "2026-05-28",
            "recorded_at": "2026-05-28T08:00:00.000Z",
            "time_zone_identifier": "Asia/Kolkata",
            "source": "typed",
            "raw_text": "Synthetic fixture log",
            "ai_draft": {"kind": "note"},
            "deleted_at": null,
            "client_mutation_id": "client-log-1",
            "source_chat_message_id": "chat-message-3",
            "created_at": "2026-05-28T08:00:00.000Z",
            "updated_at": "2026-05-28T08:00:00.000Z"
          }
        ]
      }
    }
    """
}
