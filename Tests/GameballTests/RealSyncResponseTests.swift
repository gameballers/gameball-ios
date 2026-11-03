//
//  RealSyncResponseTests.swift
//  GameballTests
//
//  Parses a payload captured from the live v4.0 sync endpoint. Reading the documentation
//  is not a substitute for parsing what the backend actually sent: every hand-built
//  fixture in MessageParserTests encodes what we *believe* the wire looks like, and this
//  is the only test that fails when that belief is wrong.
//

import XCTest
@testable import Gameball

final class RealSyncResponseTests: XCTestCase {

    private func parsed() -> SyncResult {
        return MessageParser.parseSyncResponse(IAMFixture.data("v4-sync-response"))
    }

    /// The 2026-08-24 capture, taken from moaty-survey-2. Kept alongside the older one rather
    /// than replacing it: the two payloads differ in ways worth keeping under test, and this is
    /// the one that carries a quiet window and a priority tie.
    private func parsedAugust() -> SyncResult {
        return MessageParser.parseSyncResponse(IAMFixture.data("v4-sync-quiet-hours"))
    }

    func testLivePayloadYieldsCampaigns() {
        let result = parsed()
        XCTAssertFalse(result.campaigns.isEmpty, "the captured payload must produce campaigns")
        // Every campaign in the capture is renderable, so a drop here is a regression
        // rather than a property of the data.
        XCTAssertEqual(result.campaigns.count, 8)
        XCTAssertEqual(result.cooldown, 30)
        XCTAssertNotNil(result.rawPayload)
    }

    func testEveryCampaignHasAnIdentity() {
        for campaign in parsed().campaigns {
            XCTAssertNotEqual(campaign.campaignId, 0)
            XCTAssertFalse(campaign.message.id.isEmpty)
        }
    }

    /// The capture contains only message types 1, 2 and 3, so any `.unsupported` here
    /// means the type mapping broke rather than that the backend sent something new.
    func testNoCampaignIsUnsupported() {
        for campaign in parsed().campaigns {
            XCTAssertNotEqual(campaign.message.type, .unsupported,
                              "campaign \(campaign.campaignId) parsed as unsupported")
        }
    }

    func testEveryCampaignHasSomethingToRender() {
        for campaign in parsed().campaigns {
            let hasText = campaign.message.header != nil || campaign.message.body != nil
            XCTAssertTrue(hasText || campaign.message.imageURL != nil,
                          "campaign \(campaign.campaignId) has nothing to render")
        }
    }

    /// Spot-checks the one rule most likely to be inverted, against real data: this
    /// campaign carries artwork in `media` and none in `imageUrl`, and is a fullscreen.
    func testFullscreenCampaignResolvesMediaArtwork() {
        guard let campaign = parsed().campaigns.first(where: { $0.campaignId == 2055 }) else {
            return XCTFail("campaign 2055 is missing from the capture")
        }
        XCTAssertEqual(campaign.message.type, .fullscreen)
        XCTAssertEqual(campaign.message.imageURL?.absoluteString,
                       "https://i.ibb.co/G34R4MtM/83312799-summer-sale.jpg")
        XCTAssertEqual(campaign.priority, 7)
        XCTAssertEqual(campaign.variationId, 20)
        XCTAssertEqual(campaign.message.id, "2055/20")
        XCTAssertTrue(campaign.repeatable)
        XCTAssertEqual(campaign.minInterval, 300)

        // Its trigger is an event, matched on name rather than the eventId also present.
        guard case .event(let name, let filters) = campaign.trigger else {
            return XCTFail("expected an event trigger")
        }
        XCTAssertEqual(name, "place_order")
        XCTAssertTrue(filters.isEmpty)

        // Buttons pair across the two halves of the payload.
        XCTAssertEqual(campaign.message.buttons.count, 1)
        XCTAssertEqual(campaign.message.buttons.first?.id, "ok")
        XCTAssertEqual(campaign.message.buttons.first?.text, "Track my order")
        if case .some(.navigate(let route, _)) = campaign.message.buttons.first?.action {
            XCTAssertEqual(route, "orders")
        } else {
            XCTFail("expected the paired button to navigate")
        }

        // closeBehaviour is "button" only, so scrim tap must be off.
        XCTAssertTrue(campaign.message.showCloseButton)
        XCTAssertFalse(campaign.message.dismissOnScrimTap)
    }

