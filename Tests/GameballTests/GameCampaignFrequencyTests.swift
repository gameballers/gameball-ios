//
//  GameCampaignFrequencyTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// A game is held to exactly the frequency rules a message is — `repeatable` and
/// `minIntervalSeconds` from its trigger, the account's cooldown and quiet hours — and to nothing
/// of its own.
final class GameCampaignFrequencyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Selects for a session start. The floor runs from the newest `history` entry unless
    /// `lastDisplayAt` says otherwise.
    private func select(_ campaigns: [InAppMessageCampaign],
                        history: [CampaignKey: Date] = [:],
                        lastDisplayAt: Date? = nil,
                        cooldown: TimeInterval = 0,
                        quietHours: QuietHours? = nil,
                        at time: Date? = nil) -> InAppMessageCampaign? {
        let state = CapState(lastDisplayAt: lastDisplayAt ?? history.values.max(),
                             lastDisplayByCampaign: history)
        return selectCampaign(occurrence: .sessionStart,
                              campaigns: campaigns,
                              capState: state,
                              now: time ?? now,
                              cooldown: cooldown,
                              quietHours: quietHours,
                              isArtworkReady: artworkAlwaysReady)
    }

    /// Quiet hours are judged on the device's own clock, so the instant is named in local time.
    private func local(_ hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2023; components.month = 11; components.day = 14
        components.hour = hour
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: components)!
    }

    func testANonRepeatableGameShowsOnceEver() {
        let game = makeGameCampaign(repeatable: false)

        XCTAssertNotNil(select([game]))
        XCTAssertNil(select([game], history: [.game(9645): now.addingTimeInterval(-86_400)]),
                     "a once-ever game showed twice")
    }

    func testARepeatableGameWaitsOutItsInterval() {
        let game = makeGameCampaign(repeatable: true, minInterval: 3600)
        let history: [CampaignKey: Date] = [.game(9645): now.addingTimeInterval(-600)]

        XCTAssertNil(select([game], history: history), "shown again inside its interval")
        XCTAssertNotNil(select([game], history: history, at: now.addingTimeInterval(3000)))
    }

    func testARepeatableGameWithNoIntervalShowsOnEveryOccurrence() {
        let game = makeGameCampaign(repeatable: true, minInterval: nil)
        XCTAssertNotNil(select([game], history: [.game(9645): now.addingTimeInterval(-1)]))
    }

    /// Every game carries campaignId 0; the history is keyed by game, so one game having shown
    /// says nothing about another.
    func testOneGamesHistoryDoesNotHoldBackAnother() {
        let quiz = makeGameCampaign(gameCampaignId: 9702, repeatable: false)
        XCTAssertNotNil(select([quiz], history: [.game(9645): now.addingTimeInterval(-60)]))
    }

    func testTheAccountCooldownHoldsAGameAsItHoldsAMessage() {
        for campaign in [makeGameCampaign(), makeCampaign(campaignId: 2215)] {
            XCTAssertNil(select([campaign], lastDisplayAt: now.addingTimeInterval(-10),
                                cooldown: 30),
                         "\(campaign.key) showed inside the cooldown")
            XCTAssertNotNil(select([campaign], lastDisplayAt: now.addingTimeInterval(-31),
                                   cooldown: 30))
        }
    }

    func testQuietHoursHoldAGameAsTheyHoldAMessage() {
        let quiet = QuietHours(json: ["enabled": true, "start": "22:00", "end": "08:00"])
        for campaign in [makeGameCampaign(), makeCampaign(campaignId: 2215)] {
            XCTAssertNil(select([campaign], quietHours: quiet, at: local(23)),
                         "\(campaign.key) showed inside quiet hours")
            XCTAssertNotNil(select([campaign], quietHours: quiet, at: local(12)))
        }
    }
}
