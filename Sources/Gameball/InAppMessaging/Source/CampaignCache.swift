//
//  CampaignCache.swift
//  Gameball
//

import Foundation

/// The last payload a sync succeeded with, per customer.
///
/// Stores the raw bytes rather than encoded model values, and **re-parses on read**. Two
/// reasons, both learned the hard way: a payload a newer SDK would reject is not resurrected
/// as stale objects, and there is no second serialiser to keep in step with the model every
/// time a field is added.
///
/// Consulted only when a sync fails. A successful sync — including a successful *empty* one —
/// always wins, or a customer whose campaigns were switched off would keep seeing them.
final class CampaignCache {
    private let store: IAMStore

    init(store: IAMStore) {
        self.store = store
    }

    func save(payload: Data, customerId: String) {
        store.set(CustomerScoped.encoded(payload, customerId: customerId),
                  forKey: IAMStoreKey.campaignCache)
    }

    /// Returns `nil` when there is nothing usable cached for this customer.
    ///
    /// The result carries no `rawPayload`: it came *from* the cache, and marking it as such
    /// is what stops a cache hit being written straight back over itself.
    func load(customerId: String, now: Date) -> SyncResult? {
        guard let payload = CustomerScoped<Data>.decode(store.data(forKey: IAMStoreKey.campaignCache),
                                                      customerId: customerId) else {
            return nil
        }

        let parsed = MessageParser.parseSyncResponse(payload)
        guard parsed.rawPayload != nil else {
            iamLog("cached payload could not be re-parsed; discarding it")
            return nil
        }

        // The cache can outlive the campaigns in it, so expiry is applied here too. Without
        // this a cached campaign keeps firing for as long as the cache survives.
        let live = parsed.campaigns.filter { !$0.hasExpired(at: now) }
        if live.count != parsed.campaigns.count {
            iamLog("dropped \(parsed.campaigns.count - live.count) expired campaign(s) from "
                 + "the cache")
        }

        return SyncResult(campaigns: live, cooldown: parsed.cooldown,
                          quietHours: parsed.quietHours, rawPayload: nil)
    }

    func clear() {
        store.set(nil, forKey: IAMStoreKey.campaignCache)
    }
}
