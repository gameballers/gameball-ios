//
//  IAMTestFactories.swift
//  GameballTests
//
//  Builders for the module's value types, so a test can state the one field it cares
//  about and stay readable. Defaults are deliberately *permissive* — a campaign built
//  with no arguments is selectable — so every test that expects nothing back has to say
//  which rule suppressed it.
//

import UIKit
@testable import Gameball

func makeStyle(backgroundColor: UIColor? = nil,
               textColor: UIColor? = nil) -> GameballMessageStyle {
    return GameballMessageStyle(backgroundColor: backgroundColor,
                                textColor: textColor,
                                headerColor: nil,
                                closeButtonColor: nil,
                                borderColor: nil,
                                frameColor: nil,
                                headerAlignment: .leading,
                                bodyAlignment: .leading)
}

func makeButton(id: String = "cta",
                text: String = "Tap me",
                action: GameballClickAction = .dismiss) -> GameballMessageButton {
    return GameballMessageButton(id: id,
                                 text: text,
                                 action: action,
                                 style: GameballButtonStyle(backgroundColor: nil,
                                                            textColor: nil,
                                                            borderColor: nil))
}

func makeMessage(id: String = "1",
                 type: GameballMessageType = .modal,
                 header: String? = "Header",
                 body: String? = "Body",
                 imageURL: URL? = nil,
                 iconURL: URL? = nil,
                 clickAction: GameballClickAction? = nil,
                 buttons: [GameballMessageButton] = [],
                 showCloseButton: Bool = true,
                 dismissOnScrimTap: Bool = true,
                 autoDismissAfter: TimeInterval? = nil,
                 layout: GameballMessageLayout = .textWithImage,
                 orientation: GameballMessageOrientation = .any,
                 slidePosition: GameballSlidePosition = .bottom,
                 extras: [String: Any] = [:],
                 style: GameballMessageStyle? = nil) -> GameballInAppMessage {
    return GameballInAppMessage(id: id,
                                type: type,
                                header: header,
                                body: body,
                                imageURL: imageURL,
                                iconURL: iconURL,
                                clickAction: clickAction,
                                buttons: buttons,
                                showCloseButton: showCloseButton,
                                dismissOnScrimTap: dismissOnScrimTap,
                                autoDismissAfter: autoDismissAfter,
                                layout: layout,
                                orientation: orientation,
                                slidePosition: slidePosition,
                                extras: extras,
                                style: style ?? makeStyle())
}

func makeCampaign(campaignId: Int = 1,
                  variationId: Int? = nil,
                  dispatchId: String? = "dispatch-1",
                  name: String? = "Campaign",
                  priority: Int = 0,
                  expiresAt: Date? = nil,
                  isTest: Bool = false,
                  repeatable: Bool = true,
                  minInterval: TimeInterval? = nil,
                  trigger: MessageTrigger = .sessionStart,
                  type: GameballMessageType = .modal,
                  message: GameballInAppMessage? = nil,
                  responseIndex: Int = 0) -> InAppMessageCampaign {
    return InAppMessageCampaign(
        campaignId: campaignId,
        variationId: variationId,
        dispatchId: dispatchId,
        name: name,
        priority: priority,
        expiresAt: expiresAt,
        isTest: isTest,
        repeatable: repeatable,
        minInterval: minInterval,
        trigger: trigger,
        message: message ?? makeMessage(id: "\(campaignId)", type: type),
        responseIndex: responseIndex
    )
}

/// Every campaign's artwork counts as ready. Passed explicitly by tests that are not about
/// artwork, so the evaluator's purity stays visible at the call site.
let artworkAlwaysReady: (InAppMessageCampaign) -> Bool = { _ in true }

/// Invokes a control's registered `.touchUpInside` actions directly.
///
/// `UIControl.sendActions(for:)` dispatches through `UIApplication.sendAction(_:to:from:for:)`,
/// which does not deliver inside a unit-test bundle — verified: a plain `UIButton` with one
/// registered target reports `allTargets.count == 1` and still never fires. Calling the
/// registered selectors is therefore the only reliable way to simulate a tap here.
func simulateTap(_ control: UIControl) {
    for target in control.allTargets {
        let selectors = control.actions(forTarget: target,
                                        forControlEvent: .touchUpInside) ?? []
        for name in selectors {
            let object = target as AnyObject
            let selector = Selector(name)
            guard object.responds(to: selector) else { continue }
            // A selector with no colon takes no argument; passing one would corrupt the frame.
            if name.contains(":") {
                _ = object.perform(selector, with: control)
            } else {
                _ = object.perform(selector)
            }
        }
    }
}