    /// The slideup in the capture has a null `closeBehaviour` sibling elsewhere in the
    /// payload, so this pins the "swipe" branch and the auto-dismiss read.
    func testSlideupCampaignParsesItsBehaviour() {
        guard let campaign = parsed().campaigns.first(where: { $0.campaignId == 2054 }) else {
            return XCTFail("campaign 2054 is missing from the capture")
        }
        XCTAssertEqual(campaign.message.type, .slideup)
        XCTAssertEqual(campaign.message.slidePosition, .bottom)
        XCTAssertEqual(campaign.message.autoDismissAfter, 8)
        XCTAssertFalse(campaign.message.showCloseButton)
        XCTAssertTrue(campaign.message.dismissOnScrimTap)
        // minIntervalSeconds is 0 in the capture, which means every occurrence.
        XCTAssertTrue(campaign.repeatable)
        XCTAssertNil(campaign.minInterval)
        XCTAssertNil(campaign.message.header)
        XCTAssertNotNil(campaign.message.body)
    }

    /// A null `closeBehaviour` must still leave every campaign closable, or these ship with no
    /// way out. The rule is per type, which is what this originally missed: it asserted a close
    /// button on 2042, a *slideup*, which has never rendered one.
    ///
    /// Slideup: the swipe (unconditional, added by the view) and the default timer.
    /// Modal and fullscreen: the close button.
    func testCampaignsWithNullCloseBehaviourAreClosable() {
        let ids = [2042, 2058, 2059, 2060, 2061]
        let campaigns = parsed().campaigns.filter { ids.contains($0.campaignId) }
        XCTAssertEqual(campaigns.count, ids.count)
        for campaign in campaigns {
            let message = campaign.message
            switch message.type {
            case .slideup:
                XCTAssertNotNil(message.autoDismissAfter,
                                "slideup \(campaign.campaignId) would stay up all session")
                XCTAssertFalse(message.showCloseButton,
                               "slideup \(campaign.campaignId) must not claim a close button")
            default:
                XCTAssertTrue(message.showCloseButton,
                              "campaign \(campaign.campaignId) has no close affordance")
            }
            XCTAssertTrue(message.dismissOnScrimTap,
                          "campaign \(campaign.campaignId) cannot be dismissed by scrim")
        }
    }

    func testSessionStartTriggersParse() {
        let sessionStart = parsed().campaigns.filter {
            if case .sessionStart = $0.trigger { return true }
            return false
        }
        // Six of the eight campaigns in the capture are session_start.
        XCTAssertEqual(sessionStart.count, 6)
    }

    /// `responseIndex` must follow payload order, because it is the documented tie-break
    /// for the five priority-0 campaigns this capture contains.
    func testResponseIndexFollowsPayloadOrder() {
        let campaigns = parsed().campaigns
        XCTAssertEqual(campaigns.map { $0.responseIndex }, Array(0..<campaigns.count))
        XCTAssertEqual(campaigns.first?.campaignId, 2055)
    }

    /// No campaign in the capture carries an expiry, so none may parse as already expired —
    /// that would silently suppress every one of them.
    func testNoCampaignIsExpired() {
        for campaign in parsed().campaigns {
            XCTAssertNil(campaign.expiresAt)
            XCTAssertFalse(campaign.hasExpired(at: Date()))
        }
    }

    // MARK: - The tie-break, against real data

    /// The captured payload contains a genuine tie: campaigns 2041 and 2046 are both
    /// session_start at priority 9, and 2041 comes first. Five of the ten live identities are
    /// in this state, so this is the ordinary case rather than a contrived one.
    ///
    /// The contract is that the backend has already ordered `messages` the way the campaigns are
    /// configured, so a tie is settled by payload position. Asserting it here rather than only in
    /// `TriggerEvaluatorTests` is the point: those tests build their own campaigns and could agree
    /// with each other while disagreeing with the wire.
    func testAPriorityTieIsSettledByPayloadOrder() {
        let campaigns = parsedAugust().campaigns
        let sessionStart = campaigns.filter {
            if case .sessionStart = $0.trigger { return true }
            return false
        }
        guard let top = sessionStart.map({ $0.priority }).max() else {
            return XCTFail("the capture has no session_start campaign")
        }
        let tied = sessionStart.filter { $0.priority == top }
        XCTAssertGreaterThan(tied.count, 1,
                             "this test is only meaningful while the capture contains a tie")

        let winner = selectCampaign(occurrence: .sessionStart,
                                    campaigns: campaigns,
                                    capState: .empty,
                                    now: Date(timeIntervalSince1970: 1_700_000_000),
                                    cooldown: 0,
                                    isArtworkReady: { _ in true })

        let expected = tied.min { $0.responseIndex < $1.responseIndex }
        XCTAssertEqual(winner?.campaignId, expected?.campaignId)
        XCTAssertEqual(winner?.campaignId, 2041,
                       "2041 and 2046 tie at priority 9; 2041 is first in the payload")
    }
}
