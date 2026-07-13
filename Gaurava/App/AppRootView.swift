import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [TrackerProfile]
    @Query private var preferences: [UserPreference]
    @Query private var weights: [WeightEntry]
    @Query private var injections: [InjectionEntry]
    @Query private var dailyLogs: [DailyLog]
    @Query private var dailyLogEntries: [DailyLogEntry]
    @Query private var sideEffects: [SideEffectEntry]
    @Query private var checkIns: [DailyCheckIn]
    @Query private var receipts: [SeedImportReceipt]
    @Query private var treatmentPauses: [TreatmentPause]
    @State private var selectedTab = AppTab.summary
    /// First-run gate. Combined with `hasAnyData` so a fresh install sees the
    /// optional setup screen, while a synced second device, an owner import, and
    /// existing builds 1-4 users all skip it (their data already exists).
    /// `@AppStorage` does not sync via CloudKit, which is why `hasAnyData` is
    /// part of the condition rather than the flag alone.
    @AppStorage(FirstRunFlag.key) private var hasCompletedFirstRun = false
    /// In-app language override (per-device). Empty = follow the system language.
    /// Bound here so changing it gives `content` a new `.id` — the whole tree
    /// rebuilds and every `appLocalized(...)` re-resolves against the chosen
    /// `.lproj` bundle, switching language live without an app restart. The tab
    /// selection survives because it lives on this view, above the `.id`.
    @AppStorage(AppLocalization.storageKey) private var appLanguageCode = ""
    /// In-app theme override (per-device). Empty = the default palette. Folded
    /// into `content`'s `.id` next to the language code so changing it rebuilds
    /// the tree and every `AppTheme.<token>` re-resolves against the chosen
    /// `ThemePalette` — live, no restart. Appearance (System/Light/Dark) stays
    /// orthogonal via `.preferredColorScheme` below.
    @AppStorage(AppThemeSelection.storageKey) private var appThemeID = ""
    /// Set when a `gaurava://jab-confirm` deep link arrives (Live Activity
    /// completion) or `gaurava://add-injection` arrives (widget tile). JabsView
    /// consumes it to present the prefilled Add Injection sheet, then clears it.
    @State private var presentInjectionConfirmation = false
    /// Set when a system surface asks Summary to open one of its quick-action
    /// sheets directly, such as widget Weight or Note tiles.
    @State private var pendingSummaryQuickAction: SummaryQuickAction?
    /// Set when a `gaurava://log-symptom` deep link arrives (the single system
    /// capture entry point). Presents the capture sheet where the user taps the
    /// symptom in-app; nothing is written from the widget.
    @State private var presentLogCapture = false

    private var dashboard: DashboardSnapshot {
        DashboardSnapshot.fromModels(
            profiles: profiles,
            preferences: preferences,
            weights: weights,
            injections: injections,
            dailyLogs: dailyLogs,
            dailyLogEntries: dailyLogEntries,
            sideEffects: sideEffects,
            checkIns: checkIns,
            receipts: receipts,
            pauses: treatmentPauses
        )
    }

    /// Show the optional first-run setup only on a genuinely fresh install:
    /// the flag is unset and no local/synced data exists yet.
    private var showOnboarding: Bool {
        !hasCompletedFirstRun && !dashboard.hasAnyData
    }

    var body: some View {
        content
            .id("\(appLanguageCode)-\(appThemeID)")
            .environment(\.locale, AppLocalization.effectiveLocale)
            .preferredColorScheme(dashboard.preferences.colorScheme)
            .sheet(isPresented: $presentLogCapture) {
                LogCaptureSheet(snapshot: dashboard)
            }
            .onOpenURL { url in
                handle(url)
            }
            .onChange(of: scenePhase) { _, phase in
                // A foreground Open intent (e.g. an "Open Log" control) foregrounds
                // the app and records a pending deep link; consume it on activation.
                if phase == .active {
                    routePendingDeepLink()
                    // Foreground anchored sync: silently pull any new Apple Health
                    // weight readings. Self-gates on the per-device opt-in.
                    Task { @MainActor in await HealthKitWeightSync.syncIfEnabled(context: modelContext) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                // The Open intent's perform() runs in this process and writes the
                // pending route to the App Group; react as soon as it lands so cold
                // and warm launches both route reliably.
                routePendingDeepLink()
            }
            .task {
                // Test hook: drive the same routing code as a real deep link without
                // a live URL (XCUITest cannot run `simctl openurl` from its sandbox).
                if let url = launchDeepLinkURL { handle(url) }
                routePendingDeepLink()
                await OwnerSeedImportLaunchHandler.runIfRequested(context: modelContext)
                #if DEBUG
                // Test-only: seed a specific post-onboarding data state (after the reset
                // above) so the adaptive-states UI suite can exercise Summary/Jabs
                // layouts directly. No-op unless a --gaurava-seed-* argument is present.
                TestStateSeedLaunchHandler.seedIfRequested(context: modelContext)
                #endif
                // Cold launch does not trigger a scenePhase change to .active, so the
                // foreground HealthKit pull is kicked here too (self-gates on opt-in).
                await HealthKitWeightSync.syncIfEnabled(context: modelContext)
            }
    }

    @ViewBuilder
    private var content: some View {
        if showOnboarding {
            FirstRunSetupView()
        } else {
            tabShell
        }
    }

    private var tabShell: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SummaryView(snapshot: dashboard, requestedQuickAction: $pendingSummaryQuickAction)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            LanguageMenuButton()
                        }
                    }
            }
                .tabItem { Label(appLocalized("Summary"), systemImage: AppSymbol.Tab.summary) }
                .accessibilityIdentifier("tab-summary")
                .tag(AppTab.summary)

            NavigationStack { JabsView(snapshot: dashboard, presentAddInjection: $presentInjectionConfirmation) }
                .tabItem { Label(appLocalized("Jabs"), systemImage: AppSymbol.Tab.jabs) }
                .accessibilityIdentifier("tab-jabs")
                .tag(AppTab.jabs)

            NavigationStack { ResultsView(snapshot: dashboard) }
                .tabItem { Label(appLocalized("Trends"), systemImage: AppSymbol.Tab.results) }
                .accessibilityIdentifier("tab-results")
                .tag(AppTab.results)

            NavigationStack { LogView(snapshot: dashboard) }
                .tabItem { Label(appLocalized("Log"), systemImage: AppSymbol.Tab.log) }
                .accessibilityIdentifier("tab-log")
                .tag(AppTab.log)

            NavigationStack { CareView(snapshot: dashboard) }
                .tabItem { Label(appLocalized("Care"), systemImage: AppSymbol.Tab.care) }
                .accessibilityIdentifier("tab-care")
                .tag(AppTab.care)
        }
        .accessibilityIdentifier("mainTabs")
        .tint(AppTheme.primary)
        // Keep the iOS 26 floating tab bar out of reading/chart content. UI tests
        // restore it with a small downward swipe before tapping another tab.
        .tabBarMinimizeBehavior(.onScrollDown)
        // Unified quick-add entry point (issue #13): visible above the tab bar on
        // every tab; the system collapses it inline when the tab bar minimizes.
        .tabViewBottomAccessory {
            QuickAddBar { handle(quickAdd: $0) }
        }
    }

    /// Quick-add bar taps reuse the deep-link routing state, so each action
    /// lands on the tab and sheet the equivalent `gaurava://` link would open.
    private func handle(quickAdd action: QuickAddAction) {
        switch action {
        case .jab:
            selectedTab = .jabs
            presentInjectionConfirmation = true
        case .weight:
            selectedTab = .summary
            pendingSummaryQuickAction = .weight
        case .note:
            selectedTab = .summary
            pendingSummaryQuickAction = .dailyLog
        }
    }

    /// Single routing entry point: select the tab and, for the injection
    /// confirmation link, raise the prefilled Add Injection sheet. Shared by
    /// `.onOpenURL`, the launch argument, and the App Group pending route.
    private func handle(_ url: URL) {
        if let tab = DeepLinkRoute.tab(for: url) { selectedTab = tab }
        switch DeepLinkRoute.presentation(for: url) {
        case .addWeight:
            pendingSummaryQuickAction = .weight
        case .addInjection:
            presentInjectionConfirmation = true
        case .dailyNote:
            pendingSummaryQuickAction = .dailyLog
        case .logSymptom:
            presentLogCapture = true
        case nil:
            break
        }
    }

    /// Consume any pending `gaurava://` deep link queued by a foreground App
    /// Intent and route through the same parser as `.onOpenURL`.
    private func routePendingDeepLink() {
        guard let url = SurfaceNavigation().consumePendingDeepLink() else { return }
        handle(url)
    }

    /// Reads `--gaurava-open-url <gaurava://...>` from the launch arguments.
    private var launchDeepLinkURL: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--gaurava-open-url"),
              flagIndex + 1 < args.count else { return nil }
        return URL(string: args[flagIndex + 1])
    }
}
