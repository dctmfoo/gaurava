import XCTest
@testable import Gaurava

// Build 2: gaurava:// deep-link parsing -> tab selection. Pure, no UI.
final class DeepLinkRouteTests: XCTestCase {
    private func tab(_ string: String) -> AppTab? {
        guard let url = URL(string: string) else { return nil }
        return DeepLinkRoute.tab(for: url)
    }

    func testHostFormResolvesEveryTab() {
        XCTAssertEqual(tab("gaurava://summary"), .summary)
        XCTAssertEqual(tab("gaurava://jabs"), .jabs)
        XCTAssertEqual(tab("gaurava://results"), .results)
        XCTAssertEqual(tab("gaurava://log"), .log)
        XCTAssertEqual(tab("gaurava://care"), .care)
    }

    func testCaseInsensitiveSchemeAndHost() {
        XCTAssertEqual(tab("GAURAVA://JABS"), .jabs)
        XCTAssertEqual(tab("Gaurava://Results"), .results)
    }

    func testPathFormResolves() {
        // gaurava:///log -> empty host, "log" as first path component.
        XCTAssertEqual(tab("gaurava:///log"), .log)
    }

    func testUnknownHostIsNil() {
        XCTAssertNil(tab("gaurava://nope"))
        XCTAssertNil(tab("gaurava://"))
    }

    func testWrongSchemeIsNil() {
        XCTAssertNil(tab("https://jabs"))
        XCTAssertNil(tab("mounjaro://jabs"))
    }
}
