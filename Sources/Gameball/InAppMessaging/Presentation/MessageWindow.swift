//
//  MessageWindow.swift
//  Gameball
//

import UIKit

/// The window a message is drawn in.
///
/// One touch rule, deliberately not a per-type branch: a touch is captured only when it
/// landed on the message view or something inside it. A slideup then passes touches through
/// automatically, because it occupies only its own band; a modal blocks them, because its
/// scrim is part of the message view. Adding a type check here would be the bug, not the fix.
final class MessageWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let current = node {
            if current is InAppMessageView { return hit }
            node = current.superview
        }
        return nil
    }
}
