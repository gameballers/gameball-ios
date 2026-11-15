//
//  GameballInAppMessage.swift
//  Gameball
//

import UIKit

/// Text alignment as authored, resolved to a directional alignment at layout time.
///
/// `leading`/`trailing` rather than `left`/`right` so a right-to-left locale mirrors
/// without the parser having to know the layout direction.
public enum GameballTextAlignment {
    case leading
    case center
    case trailing
}

/// The colours and alignments a campaign was authored with.
///
/// Every colour is optional and `nil` means "use the host's theme" — never a literal
/// default, which is how a message ends up unreadable in dark mode.
public struct GameballMessageStyle {
    public let backgroundColor: UIColor?
    public let textColor: UIColor?
    public let headerColor: UIColor?
    public let closeButtonColor: UIColor?
    public let borderColor: UIColor?
    public let frameColor: UIColor?
    public let headerAlignment: GameballTextAlignment
    public let bodyAlignment: GameballTextAlignment
}

/// A message that is ready to draw.
///
/// This is the value handed to the host's delegate, so it is deliberately free of
/// campaign bookkeeping — priority, expiry and repeat rules live on
/// `InAppMessageCampaign` and are none of the host's business.
/// A reward campaign rendered as the message's own content.
///
/// The campaign **is** the content — there is no headline, body, image or button, because this is
/// not a teaser that links to a game, it is the game.
///
/// Deliberately not a URL on the wire: one would have to carry the api key and the player id,
/// making the payload both credential-bearing and customer-specific. The SDK composes the URL from
/// state it already holds and the two fields here.
///
/// There is no delay and no dismissal limit, by product decision: a game opens when its trigger
/// fires and is held to exactly the frequency rules a message is.
public struct GameballWidgetContent {
    /// The challenge to open. All local bookkeeping keys off this, never off the entry's
    /// `campaignId`, which is always 0 on a game.
    public let gameCampaignId: Int

    /// Which game it is, as the open-details text: `wheel`, `quiz`, `scratch`…
    public let gameCampaignType: String

    public init(gameCampaignId: Int, gameCampaignType: String) {
        self.gameCampaignId = gameCampaignId
        self.gameCampaignType = gameCampaignType
    }

    /// What the host widget is asked to open.
    public var openDetail: String { "details_\(gameCampaignType)_\(gameCampaignId)" }
}

public struct GameballInAppMessage {
    /// `"{campaignId}"`, or `"{campaignId}/{variationId}"` when the campaign is an
    /// A/B test. Stable for the life of the campaign, so a host may key off it.
    public let id: String
    public let type: GameballMessageType
    public let header: String?
    public let body: String?
    public let imageURL: URL?
    public let iconURL: URL?
    /// `nil` means the surface is inert — a tap does nothing. Distinct from `.dismiss`,
    /// which closes the message.
    public let clickAction: GameballClickAction?
    public let buttons: [GameballMessageButton]
    public let showCloseButton: Bool
    public let dismissOnScrimTap: Bool
    /// Seconds of *visible* time before the message closes itself; `nil` means it waits
    /// for the customer.
    public let autoDismissAfter: TimeInterval?
    public let layout: GameballMessageLayout
    public let orientation: GameballMessageOrientation
    public let slidePosition: GameballSlidePosition
    /// Arbitrary key/values the dashboard attached, passed through untouched.
    public let extras: [String: Any]
    public let style: GameballMessageStyle

    /// A reward campaign to render instead of artwork and copy. `nil` for every ordinary message.
    ///
    /// A message carrying this renders a live widget, so it is exempt from the parser's "nothing to
    /// render" rule — its content arrives over the network at display time rather than in the
    /// payload.
    public let widget: GameballWidgetContent?

    /// Whether this message's content is a reward campaign rather than artwork.
    public var isWidget: Bool { widget != nil }
}
