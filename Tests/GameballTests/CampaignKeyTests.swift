//
//  CampaignKeyTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class CampaignKeyTests: XCTestCase {

    func testAMessageAndAGameWithTheSameNumberAreDifferentKeys() {
        // The contract warns these sequences overlap. Keying on the bare number would make one
        // campaign's history suppress the other's.
        XCTAssertNotEqual(CampaignKey.message(9645), CampaignKey.game(9645))
    }

    func testEqualKeysCollapseInADictionary() {
        var seen: [CampaignKey: Int] = [:]
        seen[.game(9645)] = 1
        seen[.game(9645)] = 2

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen[.game(9645)], 2)
    }

    func testRoundTripsThroughItsStorageForm() {
        for key in [CampaignKey.message(2215), CampaignKey.game(9645)] {
            XCTAssertEqual(CampaignKey.parse(key.storageKey), key)
        }
    }

    func testABareNumberParsesAsAMessage() {
        // Every history written before this change looks like this.
        XCTAssertEqual(CampaignKey.parse("2215"), .message(2215))
    }

    func testUnparseableInputIsNilRatherThanAWrongKey() {
        for bad in ["", "game:", "game:abc", "other:1", ":1"] {
            XCTAssertNil(CampaignKey.parse(bad), "expected nil for \(bad)")
        }
    }

    /// A log line names the kind as well as the id. A game's campaignId is always 0, so "campaign
    /// 0" named every game at once.
    func testALogLineNamesTheKindAndTheId() {
        XCTAssertEqual("\(CampaignKey.game(9645))", "game 9645")
        XCTAssertEqual("\(CampaignKey.message(2215))", "message 2215")
    }
}
