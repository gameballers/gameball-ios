//
//  MessageInset.swift
//  Gameball
//

import UIKit

/// Wraps a view in its own insets.
///
/// The spec gives the copy block and the button block separate padding — 20/20/20/0 and
/// 20/20/20/16 on a modal — rather than one padding for the card. A single inset on the enclosing
/// stack cannot express that, and putting the padding on the stack would also inset the artwork,
/// which is meant to run flush to the card's edges so its top corners round with them.
enum MessageInset {

    /// `alignment` controls the horizontal placement of `view` inside the padded box. `.fill` is
    /// the default; a modal's button row uses `.trailing`, which mirrors under right-to-left
    /// because it resolves through the leading/trailing anchors rather than left/right.
    enum Alignment {
        case fill
        case trailing
    }

    static func wrap(_ view: UIView,
                     insets: UIEdgeInsets,
                     alignment: Alignment = .fill) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)

        var constraints = [
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor,
                                         constant: -insets.bottom)
        ]

        switch alignment {
        case .fill:
            constraints += [
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                              constant: insets.left),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                               constant: -insets.right)
            ]
        case .trailing:
            constraints += [
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                               constant: -insets.right),
                view.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor,
                                              constant: insets.left)
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return container
    }
}
