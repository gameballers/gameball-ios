//
//  MessageViewAttributes.swift
//  Gameball
//

import UIKit

/// Per-type layout constants, mirroring the cross-platform UI spec's table one-for-one.
///
/// Every value here is a **Constant** in that spec's sense: fixed in the SDK, identical on Flutter,
/// Android, iOS and React Native, exposed to neither the host nor the campaign. They are the
/// numbers that make one campaign look the same everywhere, so changing one on a single platform is
/// exactly the drift the spec exists to end. Anything a campaign can influence lives on
/// `GameballInAppMessage`, and anything the host influences resolves through `MessageTheme`.
///
/// Units are points, which the spec treats as interchangeable with Flutter's logical pixels.
struct MessageViewAttributes {

    /// Radius on every button, every type.
    static let buttonCornerRadius: CGFloat = 8

    struct Modal {
        /// Card to screen edge.
        var margin = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        /// The card stops growing here; it never fills.
        var maxWidth: CGFloat = 420
        /// Anti-alias clipped, so the artwork's top corners round too.
        var cornerRadius: CGFloat = 16
        /// Around the scrolling copy block. No bottom inset — the button block carries its own.
        var padding = UIEdgeInsets(top: 20, left: 20, bottom: 0, right: 20)
        /// Around the button block, which sits outside the scroll view.
        var buttonsPadding = UIEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        /// Around buttons floated over a full-bleed card.
        var imageOnlyButtonsPadding = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        /// Applied only when both header and body are present.
        var labelsSpacing: CGFloat = 8
        /// Between buttons, and between wrapped rows.
        var buttonSpacing: CGFloat = 8
        var buttonPadding = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        /// From the card's top trailing corner.
        var closeInset: CGFloat = 4

        /// Artwork at or above this ratio fills the card width with no bars.
        ///
        /// A *shape*, not a fraction of the screen — which is what makes the crossover
        /// device-independent wherever there is room for it.
        var minImageRatio: CGFloat = 0.55
        /// Height always kept for copy and buttons, so artwork can never squeeze out the call to
        /// action. On a cramped screen this binds before `minImageRatio` does.
        var copyReserve: CGFloat = 120
        /// Artwork cap when the image is the whole message.
        var imageOnlyHeightFraction: CGFloat = 0.65

        static let defaults = Modal()
    }

    struct Slideup {
        /// Banner to screen edge, inside the safe area.
        var margin = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        var maxWidth: CGFloat = 480
        var cornerRadius: CGFloat = 12
        var padding = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        /// Fixed square. Sizing it to its own ratio would change the banner's height per campaign.
        var iconSize = CGSize(width: 40, height: 40)
        var iconCornerRadius: CGFloat = 8
        /// Directional — mirrors under right-to-left.
        var iconSpacing: CGFloat = 12
        /// Directional; the glyph itself flips under right-to-left.
        var chevronSpacing: CGFloat = 8
        var chevronSize: CGFloat = 20
        /// Then ellipsis. This is what keeps a banner a band: a slideup that grew with its content
        /// would eventually cover the screen it exists not to block.
        var maxTextLines: Int = 3

        static let defaults = Slideup()
    }

    struct Fullscreen {
        /// Around the scrolling copy. No bottom inset — the button block carries its own.
        var padding = UIEdgeInsets(top: 24, left: 24, bottom: 0, right: 24)
        /// Around the button block, which sits outside the scroll view.
        var buttonsPadding = UIEdgeInsets(top: 28, left: 24, bottom: 24, right: 24)
        /// Around buttons floated over a full-bleed image.
        var imageOnlyButtonsPadding = UIEdgeInsets(top: 0, left: 24, bottom: 32, right: 24)
        /// The artwork's fixed share of the available height.
        ///
        /// A fixed share rather than the slack the copy leaves, which is what stops it
        /// letterboxing when the copy happens to be short.
        var imageHeightFraction: CGFloat = 0.50
        var labelsSpacing: CGFloat = 12
        /// Between stacked buttons. They never sit side by side — a modal's compact trailing row
        /// looks lost at this size.
        var buttonSpacing: CGFloat = 12
        /// Buttons stretch full width, so only the vertical inset is specified.
        var buttonPadding = UIEdgeInsets(top: 16, left: 0, bottom: 16, right: 0)
        /// Inside the safe area — unlike the artwork, which runs under the notch.
        var closePadding: CGFloat = 8

        static let defaults = Fullscreen()
    }

    var modal = Modal.defaults
    var slideup = Slideup.defaults
    var fullscreen = Fullscreen.defaults

    static let defaults = MessageViewAttributes()
}
