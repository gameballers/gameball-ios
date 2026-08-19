//
//  MessageViewFactory.swift
//  Gameball
//

import UIKit

/// Chooses the composition for a message.
///
/// Not in the plan's file list, but the presenter takes a view factory and something has to own
/// this mapping. Keeping it out of the presenter is what lets the presenter be tested with a
/// stub view instead of five real ones.
enum MessageViewFactory {

    static func make(context: PresentationContext,
                     image: UIImage?,
                     icon: UIImage?,
                     coordinator: MessageViewCoordinating?) -> InAppMessageView? {
        let message = context.message
        let attributes = context.attributes

        // `image_only` with no usable artwork would draw an empty card, so it falls back to the
        // copy composition. The parser has already guaranteed there is something to render.
        let imageOnly = message.layout == .imageOnly && image != nil

        switch message.type {
        case .slideup:
            return SlideupMessageView(message: message, attributes: attributes,
                                      image: image, icon: icon, coordinator: coordinator)

        case .modal:
            if imageOnly {
                return ModalImageMessageView(message: message, attributes: attributes,
                                             image: image, icon: icon, coordinator: coordinator)
            }
            return ModalMessageView(message: message, attributes: attributes,
                                    image: image, icon: icon, coordinator: coordinator)

        case .fullscreen:
            if imageOnly {
                return FullscreenImageMessageView(message: message, attributes: attributes,
                                                  image: image, icon: icon,
                                                  coordinator: coordinator)
            }
            return FullscreenMessageView(message: message, attributes: attributes,
                                         image: image, icon: icon, coordinator: coordinator)

        case .unsupported:
            // Reached only if the evaluator's filter was bypassed; never fatal.
            iamLog("no view exists for an unsupported message type")
            return nil
        }
    }
}
