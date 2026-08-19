import XCTest
@testable import Gameball

final class GameballTests: XCTestCase {
    func testSDKVersionIsSet() {
        XCTAssertFalse(SDKInfo.version.isEmpty)
    }
}
