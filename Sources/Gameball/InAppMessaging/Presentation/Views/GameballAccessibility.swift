//
//  GameballAccessibility.swift
//  Gameball
//

import Foundation

/// Accessibility identifiers for the parts of a message a UI test needs to reach.
///
/// Public and documented rather than internal: an integrator writing XCUITest against their own app
/// has no other stable handle on a message. Campaign copy is authored in the dashboard and changes
/// without a release, so finding a button by its title makes the test fail for a reason that has
/// nothing to do with the app.
///
/// These are identifiers, not labels — VoiceOver still reads the campaign's own text.
public enum GameballAccessibility {

    /// The message surface. For a modal or fullscreen this is the full-bleed view including the
    /// scrim; for a slideup it is the band itself.
    public static func surface(for type: GameballMessageType) -> String {
        switch type {
        case .slideup:     return "gameball.message.slideup"
        case .modal:       return "gameball.message.modal"
        case .fullscreen:  return "gameball.message.fullscreen"
        case .unsupported: return "gameball.message.unsupported"
        }
    }

    /// The card a modal draws inside its scrim. Absent on slideup and fullscreen.
    public static let card = "gameball.message.card"

    /// The close affordance, where the composition renders one.
    public static let closeButton = "gameball.message.close"

    /// A campaign button, keyed by the id the dashboard assigned it.
    public static func button(_ id: String) -> String {
        "gameball.message.button.\(id)"
    }
}
