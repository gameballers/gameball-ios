//
//  InAppMessageView.swift
//  Gameball
//

import UIKit

/// What a message view tells the orchestrator.
///
/// Named for the *view's* perspective rather than the service's, so a view never needs to
/// know what the other side does with the callback.
protocol MessageViewCoordinating: AnyObject {
    func viewWillPresent()
    /// The message is now on screen. This — not insertion — is the impression anchor.
    func viewDidPresent()
    func viewWillDismiss()
    func viewDidDismiss()
    func viewDidClick(buttonId: String?)
    func viewDidRequest(action: GameballClickAction, buttonId: String?)
}

/// A drawable message.
///
/// `coordinator` is a requirement rather than an extension property because it must be
/// `weak`, and a protocol extension cannot store — let alone store weakly.
protocol InAppMessageView: UIView {
    var presented: Bool { get }
    var coordinator: MessageViewCoordinating? { get }
    func present(completion: (() -> Void)?)
    func dismiss(completion: (() -> Void)?)
    /// Installs this view in the window's root view with the constraints its type needs.
    ///
    /// The view decides its own extent because `MessageWindow.hitTest` captures a touch
    /// only when it lands on the message view. A slideup must therefore occupy *only* its
    /// band — pinning every type to fill the root would make a slideup swallow every touch
    /// in the app and silently undo the passthrough rule.
    func install(in container: UIView)
}

/// Whether the platform is asking for reduced motion.
///
/// Indirected through a closure because `UIAccessibility.isReduceMotionEnabled` cannot be set
/// from a test, and "the entrance is skipped" is a rule worth asserting rather than assuming.
var iamReduceMotionEnabled: () -> Bool = { UIAccessibility.isReduceMotionEnabled }

extension InAppMessageView {

    /// The Human Interface Guidelines minimum. A close affordance below this is a message the
    /// customer cannot reliably escape.
    static var closeButtonMinimumTouchTargetSize: CGFloat { return 44 }

    func willPresent() {
        coordinator?.viewWillPresent()
    }

    /// Called when the entrance has finished, so the impression is anchored to the message
    /// actually being visible rather than to it being inserted into the hierarchy.
    func didPresent() {
        // Moves VoiceOver focus onto the message. Without this the screen reader stays on
        // whatever the host was reading and the message is effectively invisible.
        UIAccessibility.post(notification: UIAccessibility.Notification.screenChanged,
                             argument: self)
        coordinator?.viewDidPresent()
    }

    func willDismiss() {
        coordinator?.viewWillDismiss()
    }

    func didDismiss() {
        coordinator?.viewDidDismiss()
    }

    func logClick(buttonId: String?) {
        coordinator?.viewDidClick(buttonId: buttonId)
    }

    /// Every tap reports a click, including a tap on a dismiss button — engagement is
    /// engagement regardless of where it leads.
    func process(action: GameballClickAction, buttonId: String?) {
        logClick(buttonId: buttonId)
        coordinator?.viewDidRequest(action: action, buttonId: buttonId)
    }
}
