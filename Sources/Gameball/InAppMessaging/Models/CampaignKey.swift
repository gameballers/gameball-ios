//
//  CampaignKey.swift
//  Gameball
//

import Foundation

/// Which sequence an id belongs to.
///
/// Not cosmetic. The backend's contract states that challenge ids and message campaign ids are
/// separate sequences that overlap numerically, so a bare `Int` cannot identify a campaign once
/// both kinds share one list.
enum CampaignKind: String {
    case message
    case game
}

/// Identifies one campaign across both kinds.
///
/// Every game entry arrives with `campaignId: 0` — the field is deliberately left empty rather than
/// filled with a challenge id — so a game's identity is its `gameCampaignId`. Keyed history
/// therefore has to carry the kind as well as the number, or one wheel displaying would suppress
/// every other game.
struct CampaignKey: Hashable {
    let kind: CampaignKind
    let id: Int

    static func message(_ id: Int) -> CampaignKey { CampaignKey(kind: .message, id: id) }
    static func game(_ id: Int) -> CampaignKey { CampaignKey(kind: .game, id: id) }

    /// The form written to storage. Stable: changing it orphans display history.
    var storageKey: String { "\(kind.rawValue):\(id)" }

    /// Reads `storageKey`, and also a bare number.
    ///
    /// A bare number is how every history written before this change looks, and all of those are
    /// message campaigns — games did not exist yet. Reading them as messages is what stops an
    /// update re-showing every once-ever campaign.
    static func parse(_ raw: String) -> CampaignKey? {
        if let bare = Int(raw) { return .message(bare) }

        guard let separator = raw.firstIndex(of: ":"), separator != raw.startIndex else {
            return nil
        }
        guard let id = Int(raw[raw.index(after: separator)...]),
              let kind = CampaignKind(rawValue: String(raw[raw.startIndex..<separator]))
        else {
            return nil
        }
        return CampaignKey(kind: kind, id: id)
    }
}

extension CampaignKey: CustomStringConvertible {
    /// How a log line names a campaign: `message 2215`, `game 9645`. Never the bare campaignId,
    /// which is 0 for every game and so named all of them at once.
    var description: String { "\(kind.rawValue) \(id)" }
}
