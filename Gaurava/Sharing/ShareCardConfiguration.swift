import CoreGraphics
import SwiftUI

struct ShareCardConfiguration: Equatable {
    var template: ShareCardTemplate
    var colorScheme: ShareCardColorScheme
    var privacyMode: ShareCardPrivacyMode
    var dateVisibility: ShareCardDateVisibility
    var unit: ShareCardWeightUnit
}

enum ShareCardTemplate: String, CaseIterable, Identifiable {
    case story
    case milestone
    case dataSheet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: appLocalizedValue("Story")
        case .milestone: appLocalizedValue("Milestone")
        case .dataSheet: appLocalizedValue("Data")
        }
    }

    var subtitle: String {
        switch self {
        case .story: appLocalizedValue("Progress arc")
        case .milestone: appLocalizedValue("One strong moment")
        case .dataSheet: appLocalizedValue("Detailed stats")
        }
    }

    var systemImage: String {
        switch self {
        case .story: "rectangle.portrait.fill"
        case .milestone: "medal.fill"
        case .dataSheet: "tablecells.fill"
        }
    }

    var canvas: ShareCardCanvas {
        .vertical
    }
}

enum ShareCardColorScheme: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: appLocalizedValue("Light")
        case .dark: appLocalizedValue("Dark")
        }
    }

    var swiftUIColorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    static func defaultValue(from theme: String) -> ShareCardColorScheme {
        theme.lowercased() == "dark" ? .dark : .light
    }
}

enum ShareCardPrivacyMode: String, CaseIterable, Identifiable {
    case exact
    case percentOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exact: appLocalizedValue("Exact")
        case .percentOnly: appLocalizedValue("% only")
        }
    }
}

enum ShareCardDateVisibility: String, CaseIterable, Identifiable {
    case show
    case hide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .show: appLocalizedValue("Show")
        case .hide: appLocalizedValue("Hide")
        }
    }
}

enum ShareCardWeightUnit: String, CaseIterable, Identifiable {
    case kg
    case lb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kg: appLocalizedValue("kg")
        case .lb: appLocalizedValue("lb")
        }
    }

    static func defaultValue(from unit: String) -> ShareCardWeightUnit {
        unit.lowercased().hasPrefix("lb") ? .lb : .kg
    }

    func value(fromKilograms weightKg: Double) -> Double {
        switch self {
        case .kg:
            return weightKg
        case .lb:
            return weightKg * 2.204_622_621_85
        }
    }
}

struct ShareCardCanvas: Equatable {
    let points: CGSize
    let pixels: CGSize
    let scale: CGFloat

    static let square = ShareCardCanvas(
        points: CGSize(width: 360, height: 360),
        pixels: CGSize(width: 1080, height: 1080),
        scale: 3
    )

    static let portrait = ShareCardCanvas(
        points: CGSize(width: 360, height: 450),
        pixels: CGSize(width: 1080, height: 1350),
        scale: 3
    )

    static let vertical = ShareCardCanvas(
        points: CGSize(width: 360, height: 640),
        pixels: CGSize(width: 1080, height: 1920),
        scale: 3
    )

    static let story = ShareCardCanvas.vertical
}
