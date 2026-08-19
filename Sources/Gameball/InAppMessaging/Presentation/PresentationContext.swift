//
//  PresentationContext.swift
//  Gameball
//

import UIKit

/// Everything the presenter needs to put one message on screen.
struct PresentationContext {
    var message: GameballInAppMessage
    var attributes: MessageViewAttributes
    /// `.normal`, deliberately. Above that the message would cover system UI such as the
    /// status bar and call banner.
    var windowLevel: UIWindow.Level
    var preferredOrientation: UIInterfaceOrientation
    /// A `UIWindowScene` on iOS 13+, cast at the point of use so the type is not referenced
    /// on a platform that predates it.
    var windowScene: Any?

    init(message: GameballInAppMessage,
         attributes: MessageViewAttributes = .defaults,
         windowLevel: UIWindow.Level = .normal,
         preferredOrientation: UIInterfaceOrientation = .portrait,
         windowScene: Any? = nil) {
        self.message = message
        self.attributes = attributes
        self.windowLevel = windowLevel
        self.preferredOrientation = preferredOrientation
        self.windowScene = windowScene
    }
}

/// What the presenter calls back on. Separate from the coordinator protocol because these are
/// closures owned by one presentation, not a long-lived delegate.
struct PresentationHandlers {
    let onShown: () -> Void
    let onButtonPressed: (GameballMessageButton) -> Void
    let onMessagePressed: () -> Void
    let onDismissed: () -> Void
}

/// Why a presentation could not happen now.
///
/// Returned rather than thrown, because the return value is what feeds the deferral stack —
/// every one of these is "try again later", not "this failed".
enum PresentationObstacle {
    case noSurface
    case alreadyShowing
    case notMainThread
}

protocol MessagePresenting: AnyObject {
    var isShowing: Bool { get }
    func present(context: PresentationContext,
                 handlers: PresentationHandlers) -> PresentationObstacle?
    func dismiss()
}
