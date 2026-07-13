import Foundation

struct ShareCardSnapshot {
    let displayName: String
    let startWeightKg: Double?
    let currentWeightKg: Double?
    let goalWeightKg: Double?
    let heightCm: Double
    let treatmentStartDate: Date
    let weekCount: Int
    let currentDoseMg: Double?
    let weightPoints: [ShareCardWeightPoint]
    let doseSteps: [ShareCardDoseStep]

    #if !GAURAVA_SURFACE_SNAPSHOT
    init(dashboard: DashboardSnapshot, now: Date = Date(), calendar: Calendar = .current) {
        let orderedWeights = dashboard.weights.sorted { $0.recordedAt < $1.recordedAt }
        let orderedInjections = dashboard.injections.sorted { $0.injectionDate < $1.injectionDate }
        let firstWeight = orderedWeights.first?.weightKg
        let startWeight = dashboard.profile.startingWeightKg > 0 ? dashboard.profile.startingWeightKg : firstWeight
        let currentWeight = orderedWeights.last?.weightKg
        let treatmentStart = dashboard.profile.treatmentStartDate
        let latestEventDate = [
            orderedWeights.last?.recordedAt,
            orderedInjections.last?.injectionDate,
            now
        ]
        .compactMap { $0 }
        .max() ?? now

        displayName = dashboard.profile.displayName
        startWeightKg = startWeight
        currentWeightKg = currentWeight
        goalWeightKg = dashboard.profile.goalWeightKg > 0 ? dashboard.profile.goalWeightKg : nil
        heightCm = dashboard.profile.heightCm
        treatmentStartDate = treatmentStart
        weekCount = max(1, ((calendar.dateComponents([.day], from: treatmentStart, to: latestEventDate).day ?? 0) / 7) + 1)
        currentDoseMg = orderedInjections.last?.doseMg ?? dashboard.profile.plannedDoseMg
        weightPoints = orderedWeights.map { weight in
            ShareCardWeightPoint(
                id: weight.id,
                date: weight.recordedAt,
                weightKg: weight.weightKg,
                doseMg: Self.doseFor(date: weight.recordedAt, injections: orderedInjections)
            )
        }
        doseSteps = Self.makeDoseSteps(
            injections: orderedInjections,
            plannedDoseMg: dashboard.profile.plannedDoseMg,
            treatmentStartDate: treatmentStart
        )
    }
    #endif

    /// Direct seed init (no DashboardSnapshot) for SwiftUI previews and the
    /// marketing share-card snapshot renderer.
    init(displayName: String, startWeightKg: Double?, currentWeightKg: Double?,
         goalWeightKg: Double?, heightCm: Double, treatmentStartDate: Date,
         weekCount: Int, currentDoseMg: Double?,
         weightPoints: [ShareCardWeightPoint], doseSteps: [ShareCardDoseStep]) {
        self.displayName = displayName
        self.startWeightKg = startWeightKg
        self.currentWeightKg = currentWeightKg
        self.goalWeightKg = goalWeightKg
        self.heightCm = heightCm
        self.treatmentStartDate = treatmentStartDate
        self.weekCount = weekCount
        self.currentDoseMg = currentDoseMg
        self.weightPoints = weightPoints
        self.doseSteps = doseSteps
    }

    var hasWeightData: Bool {
        !weightPoints.isEmpty
    }

    var totalLostKg: Double? {
        guard let startWeightKg, let currentWeightKg else { return nil }
        return startWeightKg - currentWeightKg
    }

    var percentLost: Double? {
        guard let totalLostKg, let startWeightKg, startWeightKg > 0 else { return nil }
        return (totalLostKg / startWeightKg) * 100
    }

    var progressToGoal: Double? {
        guard let startWeightKg, let currentWeightKg, let goalWeightKg else { return nil }
        let span = startWeightKg - goalWeightKg
        guard span > 0 else { return nil }
        return min(max((startWeightKg - currentWeightKg) / span, 0), 1)
    }

    var bmi: Double? {
        guard let currentWeightKg, heightCm > 0 else { return nil }
        let meters = heightCm / 100
        return currentWeightKg / (meters * meters)
    }

    var weeklyAverageLossKg: Double? {
        // Average the total change over the exact week count shown on the
        // "Weeks" tile. Dividing by a separate first->last weight-entry span
        // (the old behaviour) meant loss / Weeks did not equal the displayed
        // Weekly rate. weekCount is always >= 1, so this never divides by zero.
        guard let totalLostKg else { return nil }
        return totalLostKg / Double(weekCount)
    }

    var fingerprint: String {
        let latestWeightDate = weightPoints.last?.date.timeIntervalSince1970 ?? 0
        let latestDoseDate = doseSteps.last?.startDate.timeIntervalSince1970 ?? 0
        let current = currentWeightKg ?? 0
        let goal = goalWeightKg ?? 0
        return "\(weightPoints.count)-\(doseSteps.count)-\(latestWeightDate)-\(latestDoseDate)-\(current)-\(goal)"
    }

    // Coupled to DashboardSnapshot / InjectionSnapshot (app + widget targets).
    // The marketing surface-snapshot target sets GAURAVA_SURFACE_SNAPSHOT and
    // seeds via the direct init above, so it compiles without those app types.
    #if !GAURAVA_SURFACE_SNAPSHOT
    private static func doseFor(date: Date, injections: [InjectionSnapshot]) -> Double? {
        if let active = injections.last(where: { $0.injectionDate <= date }) {
            return active.doseMg
        }
        return injections.first?.doseMg
    }

