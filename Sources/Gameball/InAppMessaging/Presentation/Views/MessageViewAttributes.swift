//
//  MessageViewAttributes.swift
//  Gameball
//

import UIKit

/// Per-type layout and typography constants.
///
/// Values, not a themeable API: they are `internal` and exist so the five views do not carry
/// magic numbers. Fonts are all `preferredFont(forTextStyle:)`, so Dynamic Type works without
/// any view opting in.
struct MessageViewAttributes {

    struct Modal {
        var margin = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        var padding = UIEdgeInsets(top: 40, left: 25, bottom: 30, right: 25)
        var labelsSpacing: CGFloat = 10
        var spacing: CGFloat = 20
        var cornerRadius: CGFloat = 8
        var minWidth: CGFloat = 320
        var maxWidth: CGFloat = 450
        var maxHeight: CGFloat = 720
        var headerFont = UIFont.preferredFont(forTextStyle: .title3)
        var bodyFont = UIFont.preferredFont(forTextStyle: .subheadline)
        var imageHeight: CGFloat = 160
        /// From the card's top trailing corner.
        var closeInset: CGFloat = 4

        static let defaults = Modal()
    }

    struct Slideup {
        var margin = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        var padding = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        var iconSize = CGSize(width: 40, height: 40)
        var spacing: CGFloat = 12
        var labelsSpacing: CGFloat = 2
        var cornerRadius: CGFloat = 10
        /// A slideup is a band, not a panel. Beyond this it stops reading as non-blocking.
        var maxHeight: CGFloat = 120
        var headerFont = UIFont.preferredFont(forTextStyle: .subheadline)
        var bodyFont = UIFont.preferredFont(forTextStyle: .footnote)

        static let defaults = Slideup()
    }

    struct Fullscreen {
        var padding = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        var spacing: CGFloat = 20
        var labelsSpacing: CGFloat = 12
        var imageHeightFraction: CGFloat = 0.45
        var headerFont = UIFont.preferredFont(forTextStyle: .title1)
        var bodyFont = UIFont.preferredFont(forTextStyle: .body)

        static let defaults = Fullscreen()
    }

    var modal = Modal.defaults
    var slideup = Slideup.defaults
    var fullscreen = Fullscreen.defaults

    static let defaults = MessageViewAttributes()
}
