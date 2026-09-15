//
//  MessageMotion.swift
//  Gameball
//

import UIKit

/// Entrance timings, from the cross-platform UI spec.
///
/// Durations and curves are `Constant`s in the spec's sense: the same campaign should arrive on
/// screen the same way on every platform. `UIView.animate`'s `.curveEaseOut` is *not* the same
/// shape as `easeOutCubic`, so the cubic control points are given explicitly — a named option per
/// platform is precisely how two SDKs end up feeling different while both claiming "ease out".
enum MessageMotion {

    /// Modal and fullscreen.
    static let fadeDuration: TimeInterval = 0.2
    /// Slideup — slightly longer, because it travels rather than just appearing.
    static let slideDuration: TimeInterval = 0.22

    /// `cubic-bezier(0.215, 0.61, 0.355, 1)` — the standard easeOutCubic.
    static let easeOutCubic = (first: CGPoint(x: 0.215, y: 0.61),
                               second: CGPoint(x: 0.355, y: 1))

    /// Runs `animations` on the spec's cubic curve, then `completion`.
    ///
    /// Uses `UIViewPropertyAnimator` rather than `UIView.animate` because only the former takes
    /// arbitrary control points. Falls straight through when reduce-motion is on: the message must
    /// still appear, just without travelling.
    static func animate(duration: TimeInterval,
                        animations: @escaping () -> Void,
                        completion: @escaping () -> Void) {
        guard !iamReduceMotionEnabled() else {
            animations()
            completion()
            return
        }
        let animator = UIViewPropertyAnimator(duration: duration,
                                              controlPoint1: easeOutCubic.first,
                                              controlPoint2: easeOutCubic.second,
                                              animations: animations)
        animator.addCompletion { _ in completion() }
        animator.startAnimation()
    }
}
