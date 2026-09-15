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
}
