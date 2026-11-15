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
    var lastDisplayByCampaign: [CampaignKey: Date]

    static let empty = CapState(lastDisplayAt: nil, lastDisplayByCampaign: [:])

    mutating func recordDisplay(campaign: CampaignKey, at time: Date) {
        lastDisplayByCampaign[campaign] = time
        // Never let the global marker travel backwards. A device clock correction or an
        // out-of-order replay would otherwise reopen the floor early.
        if let existing = lastDisplayAt, existing > time { return }
        lastDisplayAt = time
    }

    // MARK: - Codable

    // Hand-written because the key is a struct. `JSONEncoder` special-cases `String` and `Int`
    // dictionary keys and writes an object; anything else becomes a flat array of alternating
    // keys and values. Left to itself, `[CampaignKey: Date]` would silently change the stored
    // shape and orphan every existing history.
    //
    // The read is what carries installs across the change. Verified against 3.4.0, which writes
    // `{"lastDisplayByCampaign":{"2215":721692800}}` — a bare number, which `CampaignKey.parse`
    // reads as a message campaign, because games did not exist when it was written.

    private enum CodingKeys: String, CodingKey {
        case lastDisplayAt
        case lastDisplayByCampaign
    }

    init(lastDisplayAt: Date?, lastDisplayByCampaign: [CampaignKey: Date]) {
        self.lastDisplayAt = lastDisplayAt
        self.lastDisplayByCampaign = lastDisplayByCampaign
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastDisplayAt = try container.decodeIfPresent(Date.self, forKey: .lastDisplayAt)

        let stored = try container.decodeIfPresent([String: Date].self,
                                                   forKey: .lastDisplayByCampaign) ?? [:]
        var restored: [CampaignKey: Date] = [:]
        for (raw, date) in stored {
            // An unparseable key is dropped rather than failing the whole decode: losing one
            // entry shows one campaign twice, while throwing loses the entire history.
            guard let key = CampaignKey.parse(raw) else {
                iamLog("display history has an unreadable key '\(raw)'; dropping that entry")
                continue
            }
            restored[key] = date
        }
        lastDisplayByCampaign = restored
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastDisplayAt, forKey: .lastDisplayAt)

        var stored: [String: Date] = [:]
        for (key, date) in lastDisplayByCampaign {
            stored[key.storageKey] = date
        }
        try container.encode(stored, forKey: .lastDisplayByCampaign)
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

    func recordDisplay(campaign: CampaignKey, at time: Date) {
        current.recordDisplay(campaign: campaign, at: time)
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
