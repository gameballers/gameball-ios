//
//  FrequencyCapTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class FrequencyCapTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRecordedDisplaySurvivesReload() {
        let store = InMemoryIAMStore()

        let cap = FrequencyCap(store: store, customerId: "cust-1")
        cap.load()
        cap.recordDisplay(campaignId: 42, at: now)

        let reloaded = FrequencyCap(store: store, customerId: "cust-1")
        reloaded.load()
        XCTAssertEqual(reloaded.state.lastDisplayAt, now)
        XCTAssertEqual(reloaded.state.lastDisplayByCampaign[42], now)
    }

    func testStateForADifferentCustomerIsDiscarded() {
        let store = InMemoryIAMStore()

        let cap = FrequencyCap(store: store, customerId: "cust-1")
        cap.load()
        cap.recordDisplay(campaignId: 42, at: now)

        let other = FrequencyCap(store: store, customerId: "cust-2")
        other.load()
        XCTAssertNil(other.state.lastDisplayAt)
        XCTAssertTrue(other.state.lastDisplayByCampaign.isEmpty)
    }

    func testCorruptStoredDataYieldsEmptyStateWithoutThrowing() {
        let store = InMemoryIAMStore()
        store.set(Data("not json at all".utf8), forKey: IAMStoreKey.displayHistory)

        let cap = FrequencyCap(store: store, customerId: "cust-1")
        cap.load()
        XCTAssertNil(cap.state.lastDisplayAt)
        XCTAssertTrue(cap.state.lastDisplayByCampaign.isEmpty)
    }

    func testResetClearsHistory() {
        let store = InMemoryIAMStore()
        let cap = FrequencyCap(store: store, customerId: "cust-1")
        cap.load()
        cap.recordDisplay(campaignId: 42, at: now)

        cap.reset()
        XCTAssertNil(cap.state.lastDisplayAt)
        XCTAssertTrue(cap.state.lastDisplayByCampaign.isEmpty)

        // And it must not come back on the next load.
        let reloaded = FrequencyCap(store: store, customerId: "cust-1")
        reloaded.load()
        XCTAssertTrue(reloaded.state.lastDisplayByCampaign.isEmpty)
    }

    /// Not pruned: the backend stops returning a non-repeatable campaign once its
    /// impression lands, so forgetting an old entry could show a once-ever message twice.
    func testHistoryIsNotPrunedByCampaignCount() {
        let store = InMemoryIAMStore()
        let cap = FrequencyCap(store: store, customerId: "cust-1")
        cap.load()

        for id in 0..<200 {
            cap.recordDisplay(campaignId: id, at: now.addingTimeInterval(TimeInterval(id)))
        }

        let reloaded = FrequencyCap(store: store, customerId: "cust-1")
        reloaded.load()
        XCTAssertEqual(reloaded.state.lastDisplayByCampaign.count, 200)
        XCTAssertEqual(reloaded.state.lastDisplayByCampaign[0], now)
    }

    func testLastDisplayAtTracksTheMostRecentDisplay() {
        var state = CapState.empty
        state.recordDisplay(campaignId: 1, at: now)
        state.recordDisplay(campaignId: 2, at: now.addingTimeInterval(10))

        XCTAssertEqual(state.lastDisplayAt, now.addingTimeInterval(10))
        XCTAssertEqual(state.lastDisplayByCampaign[1], now)
        XCTAssertEqual(state.lastDisplayByCampaign[2], now.addingTimeInterval(10))
    }

    /// Clock changes and out-of-order replays must not make `lastDisplayAt` travel
    /// backwards, or the global floor would reopen early.
    func testLastDisplayAtDoesNotMoveBackwards() {
        var state = CapState.empty
        state.recordDisplay(campaignId: 1, at: now)
        state.recordDisplay(campaignId: 2, at: now.addingTimeInterval(-60))

        XCTAssertEqual(state.lastDisplayAt, now)
    }

    func testNothingIsWrittenBeforeADisplayIsRecorded() {
        let store = InMemoryIAMStore()
        let cap = FrequencyCap(store: store, customerId: "cust-1")
        cap.load()
        XCTAssertNil(store.data(forKey: IAMStoreKey.displayHistory),
                     "loading an empty cap must not write")
    }
}
