//
//  GameCampaignParserTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class GameCampaignParserTests: XCTestCase {

    /// A game entry as the contract's worked example shapes one, including the fields it says are
    /// present but meaningless.
    private static let wheelEntry = """
    {
      "campaignType": 2, "campaignId": 0, "variationId": 0, "dispatchId": null,
      "name": "Spin the Wheel", "priority": 0, "messageType": 2,
      "trigger": { "type": "session_start", "repeatable": true },
      "content": null, "locale": null, "localeCode": null,
      "expiresAt": null, "isTest": false,
      "gameCampaignId": 9645, "gameCampaignType": "wheel"
    }
    """

    private func sync(_ entries: String) -> Data {
        Data("{\"cooldownSeconds\":30,\"messages\":[\(entries)]}".utf8)
    }

    private func campaigns(_ entry: String) -> [InAppMessageCampaign] {
        MessageParser.parseSyncResponse(sync(entry)).campaigns
    }

    func testAGameEntryParsesWithNoContentOfItsOwn() {
        let parsed = campaigns(Self.wheelEntry)

        XCTAssertEqual(parsed.count, 1)
        let widget = parsed.first?.message.widget
        XCTAssertEqual(widget?.gameCampaignId, 9645)
        XCTAssertEqual(widget?.gameCampaignType, "wheel")
        XCTAssertEqual(widget?.openDetail, "details_wheel_9645")
    }

    func testAGameEntryIsIdentifiedByItsGameIdNeverByCampaignIdZero() {
        XCTAssertEqual(campaigns(Self.wheelEntry).first?.key, .game(9645))
    }

    func testAnUnknownCampaignTypeIsSkippedNotCoerced() {
        let entry = Self.wheelEntry.replacingOccurrences(of: "\"campaignType\": 2",
                                                         with: "\"campaignType\": 7")
        XCTAssertTrue(campaigns(entry).isEmpty)
    }

    func testAnUnknownGameCampaignTypeIsSkipped() {
        let entry = Self.wheelEntry.replacingOccurrences(of: "\"gameCampaignType\": \"wheel\"",
                                                         with: "\"gameCampaignType\": \"roulette\"")
        XCTAssertTrue(campaigns(entry).isEmpty)
    }

    func testAGameEntryWithNoGameCampaignIdIsSkipped() {
        let entry = Self.wheelEntry.replacingOccurrences(of: "\"gameCampaignId\": 9645,", with: "")
        XCTAssertTrue(campaigns(entry).isEmpty)
    }

    func testAMessageWithNullContentIsStillDropped() {
        // The exemption is keyed off campaignType, not off the fields being absent, so a
        // malformed message keeps failing for the right reason.
        let entry = Self.wheelEntry
            .replacingOccurrences(of: "\"campaignType\": 2", with: "\"campaignType\": 1")
            .replacingOccurrences(of: "\"campaignId\": 0", with: "\"campaignId\": 2215")
        XCTAssertTrue(campaigns(entry).isEmpty)
    }

    func testAScreenTriggeredGameIsSkipped() {
        let entry = Self.wheelEntry.replacingOccurrences(
            of: "\"trigger\": { \"type\": \"session_start\", \"repeatable\": true }",
            with: "\"trigger\": { \"type\": \"screen\", \"name\": \"cart\", \"repeatable\": true }")
        XCTAssertTrue(campaigns(entry).isEmpty)
    }

    func testAFullscreenGameIsKept() {
        // Fullscreen was found to work once it was measured in a real fullscreen box rather than
        // a short wide one. A portrait screen is well inside the ratio at which the widget clips.
        let entry = Self.wheelEntry.replacingOccurrences(of: "\"messageType\": 2",
                                                         with: "\"messageType\": 3")
        let parsed = campaigns(entry)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.message.type, .fullscreen)
        XCTAssertTrue(parsed.first?.message.isWidget ?? false)
    }

    func testAnOrdinaryMessageStillParsesAlongsideTheFork() {
        let message = """
        {
          "campaignType": 1, "campaignId": 2215, "variationId": 206,
          "dispatchId": "d-1", "name": "Welcome", "priority": 100, "messageType": 2,
          "trigger": { "type": "session_start", "repeatable": false },
          "content": { "colors": { "background": "#FFFFFF" } },
          "locale": { "header": "Welcome back!" },
          "localeCode": "en", "expiresAt": null, "isTest": false
        }
        """
        let parsed = campaigns(message)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertFalse(parsed.first?.message.isWidget ?? true)
        XCTAssertEqual(parsed.first?.message.header, "Welcome back!")
    }

    func testAnEntryWithNoCampaignTypeIsReadAsAMessage() {
        // Older payloads, and anything sent before the field is universal. Defaulting to the kind
        // that has always existed is safe; defaulting to a game would try to open something that
        // is not there.
        let legacy = """
        {
          "campaignId": 2215, "messageType": 2,
          "trigger": { "type": "session_start", "repeatable": false },
          "content": {}, "locale": { "header": "Hello" }, "localeCode": "en"
        }
        """
        let parsed = campaigns(legacy)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertFalse(parsed.first?.message.isWidget ?? true)
    }

    // MARK: - Frequency is the message rules

    private func withTrigger(_ trigger: String) -> String {
        Self.wheelEntry.replacingOccurrences(
            of: "\"trigger\": { \"type\": \"session_start\", \"repeatable\": true }",
            with: "\"trigger\": \(trigger)")
    }

    func testAGameReadsItsRepeatRulesFromTheTriggerAsAMessageDoes() {
        let parsed = campaigns(withTrigger(
            "{ \"type\": \"session_start\", \"repeatable\": true, \"minIntervalSeconds\": 3600 }"))
            .first

        XCTAssertEqual(parsed?.repeatable, true)
        XCTAssertEqual(parsed?.minInterval, 3600)
    }

    /// Null on every game entry today. No game-specific interval stands in for it: a repeatable
    /// game may show on every occurrence, held back only by the account's cooldown and quiet
    /// hours — exactly as a message would be.
    func testAGameWithNoIntervalGetsNoDefaultOfItsOwn() {
        let parsed = campaigns(withTrigger(
            "{ \"type\": \"session_start\", \"repeatable\": true, \"minIntervalSeconds\": null }"))
            .first

        XCTAssertEqual(parsed?.repeatable, true)
        XCTAssertNil(parsed?.minInterval)
    }

    func testANonRepeatableGameIsOnceEver() {
        let parsed = campaigns(withTrigger("{ \"type\": \"session_start\", \"repeatable\": false }"))
            .first
        XCTAssertEqual(parsed?.repeatable, false)
    }
}
