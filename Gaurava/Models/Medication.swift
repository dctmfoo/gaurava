import Foundation

enum Medication: String, CaseIterable, Identifiable, Sendable, Codable {
    case tirzepatide
    case semaglutide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tirzepatide:
            return appLocalizedValue("Tirzepatide")
        case .semaglutide:
            return appLocalizedValue("Semaglutide")
        }
    }

    var dosePresets: [Double] {
        switch self {
        case .tirzepatide:
            return [2.5, 5, 7.5, 10, 12.5, 15]
        case .semaglutide:
            return [0.25, 0.5, 1, 1.7, 2, 2.4, 7.2]
        }
    }

    var starterDose: Double {
        dosePresets.first ?? 0
    }

    static func inferred(fromMg dose: Double?) -> Medication {
        guard let dose else { return .tirzepatide }
        return allCases.min { lhs, rhs in
            lhs.distance(fromPresetNearestTo: dose) < rhs.distance(fromPresetNearestTo: dose)
        } ?? .tirzepatide
    }

    func nearestPresetIndex(to dose: Double) -> Int {
        guard let index = dosePresets.indices.min(by: {
            abs(dosePresets[$0] - dose) < abs(dosePresets[$1] - dose)
        }) else {
            return 0
        }
        return index
    }

    private func distance(fromPresetNearestTo dose: Double) -> Double {
        dosePresets.map { abs($0 - dose) }.min() ?? .greatestFiniteMagnitude
    }
}
