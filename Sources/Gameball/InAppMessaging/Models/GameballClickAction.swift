//
//  GameballClickAction.swift
//  Gameball
//

import UIKit

/// What a tap on a message surface or button does.
///
/// `unsupported` carries the wire's type name so a diagnostic can say which action was
/// asked for. As with `GameballMessageType.unsupported`, it exists to make an unknown
/// action inert rather than fatal.
public enum GameballClickAction {
    case dismiss
    case openURL(url: URL, external: Bool)
    case navigate(route: String, arguments: [String: Any]?)

    /// Asks the OS for notification permission, then dismisses. The dashboard offers this
    /// as a button action so a campaign can be the moment that asks; it used to reach the
    /// device as `.unsupported` and the button would silently behave as a close button.
    case requestPushPermission
    case unsupported(type: String)
}

/// Per-button colours, each optional so an unstyled button inherits the host's theme
/// rather than a hardcoded literal that would clash with a dark-mode app.
public struct GameballButtonStyle {
    public let backgroundColor: UIColor?
    public let textColor: UIColor?
    public let borderColor: UIColor?
}

/// One tappable button on a modal or fullscreen message.
///
/// `id` is the dashboard's button identifier and is reported back with the click, so it
/// must survive parsing unchanged.
public struct GameballMessageButton {
    public let id: String
    public let text: String
    public let action: GameballClickAction
    public let style: GameballButtonStyle
}
