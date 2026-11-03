//
//  TriggerEvaluatorTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class TriggerEvaluatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func select(_ occurrence: TriggerOccurrence,
                        _ campaigns: [InAppMessageCampaign],
                        capState: CapState = .empty,
                        now: Date? = nil,
                        cooldown: TimeInterval = defaultDisplayCooldown,
                        isArtworkReady: (InAppMessageCampaign) -> Bool = artworkAlwaysReady)
        -> InAppMessageCampaign? {
        return selectCampaign(occurrence: occurrence,
                              campaigns: campaigns,
                              capState: capState,
                              now: now ?? self.now,
                              cooldown: cooldown,
                              isArtworkReady: isArtworkReady)
    }

    // MARK: - Trigger matching

    func testSessionStartSelectsSessionStartCampaign() {
        let campaign = makeCampaign(trigger: .sessionStart)
        XCTAssertEqual(select(.sessionStart, [campaign])?.campaignId, 1)
    }

    func testSessionStartDoesNotSelectAnEventCampaign() {
        let campaign = makeCampaign(trigger: .event(name: "place_order", filters: []))
        XCTAssertNil(select(.sessionStart, [campaign]))
    }

    func testNamedEventSelectsMatchingCampaign() {
        let campaign = makeCampaign(trigger: .event(name: "place_order", filters: []))
        XCTAssertEqual(select(.event(name: "place_order", properties: [:]), [campaign])?.campaignId, 1)
    }

    func testNonMatchingEventNameSelectsNothing() {
        let campaign = makeCampaign(trigger: .event(name: "place_order", filters: []))
        XCTAssertNil(select(.event(name: "view_product", properties: [:]), [campaign]))
    }

    func testFiltersMustAllMatch() {
        let campaign = makeCampaign(trigger: .event(name: "place_order", filters: [
            PropertyFilter(name: "price", op: .greaterThan, value: 100),
            PropertyFilter(name: "currency", op: .equals, value: "USD")
        ]))
        XCTAssertNotNil(select(.event(name: "place_order",
                                      properties: ["price": 150, "currency": "USD"]), [campaign]))
        // One failing filter is enough to disqualify it.
        XCTAssertNil(select(.event(name: "place_order",
                                   properties: ["price": 150, "currency": "EUR"]), [campaign]))
    }

    func testMissingPropertyNeverMatches() {
        let campaign = makeCampaign(trigger: .event(name: "place_order", filters: [
            PropertyFilter(name: "price", op: .greaterThan, value: 100)
        ]))
        XCTAssertNil(select(.event(name: "place_order", properties: [:]), [campaign]))
    }

    // MARK: - Expiry

    func testExpiredCampaignIsNeverSelected() {
        let campaign = makeCampaign(expiresAt: now.addingTimeInterval(-1))
        XCTAssertNil(select(.sessionStart, [campaign]))
    }

    /// Campaigns are held for the session, so one fetched at 23:58 would otherwise fire all
    /// night — and keep firing after the campaign was paused.
    func testExpiryIsCheckedAtSelectionNotOnlyAtFetch() {
        let campaign = makeCampaign(expiresAt: now.addingTimeInterval(60))
        XCTAssertNotNil(select(.sessionStart, [campaign], now: now))
        XCTAssertNil(select(.sessionStart, [campaign], now: now.addingTimeInterval(120)))
    }

    func testExpiryAtExactlyNowIsExpired() {
        let campaign = makeCampaign(expiresAt: now)
        XCTAssertNil(select(.sessionStart, [campaign], now: now))
    }

    // MARK: - Repeat rules

    func testNonRepeatableCampaignIsNeverSelectedTwice() {
        let campaign = makeCampaign(repeatable: false)
        XCTAssertNotNil(select(.sessionStart, [campaign]))

        var capState = CapState.empty
        capState.recordDisplay(campaignId: 1, at: now.addingTimeInterval(-100_000))
        XCTAssertNil(select(.sessionStart, [campaign], capState: capState),
                     "a once-ever campaign must stay suppressed however long ago it showed")
    }

    func testRepeatableCampaignRespectsMinInterval() {
        let campaign = makeCampaign(repeatable: true, minInterval: 300)
        var capState = CapState.empty
        capState.recordDisplay(campaignId: 1, at: now.addingTimeInterval(-100))

        // Inside its own interval, and outside the global floor so only the interval applies.
        XCTAssertNil(select(.sessionStart, [campaign], capState: capState, cooldown: 0))
        XCTAssertNotNil(select(.sessionStart, [campaign], capState: capState,
                               now: now.addingTimeInterval(300), cooldown: 0))
    }

    func testRepeatableWithNilIntervalSelectsEveryOccurrence() {
        let campaign = makeCampaign(repeatable: true, minInterval: nil)
        var capState = CapState.empty
        capState.recordDisplay(campaignId: 1, at: now.addingTimeInterval(-1))
        XCTAssertNotNil(select(.sessionStart, [campaign], capState: capState, cooldown: 0))
    }

    // MARK: - Global floor

    func testInsideGlobalFloorNothingIsSelected() {
        let campaign = makeCampaign(campaignId: 42)
        var capState = CapState.empty
        // Something unrelated displayed 5 seconds ago.
        capState.recordDisplay(campaignId: 7, at: now.addingTimeInterval(-5))
        XCTAssertNil(select(.sessionStart, [campaign], capState: capState, cooldown: 30),
                     "the floor is global, so even a never-shown campaign waits")
    }

    func testOutsideGlobalFloorSelectionResumes() {
        let campaign = makeCampaign(campaignId: 42)
        var capState = CapState.empty
        capState.recordDisplay(campaignId: 7, at: now.addingTimeInterval(-31))
        XCTAssertNotNil(select(.sessionStart, [campaign], capState: capState, cooldown: 30))
    }

    /// Eligibility is filtered first, so a high-priority campaign that cannot display does
    /// not consume the occurrence a usable one could have had.
    func testFloorIsCheckedAfterEligibilityNotPerCampaign() {
        let spent = makeCampaign(campaignId: 1, priority: 10, repeatable: false, responseIndex: 0)
        let fresh = makeCampaign(campaignId: 2, priority: 1, responseIndex: 1)

        var capState = CapState.empty
        capState.recordDisplay(campaignId: 1, at: now.addingTimeInterval(-10_000))

        XCTAssertEqual(select(.sessionStart, [spent, fresh], capState: capState)?.campaignId, 2)
    }

    // MARK: - Priority and tie-breaking

    func testHighestPriorityWins() {
        let low = makeCampaign(campaignId: 1, priority: 5, responseIndex: 0)
        let high = makeCampaign(campaignId: 2, priority: 10, responseIndex: 1)
        XCTAssertEqual(select(.sessionStart, [low, high])?.campaignId, 2)
    }

    /// Swift's `sort` is not guaranteed stable, so a single run can pass by luck. The
    /// repetition is the test.
    func testTiesBreakOnResponseOrderStably() {
        let campaigns = (0..<20).map {
            makeCampaign(campaignId: 100 + $0, priority: 5, responseIndex: $0)
        }
        for run in 0..<50 {
            XCTAssertEqual(select(.sessionStart, campaigns)?.campaignId, 100,
                           "run \(run) picked a different winner")
        }
    }

    func testTieBreakFollowsResponseIndexNotArrayOrder() {
        let second = makeCampaign(campaignId: 2, priority: 5, responseIndex: 1)
        let first = makeCampaign(campaignId: 1, priority: 5, responseIndex: 0)
        // Handed to the evaluator out of order on purpose.
        XCTAssertEqual(select(.sessionStart, [second, first])?.campaignId, 1)
    }

    // MARK: - Filtered-not-refused

    /// Filtered during eligibility rather than refused at display, so a usable
    /// lower-priority campaign still wins instead of the occurrence being wasted.
    func testUnsupportedTypeIsFilteredSoLowerPriorityWins() {
        let unsupported = makeCampaign(campaignId: 1, priority: 10, type: .unsupported,
                                       responseIndex: 0)
        let usable = makeCampaign(campaignId: 2, priority: 1, type: .modal, responseIndex: 1)
        XCTAssertEqual(select(.sessionStart, [unsupported, usable])?.campaignId, 2)
    }

    func testUnreadyArtworkIsFilteredSoLowerPriorityWins() {
        let unready = makeCampaign(campaignId: 1, priority: 10, responseIndex: 0)
        let ready = makeCampaign(campaignId: 2, priority: 1, responseIndex: 1)
        let selected = select(.sessionStart, [unready, ready],
                              isArtworkReady: { $0.campaignId != 1 })
        XCTAssertEqual(selected?.campaignId, 2)
    }

    func testNoEligibleCampaignSelectsNothing() {
        XCTAssertNil(select(.sessionStart, []))
    }

    // MARK: - Purchase

    /// A purchase is not a trigger type — it arrives as an event named `purchase`.
    func testPurchaseSelectsCampaignTriggeredOnPurchaseEvent() {
        let campaign = makeCampaign(trigger: .event(name: gameballPurchaseEventName, filters: []))
        let occurrence = TriggerOccurrence.event(name: gameballPurchaseEventName,
                                                properties: ["productId": "sku-1", "price": 150])
        XCTAssertEqual(select(occurrence, [campaign])?.campaignId, 1)
    }

    func testPurchaseFiltersOnPriceAndProductId() {
        let campaign = makeCampaign(trigger: .event(name: gameballPurchaseEventName, filters: [
            PropertyFilter(name: "price", op: .greaterThan, value: 100),
            PropertyFilter(name: "productId", op: .equals, value: "sku-1")
        ]))
        XCTAssertNotNil(select(.event(name: gameballPurchaseEventName,
                                      properties: ["productId": "sku-1", "price": 150]), [campaign]))
        XCTAssertNil(select(.event(name: gameballPurchaseEventName,
                                   properties: ["productId": "sku-1", "price": 50]), [campaign]))
        XCTAssertNil(select(.event(name: gameballPurchaseEventName,
                                   properties: ["productId": "sku-2", "price": 150]), [campaign]))
    }
}
