//
//  CampaignCacheTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class CampaignCacheTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Builds a sync payload whose single campaign expires at the given moment.
    private func payload(campaignId: Int = 1, expiresAt: String? = nil) -> Data {
        var campaign: [String: Any] = [
            "campaignId": campaignId,
            "messageType": 2,
            "contentMode": "prerendered",
            "trigger": ["type": "session_start", "repeatable": true],
            "locale": ["header": "Header", "message": "Body"]
        ]
        if let expiresAt = expiresAt { campaign["expiresAt"] = expiresAt }
        return try! JSONSerialization.data(withJSONObject: [
            "cooldownSeconds": 45,
            "messages": [campaign]
        ])
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: - Round trip

    func testSavedPayloadIsReParsedOnLoad() {
        let store = InMemoryIAMStore()
        let cache = CampaignCache(store: store)
        cache.save(payload: payload(campaignId: 7), customerId: "cust-1")

        let loaded = cache.load(customerId: "cust-1", now: now)
        XCTAssertEqual(loaded?.campaigns.map { $0.campaignId } ?? [], [7])
        XCTAssertEqual(loaded?.cooldown, 45)
    }

    /// The result came *from* the cache, so it carries no raw payload — that is what stops
    /// a cache hit being written straight back over itself.
    func testLoadedResultCarriesNoRawPayload() {
        let store = InMemoryIAMStore()
        let cache = CampaignCache(store: store)
        cache.save(payload: payload(), customerId: "cust-1")
        XCTAssertNil(cache.load(customerId: "cust-1", now: now)?.rawPayload)
    }

    func testNothingCachedYieldsNil() {
        let cache = CampaignCache(store: InMemoryIAMStore())
        XCTAssertNil(cache.load(customerId: "cust-1", now: now))
    }

    // MARK: - Scoping and corruption

    func testADifferentCustomerYieldsNil() {
        let store = InMemoryIAMStore()
        let cache = CampaignCache(store: store)
        cache.save(payload: payload(), customerId: "cust-1")
        XCTAssertNil(cache.load(customerId: "cust-2", now: now))
    }

    func testCorruptPayloadYieldsNilWithoutThrowing() {
        let store = InMemoryIAMStore()
        let cache = CampaignCache(store: store)
        cache.save(payload: Data("{ not json".utf8), customerId: "cust-1")
        XCTAssertNil(cache.load(customerId: "cust-1", now: now))
    }

    func testCorruptWrapperYieldsNilWithoutThrowing() {
        let store = InMemoryIAMStore()
        store.set(Data("not even a wrapper".utf8), forKey: IAMStoreKey.campaignCache)
        XCTAssertNil(CampaignCache(store: store).load(customerId: "cust-1", now: now))
    }

    // MARK: - Expiry

    /// The cache can outlive the campaigns in it, so expiry is applied on read. Without
    /// this, a cached campaign would keep firing for as long as the cache survived.
    func testExpiredCampaignsAreExcludedOnLoad() {
        let store = InMemoryIAMStore()
        let cache = CampaignCache(store: store)
        cache.save(payload: payload(campaignId: 7,
                                    expiresAt: iso(now.addingTimeInterval(-60))),
                   customerId: "cust-1")

        let loaded = cache.load(customerId: "cust-1", now: now)
        XCTAssertNotNil(loaded, "the payload is still readable")
        XCTAssertTrue(loaded?.campaigns.isEmpty ?? false, "the expired campaign must be dropped")
    }

    func testUnexpiredCampaignsSurviveLoad() {
        let store = InMemoryIAMStore()
        let cache = CampaignCache(store: store)
        cache.save(payload: payload(campaignId: 7,
                                    expiresAt: iso(now.addingTimeInterval(600))),
                   customerId: "cust-1")
        XCTAssertEqual(cache.load(customerId: "cust-1", now: now)?.campaigns.count, 1)
    }

    /// Re-parsed on read rather than stored as objects, so a payload a newer SDK would
    /// reject is not resurrected as stale model values — and there is no serialiser to keep
    /// in step with the model.
    func testLoadAppliesCurrentParsingRules() {
        let store = InMemoryIAMStore()
        let cache = CampaignCache(store: store)
        // A campaign the current parser drops: an event trigger with no name.
        let unusable = try! JSONSerialization.data(withJSONObject: [
            "messages": [[
                "campaignId": 3,
                "messageType": 2,
                "trigger": ["type": "event", "eventId": 99],
                "locale": ["message": "Body"]
            ]]
        ])
        cache.save(payload: unusable, customerId: "cust-1")
        XCTAssertTrue(cache.load(customerId: "cust-1", now: now)?.campaigns.isEmpty ?? false)
    }

    // MARK: - Clearing

    func testClearEmptiesTheCache() {
        let store = InMemoryIAMStore()
        let cache = CampaignCache(store: store)
        cache.save(payload: payload(), customerId: "cust-1")

        cache.clear()
        XCTAssertNil(cache.load(customerId: "cust-1", now: now))
        XCTAssertNil(store.data(forKey: IAMStoreKey.campaignCache))
    }

    func testSaveOverwritesThePreviousPayload() {
        let store = InMemoryIAMStore()
        let cache = CampaignCache(store: store)
        cache.save(payload: payload(campaignId: 1), customerId: "cust-1")
        cache.save(payload: payload(campaignId: 2), customerId: "cust-1")
        XCTAssertEqual(cache.load(customerId: "cust-1", now: now)?.campaigns.map { $0.campaignId } ?? [],
                       [2])
    }
}
