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
    static var scrim: UIColor {
        return UIColor.black.withAlphaComponent(0.45)
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
