//
//  FrequencyCap.swift
//  Gameball
//

import Foundation

/// What has been shown, and when.
///
/// Two facts, because two different rules need them: the global display floor asks only
/// "when did *anything* last show", while the per-campaign repeat rule asks "when did
/// *this* last show".
struct CapState: Codable {
    var lastDisplayAt: Date?
    var lastDisplayByCampaign: [Int: Date]

    static let empty = CapState(lastDisplayAt: nil, lastDisplayByCampaign: [:])

    mutating func recordDisplay(campaignId: Int, at time: Date) {
        lastDisplayByCampaign[campaignId] = time
        // Never let the global marker travel backwards. A device clock correction or an
        // out-of-order replay would otherwise reopen the floor early.
        if let existing = lastDisplayAt, existing > time { return }
        lastDisplayAt = time
    }
}

/// Owns `CapState` and its persistence.
///
/// History is deliberately **not** pruned. The backend stops returning a non-repeatable
/// campaign once its impression lands, but that round trip is not instant and can fail —
/// so forgetting an entry locally is how a once-ever message shows twice.
final class FrequencyCap {
    private let store: IAMStore
    private let customerId: String
    private var current: CapState = .empty

    init(store: IAMStore, customerId: String) {
        self.store = store
        self.customerId = customerId
    }

    var state: CapState {
        return current
    }

    func load() {
        current = CustomerScoped<CapState>.decode(store.data(forKey: IAMStoreKey.displayHistory),
                                                customerId: customerId) ?? .empty
    }

    func recordDisplay(campaignId: Int, at time: Date) {
        current.recordDisplay(campaignId: campaignId, at: time)
        persist()
    }

    func reset() {
        current = .empty
        store.set(nil, forKey: IAMStoreKey.displayHistory)
    }

    private func persist() {
        store.set(CustomerScoped.encoded(current, customerId: customerId),
                  forKey: IAMStoreKey.displayHistory)
    }
}
