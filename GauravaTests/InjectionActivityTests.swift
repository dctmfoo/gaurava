import XCTest
@testable import Gaurava

// Build 4 coverage: the injection-day Live Activity projection (the pure
// start/update/end eligibility + privacy + window state machine), the tiny
// ContentState codec, and the completion deep-link parsing.
//
// The projection derives everything from primitives + TreatmentMath — it reads
// no SwiftData and creates no InjectionEntry. These tests lock the eligibility
// rules, the "cannot remain stale past the due window" guarantee, producer-side
// privacy redaction, and that the completion link is a pure Jabs route.
final class InjectionActivityTests: XCTestCase {
    private let calendar = Calendar.current

    private func at(_ daysAgo: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: now)!
    }

    private func input(
        optedIn: Bool = true,
        privacy: SurfacePrivacyMode = .full,
        lastInjectionDate: Date?,
        lastSite: String? = "Abdomen - Left",
        plannedDose: Double? = 5,
        windowHours: Int = 24
    ) -> InjectionActivityInput {
        InjectionActivityInput(
            optedIn: optedIn,
            privacyMode: privacy,
            lastInjectionDate: lastInjectionDate,
            lastInjectionSite: lastSite,
            plannedDoseMg: plannedDose,
            lastDoseMg: 2.5,
            preferredSites: InjectionSiteRotation.allSites,
            windowHours: windowHours
        )
    }

    // MARK: - Eligibility

    func testOptedOutIsInactive() {
        let now = Date()
        let decision = InjectionActivityProjection.decide(
            input: input(optedIn: false, lastInjectionDate: at(7, from: now)),
            now: now
        )
        XCTAssertEqual(decision, .inactive)
    }

    func testNoInjectionsIsInactive() {
        let now = Date()
        XCTAssertEqual(
            InjectionActivityProjection.decide(input: input(lastInjectionDate: nil), now: now),
            .inactive
        )
    }

    func testDueTodayProducesActiveState() {
        let now = Date()
        // Last injection exactly 7 days ago -> next dose is due today.
        let decision = InjectionActivityProjection.decide(
            input: input(lastInjectionDate: at(7, from: now)),
            now: now
        )
        guard case .active(let state) = decision else {
            return XCTFail("Expected active, got \(decision)")
        }
        XCTAssertFalse(state.isCompleted)
        XCTAssertEqual(state.statusKind, .some(.dueToday))
        XCTAssertEqual(state.localizedStatusPhrase, "Dose due today")
        XCTAssertNil(state.statusPhrase)
        XCTAssertEqual(state.doseMg, 5)
        // Suggested site rotates past the last site.
        XCTAssertEqual(state.suggestedSite, "Abdomen - Right")
        // Window closes 24h after the start of the due day.
        let expectedWindow = calendar.date(byAdding: .hour, value: 24, to: calendar.startOfDay(for: now))
        XCTAssertEqual(state.windowEnd, expectedWindow)
    }

    func testLoggedTodayProducesCompleted() {
        let now = Date()
        let decision = InjectionActivityProjection.decide(
            input: input(lastInjectionDate: now),
            now: now
        )
        guard case .completed(let state) = decision else {
            return XCTFail("Expected completed, got \(decision)")
        }
        XCTAssertTrue(state.isCompleted)
        XCTAssertEqual(state.statusKind, .some(.logged))
        XCTAssertEqual(state.localizedStatusPhrase, "Dose logged")
        XCTAssertNil(state.statusPhrase)
    }

    func testPastDueWindowIsInactive() {
        let now = Date()
        // Last injection 8 days ago -> next dose was due yesterday; with a 24h
        // window the activity must not remain (cannot stay stale past the window).
        XCTAssertEqual(
            InjectionActivityProjection.decide(input: input(lastInjectionDate: at(8, from: now)), now: now),
            .inactive
        )
    }

    func testOverdueWithinExtendedWindowIsActive() {
        let now = Date()
        // Due yesterday, but a wider window keeps it briefly active and overdue.
        let decision = InjectionActivityProjection.decide(
            input: input(lastInjectionDate: at(8, from: now), windowHours: 72),
            now: now
        )
        guard case .active(let state) = decision else {
            return XCTFail("Expected active, got \(decision)")
        }
        XCTAssertEqual(state.statusKind, .some(.overdue))
        XCTAssertEqual(state.localizedStatusPhrase, "Dose overdue")
        XCTAssertNil(state.statusPhrase)
    }

    // MARK: - Privacy (producer-side redaction)

    func testRedactedHidesDoseAndSite() {
        let now = Date()
        let decision = InjectionActivityProjection.decide(
            input: input(privacy: .redacted, lastInjectionDate: at(7, from: now)),
            now: now
        )
        guard case .active(let state) = decision else {
            return XCTFail("Expected active, got \(decision)")
        }
        XCTAssertNil(state.doseMg, "Redacted mode must omit the dose")
        XCTAssertNil(state.suggestedSite, "Redacted mode must omit the site")
        XCTAssertEqual(state.statusKind, .some(.dueToday), "The safe semantic status still shows")
    }

    func testMinimalKeepsScheduleDetail() {
        let now = Date()
        let decision = InjectionActivityProjection.decide(
            input: input(privacy: .minimal, lastInjectionDate: at(7, from: now)),
            now: now
        )
        guard case .active(let state) = decision else {
            return XCTFail("Expected active, got \(decision)")
        }
        // Minimal mirrors the glance: schedule detail (dose/site) stays visible.
        XCTAssertEqual(state.doseMg, 5)
        XCTAssertEqual(state.suggestedSite, "Abdomen - Right")
    }

    // MARK: - Codec (must stay tiny; ActivityKit caps ContentState at 4KB)

    func testContentStateCodableRoundTripsAndStaysSmall() throws {
        let now = Date()
        let state = GauravaInjectionActivityAttributes.ContentState(
            dueDate: now,
            windowEnd: now.addingTimeInterval(86_400),
            statusKind: .dueToday,
            statusPhrase: nil,
            doseMg: 7.5,
            suggestedSite: "Thigh - Left",
            isCompleted: false
        )
        let data = try JSONEncoder().encode(state)
        XCTAssertLessThan(data.count, 4096, "ContentState must stay well under ActivityKit's 4KB limit")
        let decoded = try JSONDecoder().decode(GauravaInjectionActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testLegacyContentStateDecodesPhraseFallback() throws {
        let json = """
        {"dueDate":0,"windowEnd":86400,"statusPhrase":"Dose due today","isCompleted":false}
        """
        let decoded = try JSONDecoder().decode(
            GauravaInjectionActivityAttributes.ContentState.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(decoded.statusKind)
        XCTAssertEqual(decoded.localizedStatusPhrase, "Dose due today")
    }

    // MARK: - Completion deep link (pure route, no clinical write)

    func testInjectionConfirmationLinkRoutesToJabs() {
        let url = GauravaScreen.jabConfirm.url
        XCTAssertEqual(url, URL(string: "gaurava://jab-confirm"))
        XCTAssertTrue(DeepLinkRoute.isInjectionConfirmation(url))
        XCTAssertTrue(DeepLinkRoute.isAddInjectionRequest(url))
        XCTAssertEqual(DeepLinkRoute.tab(for: url), .jabs)
        XCTAssertEqual(DeepLinkRoute.presentation(for: url), .addInjection)
        XCTAssertTrue(DeepLinkRoute.isAddInjectionRequest(GauravaScreen.addInjection.url))
        // A plain Jabs link is not a confirmation request.
        XCTAssertFalse(DeepLinkRoute.isInjectionConfirmation(GauravaScreen.jabs.url))
    }
}