    private static func makeDoseSteps(
        injections: [InjectionSnapshot],
        plannedDoseMg: Double?,
        treatmentStartDate: Date
    ) -> [ShareCardDoseStep] {
        var steps: [ShareCardDoseStep] = []
        var previousDose: Double?

        for injection in injections {
            guard injection.doseMg != previousDose else { continue }
            previousDose = injection.doseMg
            steps.append(ShareCardDoseStep(doseMg: injection.doseMg, startDate: injection.injectionDate))
        }

        if steps.isEmpty, let plannedDoseMg {
            steps.append(ShareCardDoseStep(doseMg: plannedDoseMg, startDate: treatmentStartDate))
        }

        return steps
    }
    #endif
}

struct ShareCardWeightPoint: Identifiable {
    let id: UUID
    let date: Date
    let weightKg: Double
    let doseMg: Double?
}

struct ShareCardDoseStep: Identifiable {
    let doseMg: Double
    let startDate: Date

    var id: String {
        "\(doseMg)-\(startDate.timeIntervalSince1970)"
    }
}

struct ShareCardFormatter {
    let snapshot: ShareCardSnapshot
    let configuration: ShareCardConfiguration

    func weight(_ weightKg: Double?) -> String {
        guard let weightKg else { return appLocalizedValue("--") }
        switch configuration.privacyMode {
        case .exact:
            let converted = configuration.unit.value(fromKilograms: weightKg)
            let value = converted.formatted(.number.precision(.fractionLength(1)))
            return appLocalizedValue("\(value) \(configuration.unit.title)")
        case .percentOnly:
            guard let start = snapshot.startWeightKg, start > 0 else { return appLocalizedValue("--") }
            let value = ((weightKg / start) * 100).formatted(.number.precision(.fractionLength(1)))
            return appLocalizedValue("\(value)%")
        }
    }

    func loss() -> String {
        guard let lost = snapshot.totalLostKg else { return appLocalizedValue("--") }
        switch configuration.privacyMode {
        case .exact:
            let converted = configuration.unit.value(fromKilograms: abs(lost))
            let sign = lost >= 0 ? "-" : "+"
            let value = converted.formatted(.number.precision(.fractionLength(1)))
            return appLocalizedValue("\(sign)\(value) \(configuration.unit.title)")
        case .percentOnly:
            guard let percent = snapshot.percentLost else { return appLocalizedValue("--") }
            let sign = percent >= 0 ? "-" : "+"
            let value = abs(percent).formatted(.number.precision(.fractionLength(1)))
            return appLocalizedValue("\(sign)\(value)%")
        }
    }

    func weeklyAverage() -> String {
        guard let weeklyAverage = snapshot.weeklyAverageLossKg else { return appLocalizedValue("--") }
        switch configuration.privacyMode {
        case .exact:
            let converted = configuration.unit.value(fromKilograms: abs(weeklyAverage))
            let value = converted.formatted(.number.precision(.fractionLength(2)))
            return appLocalizedValue("\(value) \(configuration.unit.title)/wk")
        case .percentOnly:
            guard let start = snapshot.startWeightKg, start > 0 else { return appLocalizedValue("--") }
            let percent = (abs(weeklyAverage) / start) * 100
            let value = percent.formatted(.number.precision(.fractionLength(2)))
            return appLocalizedValue("\(value)%/wk")
        }
    }

    func weeklyAverageSentenceValue() -> String {
        guard let weeklyAverage = snapshot.weeklyAverageLossKg else { return appLocalizedValue("--") }
        switch configuration.privacyMode {
        case .exact:
            let converted = configuration.unit.value(fromKilograms: abs(weeklyAverage))
            let value = converted.formatted(.number.precision(.fractionLength(2)))
            return appLocalizedValue("\(value) \(configuration.unit.title) per week")
        case .percentOnly:
            guard let start = snapshot.startWeightKg, start > 0 else { return appLocalizedValue("--") }
            let percent = (abs(weeklyAverage) / start) * 100
            let value = percent.formatted(.number.precision(.fractionLength(2)))
            return appLocalizedValue("\(value)% per week")
        }
    }

    // How far along the journey is, as a single percent (0-100%). Mode-agnostic
    // because it is a ratio, not a weight.
    func progressToGoalText() -> String {
        guard let progress = snapshot.progressToGoal else { return appLocalizedValue("--") }
        return appLocalizedValue("\(Int((progress * 100).rounded()))%")
    }

    // The goal itself. In exact mode that is the goal weight; in percent mode it
    // is the *target loss* (how much of the starting weight the goal represents
    // losing), e.g. -27.9% -- the way weight-loss/GLP-1 goals are actually
    // stated ("lose X%"), not "72.1% of start remaining".
    func goalTarget() -> String {
        switch configuration.privacyMode {
        case .exact:
            return weight(snapshot.goalWeightKg)
        case .percentOnly:
            guard let start = snapshot.startWeightKg, let goal = snapshot.goalWeightKg, start > 0 else { return appLocalizedValue("--") }
            let targetLossPercent = ((start - goal) / start) * 100
            let sign = targetLossPercent >= 0 ? "-" : "+"
            let value = abs(targetLossPercent).formatted(.number.precision(.fractionLength(1)))
            return appLocalizedValue("\(sign)\(value)%")
        }
    }
}
