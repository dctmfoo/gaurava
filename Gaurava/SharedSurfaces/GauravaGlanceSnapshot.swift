import Foundation

// The platform-neutral glance surface contract.
//
// Foundation only. No SwiftUI, no WidgetKit, no SwiftData. This is the single
// payload that crosses the app -> surface process boundary. Producer-side
// redaction means privacy decisions are baked in here by the app; the widget
// renders whatever slices are present and never holds raw values it must hide.
//
// See docs/widget-build-runbook.md (Appendix C) and
// docs/widget-options-deep-dive.html.

enum SurfacePrivacyMode: String, Codable, Sendable {
    case full      // exact values
    case minimal   // fractions and schedule, no absolute weights (default)
    case redacted  // semantic status + day count only
}

struct NextActionSlice: Codable, Equatable, Sendable {
    var daysUntilNextInjection: Int?
    var nextInjectionDate: Date?
    var doseMg: Double?
    var suggestedSite: String?
    /// Producer-computed dose color band index, mirroring `AppTheme.doseColorRamp`
    /// (see `doseColorBandIndex` in AppStyle.swift). Baked in here so surfaces can
    /// color the dose value by its band without importing the app's dose-preset
    /// logic. Optional + defaulted so older snapshots decode to `nil`.
    var doseBandIndex: Int? = nil
}

struct ProgressSlice: Codable, Equatable, Sendable {
    var progressToGoal: Double          // 0...1, always safe to show
    var currentWeightKg: Double?        // omitted under minimal/redacted
    var totalLostKg: Double?            // omitted under minimal/redacted
    var startingWeightKg: Double?
    var goalWeightKg: Double?
    var weightUnit: String
}

struct TrendPoint: Codable, Equatable, Sendable {
    var date: Date
    var weightKg: Double
}

struct TrendSlice: Codable, Equatable, Sendable {
    var points: [TrendPoint]
}

enum SafeStatusKind: String, Codable, Equatable, Sendable {
    case noDataYet
    case noDoseScheduled
    case doseDue
    case nextDoseInDays
}

struct SafeStatusSlice: Codable, Equatable, Sendable {
    /// Semantic status for schema v2+. Surfaces resolve this in their own bundle
    /// and locale so widgets/watch never preserve producer-locale prose.
    var kind: SafeStatusKind?
    /// Count used by pluralized status strings. Stored here even though
    /// `NextActionSlice` also carries the display day count, so redacted and
    /// legacy-compatible status rendering has all grammar variables in one slice.
    var daysUntilNextInjection: Int?
    /// Schema v1 compatibility only. New producers leave this nil.
    var phrase: String?

    init(kind: SafeStatusKind, daysUntilNextInjection: Int? = nil) {
        self.kind = kind
        self.daysUntilNextInjection = daysUntilNextInjection
        self.phrase = nil
    }

    init(legacyPhrase: String) {
        self.kind = nil
        self.daysUntilNextInjection = nil
        self.phrase = legacyPhrase
    }

    static func nextDose(daysUntil: Int?) -> SafeStatusSlice {
        guard let daysUntil else { return SafeStatusSlice(kind: .noDoseScheduled) }
        if daysUntil <= 0 { return SafeStatusSlice(kind: .doseDue, daysUntilNextInjection: daysUntil) }
        return SafeStatusSlice(kind: .nextDoseInDays, daysUntilNextInjection: daysUntil)
    }
}

struct GauravaGlanceSnapshot: Codable, Equatable, Sendable {
    // Envelope
    var schemaVersion: Int
    var producerBuild: String
    var generatedAt: Date
    var expiresAt: Date
    var sourceWatermark: String
    var privacyMode: SurfacePrivacyMode
    var renderPolicyVersion: Int

    // Payload slices (already privacy-shaped by the producer)
    var nextAction: NextActionSlice?
    var progress: ProgressSlice?
    var trend: TrendSlice?
    var status: SafeStatusSlice?

    /// True once the snapshot is past its TTL; surfaces render a refresh state.
    func isExpired(asOf now: Date) -> Bool {
        now >= expiresAt
    }

    /// A cleared snapshot, written immediately after reset/import-reset so a
    /// widget never shows data from a wiped store.
    static func tombstone(producerBuild: String, now: Date, ttl: TimeInterval = GauravaSurface.defaultTTL) -> GauravaGlanceSnapshot {
        GauravaGlanceSnapshot(
            schemaVersion: GauravaSurface.schemaVersion,
            producerBuild: producerBuild,
            generatedAt: now,
            expiresAt: now.addingTimeInterval(ttl),
            sourceWatermark: "tombstone",
            privacyMode: .minimal,
            renderPolicyVersion: 1,
            nextAction: nil,
            progress: nil,
            trend: nil,
            status: SafeStatusSlice(kind: .noDataYet)
        )
    }
}
