import Foundation

// Pure, dependency-free injection-site rotation rules.
// Kept import-clean (Foundation only) so the glance-surface projection can
// reuse it without pulling in SwiftData or SwiftUI. See Build 0 in
// docs/widget-options-deep-dive.html.
enum InjectionSiteRotation {
    static let allSites = [
        "Abdomen - Left",
        "Abdomen - Right",
        "Thigh - Left",
        "Thigh - Right",
        "Upper Arm - Left",
        "Upper Arm - Right"
    ]

    static func localizedDisplayName(for rawSite: String) -> String {
        switch rawSite {
        case "Abdomen - Left": return appLocalizedResource(.injectionSiteAbdomenLeft)
        case "Abdomen - Right": return appLocalizedResource(.injectionSiteAbdomenRight)
        case "Thigh - Left": return appLocalizedResource(.injectionSiteThighLeft)
        case "Thigh - Right": return appLocalizedResource(.injectionSiteThighRight)
        case "Upper Arm - Left": return appLocalizedResource(.injectionSiteUpperArmLeft)
        case "Upper Arm - Right": return appLocalizedResource(.injectionSiteUpperArmRight)
        default: return rawSite
        }
    }

    static func preferredSites(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return allSites
        }
        return normalizedPreferredSites(decoded)
    }

    static func encodedPreferredSites(_ sites: [String]) -> String {
        let normalized = normalizedPreferredSites(sites)
        guard let data = try? JSONEncoder().encode(normalized),
              let value = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return value
    }

    static func normalizedPreferredSites(_ sites: [String]) -> [String] {
        let selected = Set(sites)
        let ordered = allSites.filter { selected.contains($0) }
        return ordered.isEmpty ? allSites : ordered
    }

    static func siteOptions(preferredSites: [String], including currentSite: String? = nil) -> [String] {
        var options = normalizedPreferredSites(preferredSites)
        if let currentSite,
           allSites.contains(currentSite),
           !options.contains(currentSite) {
            options.append(currentSite)
        }
        return options
    }

    /// Form default: the site to preselect in the Add Injection picker. Always
    /// returns a concrete site (the next in rotation, or the first when there is
    /// no history) because a form control needs a selected value. This is a UI
    /// default, not a clinical claim about where to inject.
    static func suggestedSite(after lastSite: String?, preferredSites: [String]) -> String {
        let sites = normalizedPreferredSites(preferredSites)
        guard let lastSite,
              let index = sites.firstIndex(of: lastSite)
        else {
            return sites.first ?? "Site not set"
        }
        return sites[(index + 1) % sites.count]
    }

    /// Display value: the next site to surface in the UI as a suggestion. Returns
    /// nil when there is no injection history, so a brand-new user is never told
    /// "inject here" before any injection exists. Distinct from `suggestedSite`,
    /// which must always yield a form default.
    static func displaySite(after lastSite: String?, preferredSites: [String]) -> String? {
        guard lastSite != nil else { return nil }
        return suggestedSite(after: lastSite, preferredSites: preferredSites)
    }
}
