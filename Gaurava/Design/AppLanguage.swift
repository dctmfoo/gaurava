import SwiftUI

/// A language Gaurava can switch to, identified by its String Catalog / `.lproj`
/// code. The set is DERIVED from what's compiled into the app (`AppLanguage.all`),
/// so adding a language to `Localizable.xcstrings` makes it appear in the picker
/// with no Swift change here — see the "Localization" section in CLAUDE.md.
struct AppLanguage: Identifiable, Hashable {
    let code: String
    var id: String { code }

    /// The language's own name in its own script (endonym), e.g. "हिन्दी". Shown
    /// in the picker so a user who cannot read the current UI can still find
    /// their language.
    var endonym: String {
        Locale(identifier: code)
            .localizedString(forIdentifier: code)?
            .localizedCapitalized
            ?? code
    }

    /// Every language bundled into the app, derived from the String Catalog's
    /// compiled `.lproj`s. Source language first, then the rest by endonym.
    static let all: [AppLanguage] = {
        let source = Bundle.main.developmentLocalization ?? "en"
        return Bundle.main.localizations
            .filter { $0 != "Base" }
            .map(AppLanguage.init(code:))
            .sorted { lhs, rhs in
                if lhs.code == source { return true }
                if rhs.code == source { return false }
                return lhs.endonym.localizedCompare(rhs.endonym) == .orderedAscending
            }
    }()

    /// Codes we can switch to — used to validate a stored choice.
    static let supportedCodes: Set<String> = Set(all.map(\.code))
}

/// Process-wide in-app language selection. The choice is a per-device override
/// (mirroring iOS's own per-app language) that overrides the system language for
/// in-app text without leaving the app or restarting it.
///
/// Reads are synchronous so the free `appLocalized(_:)` helper can resolve
/// strings against the chosen language's `.lproj` bundle on the spot. When no
/// choice has been made (`storedCode` empty) everything resolves against the
/// main bundle exactly as before — zero behaviour change for users who never
/// touch the setting.
enum AppLocalization {
    /// UserDefaults / `@AppStorage` key holding the chosen language code, or "" to follow the system.
    static let storageKey = "appLanguageCode"

    /// The explicitly chosen code, or "" when following the system.
    static var storedCode: String {
        UserDefaults.standard.string(forKey: storageKey) ?? ""
    }

    /// The language actually in effect: the explicit choice, else the system's
    /// best match against what we ship, else English. Drives the picker's
    /// checkmark and the Care row's displayed value.
    static var effectiveCode: String {
        let stored = storedCode
        if !stored.isEmpty, AppLanguage.supportedCodes.contains(stored) { return stored }
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        if AppLanguage.supportedCodes.contains(preferred) { return preferred }
        return AppLanguage.supportedCodes.contains("en") ? "en" : (AppLanguage.all.first?.code ?? "en")
    }

    /// Locale injected into the SwiftUI environment so dates/numbers and any
    /// `Text(LocalizedStringKey)` literals follow the chosen language too.
    static var effectiveLocale: Locale { Locale(identifier: effectiveCode) }

    /// A calendar whose symbols (weekday/month names) follow the IN-APP picker.
    /// `Calendar.current` resolves its symbols against the SYSTEM locale
    /// (`Locale.current`, derived from `AppleLanguages`), so a standalone
    /// `Calendar.current.weekdaySymbols[…]` lookup stays in the system language
    /// and lags the picker — the same boundary `Date.appFormatted` fixes for
    /// formatted dates (see CLAUDE.md → Localization → Known boundaries). Pin
    /// `effectiveLocale` so weekday names switch with everything else.
    static var effectiveCalendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = effectiveLocale
        return calendar
    }

    /// One immutable `.lproj` bundle per shipped language, built once. A lazy
    /// `static let` is concurrency-safe (immutable after init) — no mutable
    /// static cache to reason about.
    private static let bundles: [String: Bundle] = {
        var map: [String: Bundle] = [:]
        for language in AppLanguage.all {
            if let path = Bundle.main.path(forResource: language.code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                map[language.code] = bundle
            }
        }
        return map
    }()

    static func bundle(for code: String) -> Bundle { bundles[code] ?? .main }

    /// The bundle `appLocalized(_:)` resolves against for the current selection.
    /// Empty selection → the main bundle (system behaviour preserved).
    static var currentBundle: Bundle {
        let stored = storedCode
        return stored.isEmpty ? .main : bundle(for: stored)
    }

    /// Mirror the choice into `AppleLanguages` as well. This keeps the per-app
    /// entry in iOS Settings in sync and makes any string path NOT routed through
    /// `appLocalized` (raw `String(localized:)` interpolations, the app name,
    /// notifications) resolve in the chosen language on the next launch.
    static func syncSystemLanguage(_ code: String) {
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }
}

/// Interpolation/literal companion to `appLocalized(_:)` for raw
/// `String(localized: "…")` call sites. `String(localized:)` already takes a
/// `String.LocalizationValue`, so this is a drop-in that additionally resolves
/// against the chosen language's bundle — number/date/phrase strings switch with
/// everything else.
func appLocalizedValue(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: AppLocalization.currentBundle)
}

/// Companion for `String(localized: .catalogKey)` resource call sites (the
/// generated String Catalog symbols). Pins the resource to the chosen language
/// before resolving.
func appLocalizedResource(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    // `bundle` is get-only; `locale` is settable and — per the LocalizedStringResource
    // docs — drives which language the deferred lookup resolves. The main bundle
    // already carries every shipped translation, so locale alone selects them.
    resource.locale = AppLocalization.effectiveLocale
    return String(localized: resource)
}

extension Date {
    /// Format a date in the IN-APP chosen language. A bare `Date.formatted(...)`
    /// builds its `String` using the SYSTEM locale (`Locale.autoupdatingCurrent`,
    /// derived from `AppleLanguages`) at the call site — that lags the in-app
    /// picker (it only updates on relaunch) and is NOT affected by the SwiftUI
    /// `.environment(\.locale)`, because the string is produced before `Text` sees
    /// it. Pinning `effectiveLocale` makes month/weekday names follow the picker.
    /// This is the "Known boundaries → system-formatted dates" item in CLAUDE.md;
    /// every user-facing date must format through here, not raw `.formatted`.
    func appFormatted(_ style: Date.FormatStyle) -> String {
        formatted(style.locale(AppLocalization.effectiveLocale))
    }
}

/// The list of languages shown inside a `Menu`, as an inline checklist. Writing
/// the selection updates `@AppStorage` (which drives the root `.id` rebuild) and
/// mirrors it into `AppleLanguages`.
struct LanguagePicker: View {
    @AppStorage(AppLocalization.storageKey) private var code: String = ""

    var body: some View {
        Picker(
            selection: Binding(
                get: { AppLocalization.effectiveCode },
                set: { newCode in
                    code = newCode
                    AppLocalization.syncSystemLanguage(newCode)
                }
            )
        ) {
            ForEach(AppLanguage.all) { language in
                Text(language.endonym).tag(language.code)
            }
        } label: {
            Text(appLocalized("Language"))
        }
        .pickerStyle(.inline)
    }
}

/// Top-right globe in the Summary toolbar: one tap opens the language list.
struct LanguageMenuButton: View {
    var body: some View {
        Menu {
            LanguagePicker()
        } label: {
            Image(systemName: "globe")
        }
        .accessibilityIdentifier("language-menu")
        .accessibilityLabel(Text(appLocalized("Language")))
    }
}
