//
//  InAppMessageCampaign.swift
//  Gameball
//

import Foundation

/// A parsed campaign: the message to draw plus every rule that decides whether it may be.
///
/// Internal by design. The host sees `GameballInAppMessage`; scheduling metadata stays in
/// the module.
struct InAppMessageCampaign {
    let campaignId: Int
    let variationId: Int?
    /// Correlates a display back to the specific send that produced it. Reported with
    /// every event when present.
    let dispatchId: String?
    let name: String?
    let priority: Int
    let expiresAt: Date?
    /// A test send: it displays normally but reports nothing, so a marketer previewing a
    /// campaign does not pollute its metrics.
    let isTest: Bool
    let repeatable: Bool
    /// Minimum seconds between two displays of *this* campaign. `nil` with
    /// `repeatable == true` means every matching occurrence may display.
    let minInterval: TimeInterval?
    let trigger: MessageTrigger
    let message: GameballInAppMessage
    /// Position in the sync payload, carried explicitly as the documented tie-break for
    /// equal-priority campaigns. Swift's `sort` is not guaranteed stable, so without this
    /// a tie would rotate arbitrarily between runs.
    let responseIndex: Int

    /// How this campaign is identified in display history.
    ///
    /// A game entry's `campaignId` is always 0, so its identity is the id of the game it opens.
    /// Reading this rather than `campaignId` is what keeps the two kinds from sharing cap state —
    /// challenge ids and message campaign ids are separate sequences that overlap numerically.
    var key: CampaignKey {
        guard let widget = message.widget else { return .message(campaignId) }
        return .game(widget.gameCampaignId)
    }

    /// Whether impressions, clicks and dismissals of this campaign go to the events endpoint.
    ///
    /// Never for a test send, and never for a game: a game is not a message campaign, its
    /// campaignId is always 0, and its engagement is recorded through the challenge flow when the
    /// customer plays.
    var reportsTelemetry: Bool {
        return !isTest && !message.isWidget
    }

    func hasExpired(at now: Date) -> Bool {
        guard let expiresAt = expiresAt else { return false }
        return expiresAt <= now
    }
}
