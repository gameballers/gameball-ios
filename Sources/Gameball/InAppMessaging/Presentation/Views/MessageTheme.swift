//
//  MessageTheme.swift
//  Gameball
//

import UIKit

/// Fallbacks for colours a campaign did not specify.
///
/// Every value is a *semantic* system colour where the platform has one, so an unstyled
/// message follows the host's light/dark appearance instead of being painted a literal that
/// looks correct in exactly one of them. This is why the parser resolves an unspecified
/// colour to nil rather than to a default.
enum MessageTheme {

    static var background: UIColor {
        if #available(iOS 13.0, *) { return .systemBackground }
        return .white
    }

    static var primaryText: UIColor {
        if #available(iOS 13.0, *) { return .label }
        return .black
    }

    static var secondaryText: UIColor {
        if #available(iOS 13.0, *) { return .secondaryLabel }
        return UIColor(white: 0.36, alpha: 1)
    }

    static var accent: UIColor {
        if #available(iOS 13.0, *) { return .link }
        return UIColor(red: 0, green: 0.48, blue: 1, alpha: 1)
    }

    static var onAccent: UIColor {
        return .white
    }

    /// Dimming behind a modal. Deliberately not opaque: the customer should still see that
    /// the app is there, so the message reads as temporary.
    ///
    /// 60% is a `Constant` in the UI spec's sense — `0x99000000`, identical on every platform.
    /// It is also the only scrim in production: `colors.frame` is null on every live campaign.
    static var scrim: UIColor {
        return UIColor.black.withAlphaComponent(0.6)
    }

    // MARK: - The close glyph

    /// The dark half of the close-glyph pair. Load-bearing, not decorative.
    static let closeGlyphOnLight = UIColor(red: 0x11 / 255, green: 0x18 / 255,
                                          blue: 0x27 / 255, alpha: 1)

    /// The light half.
    static let closeGlyphOnDark = UIColor.white

    /// Where the two change places: the relative luminance at which black and white contrast
    /// equally. Derived, not chosen — it is `sqrt(1.05 × 0.05) − 0.05`.
    static let closeGlyphLuminanceThreshold: CGFloat = 0.179

    /// Resolves the close glyph's colour in three cases, in order.
    ///
    /// 1. The campaign named one — use it verbatim, readable or not. Substituting something more
    ///    legible is how a brand colour becomes a colour nobody chose.
    /// 2. The campaign named a background — pick whichever half of the constant pair contrasts
    ///    with it. Worst case, at the threshold itself, is 3.8:1, against WCAG 2.1's 3:1 for a
    ///    non-text control.
    /// 3. Neither — defer to the platform's on-surface colour, which already contrasts with the
    ///    surface it sits on.
    ///
    /// There is no fourth case, and nothing here consults the artwork. An earlier rule keyed the
    /// colour off whether the message *had* artwork, which was wrong twice over: a contained
    /// portrait image letterboxes, so the glyph usually sits on card background anyway, and naming
    /// `closeButton` switched the contrast treatment off — making the one field a marketer is most
    /// likely to touch the one that could hide the control.
    static func closeGlyphColor(named: UIColor?, background: UIColor?) -> UIColor {
        if let named = named { return named }
        guard let background = background,
              let luminance = relativeLuminance(of: background) else { return primaryText }
        return luminance > closeGlyphLuminanceThreshold ? closeGlyphOnLight : closeGlyphOnDark
    }

    /// WCAG 2.1 relative luminance. `nil` when the colour is not in a component-readable space —
    /// a pattern colour, say — which falls through to the host theme rather than guessing.
    ///
    /// Alpha is read but not composited: a translucent campaign background sits over app content
    /// the SDK cannot see, so its own channels are the only evidence available.
    static func relativeLuminance(of color: UIColor) -> CGFloat? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        func linear(_ channel: CGFloat) -> CGFloat {
            return channel <= 0.03928 ? channel / 12.92
                                      : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

extension GameballTextAlignment {
    /// `.natural` for leading, deliberately.
    ///
    /// A view builds itself before it joins a hierarchy, so its `traitCollection` still reports
    /// the default direction at that moment — resolving leading to `.left` there would bake in
    /// left-to-right and never mirror. `.natural` defers the decision to draw time, which is the
    /// only point at which the answer is known. Only `trailing` needs an explicit direction, and
    /// it reads the app's, because layout direction comes from the locale rather than the view.
    var textAlignment: NSTextAlignment {
        switch self {
        case .leading:
            return .natural
        case .center:
            return .center
        case .trailing:
            let rightToLeft = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
            return rightToLeft ? .left : .right
        }
    }
}
