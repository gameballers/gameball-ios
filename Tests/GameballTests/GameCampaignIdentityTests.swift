//
//  GameCampaignIdentityTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// A session-start game campaign. `campaignId` is 0 exactly as a real game entry arrives; its
/// identity comes from `gameCampaignId`.
func makeGameCampaign(gameCampaignId: Int = 9645,
                      type: GameballMessageType = .modal) -> InAppMessageCampaign {
    return makeCampaign(
        campaignId: 0,
        type: type,
        message: makeMessage(widget: GameballWidgetContent(gameCampaignId: gameCampaignId,
                                                          gameCampaignType: "wheel"),
                             id: "game_\(gameCampaignId)",
                             type: type,
                             header: nil,
                             body: nil))
}

final class GameCampaignIdentityTests: XCTestCase {

    func testAGameIsKeyedByItsGameIdNotByCampaignIdZero() {
        XCTAssertEqual(makeGameCampaign().key, .game(9645))
    }

    func testTwoGamesDoNotShareOneKey() {
        // Both arrive with campaignId 0. Keyed on that, showing one would mark the other shown.
        XCTAssertNotEqual(makeGameCampaign(gameCampaignId: 9645).key,
                          makeGameCampaign(gameCampaignId: 9702).key)
    }

    func testAMessageKeepsItsCampaignId() {
        XCTAssertEqual(makeCampaign(campaignId: 2215).key, .message(2215))
    }

    func testAGameAndAMessageOfTheSameNumberDoNotCollide() {
        XCTAssertNotEqual(makeGameCampaign(gameCampaignId: 2215).key,
                          makeCampaign(campaignId: 2215).key)
    }

    func testTheOpenDetailCarriesTypeAndId() {
        XCTAssertEqual(makeGameCampaign().message.widget?.openDetail, "details_wheel_9645")
    }

    func testAGameIsAWidgetMessageAndAnOrdinaryOneIsNot() {
        XCTAssertTrue(makeGameCampaign().message.isWidget)
        XCTAssertFalse(makeCampaign().message.isWidget)
    }
}
