import XCTest
@testable import Gameball

final class GameballTests: XCTestCase {
    func testSDKVersionIsSet() {
        XCTAssertFalse(SDKInfo.version.isEmpty)
    }

    func testConfigKeepsTheAppGroup() {
        XCTAssertEqual(GameballConfig(apiKey: "k", lang: "en", appGroup: "group.x").appGroup, "group.x")
        XCTAssertNil(GameballConfig(apiKey: "k", lang: "en").appGroup)
    }
}
