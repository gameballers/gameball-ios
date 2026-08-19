//
//  GameballMessageType.swift
//  Gameball
//

import Foundation

/// The presentation family a campaign belongs to.
///
/// `unsupported` is not an error case — it is how forward compatibility works. Types the
/// backend may start sending (HTML fullscreen, email capture) must arrive as a harmless
/// no-op on an older SDK, so an unrecognised value is *kept* as a campaign and skipped at
/// selection instead of dropping the payload.
public enum GameballMessageType {
    case slideup
    case modal
    case fullscreen
    case unsupported

    /// Maps the wire's numeric message type.
    ///
    /// 4 and 5 are out of scope by design, and anything higher does not exist yet; all of
    /// them land on `unsupported`.
    init(rawValue: Int) {
        switch rawValue {
        case 1:  self = .slideup
        case 2:  self = .modal
        case 3:  self = .fullscreen
        default: self = .unsupported
        }
    }
}

/// Whether a message composes copy alongside its artwork, or is artwork alone.
///
/// Two genuinely different compositions rather than one with the labels hidden.
public enum GameballMessageLayout {
    case textWithImage
    case imageOnly
}

/// The orientations a message is authored to support.
public enum GameballMessageOrientation {
    case portrait
    case landscape
    case any
}

/// Which edge a slideup enters from and rests against.
public enum GameballSlidePosition {
    case top
    case bottom
}
