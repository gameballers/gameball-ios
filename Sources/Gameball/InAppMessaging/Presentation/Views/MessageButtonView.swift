//
//  MessageButtonView.swift
//  Gameball
//

import UIKit

/// One campaign button.
final class MessageButtonView: UIButton {

    private let button: GameballMessageButton
    var onTap: ((GameballMessageButton) -> Void)?

    init(button: GameballMessageButton,
         style: GameballButtonStyle,
         typography: MessageTypography = .modalButton,
         contentInsets: UIEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)) {
        self.button = button
        super.init(frame: .zero)

        setTitle(button.text, for: .normal)
        setTitleColor(style.textColor ?? MessageTheme.onAccent, for: .normal)
        backgroundColor = style.backgroundColor ?? MessageTheme.accent

        // Only when the campaign named one. There is no default outline — an unstyled button is a
        // bare text button in the host's primary colour, which is what every live campaign renders
        // as today.
        if let border = style.borderColor {
            layer.borderColor = border.cgColor
            layer.borderWidth = 1
        }
        layer.cornerRadius = MessageViewAttributes.buttonCornerRadius

        accessibilityIdentifier = GameballAccessibility.button(button.id)
        titleLabel?.font = typography.font()
        titleLabel?.adjustsFontForContentSizeCategory = true
        // Wrapping rather than truncating: a button whose label is cut off is a button whose
        // consequence is a guess.
        titleLabel?.numberOfLines = 0
        titleLabel?.textAlignment = .center

        contentEdgeInsets = contentInsets
        translatesAutoresizingMaskIntoConstraints = false
        // The insets already carry the spec's height; this is the accessibility floor beneath it.
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        // A call to action is sized by its label. Without this it is sized by whatever is left
        // over: in the fullscreen composition the content stack is pinned to both the top and
        // the bottom of the screen, and the button was the view that absorbed the difference —
        // 69% of a 667pt screen with no artwork, 26% with.
        //
        // It has to be set *here* rather than on the enclosing stack. Content hugging only
        // produces a constraint where there is an intrinsic size to hug, and `UIStackView` and
        // `UIScrollView` have none — so hugging set on either of those is silently inert. This
        // button has an intrinsic height, so `.required` here becomes a real `height <=
        // intrinsic` that a parent's fill distribution cannot override.
        setContentHuggingPriority(.required, for: .vertical)

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { return nil }

    @objc private func handleTap() {
        onTap?(button)
    }
}

/// A stack that turns vertical when its buttons will not fit side by side.
///
/// Wrapping instead of overflowing matters most in the cases nobody previews: a long label, a
/// narrow device, or an accessibility text size. Any of the three otherwise pushes a button
/// off the edge of the card.
final class MessageButtonStack: UIStackView {

    override func layoutSubviews() {
        let available = bounds.width
        if available > 0 && !arrangedSubviews.isEmpty {
            let widths = arrangedSubviews.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width }
            let gaps = spacing * CGFloat(max(0, arrangedSubviews.count - 1))
            let wanted: NSLayoutConstraint.Axis = (widths + gaps > available) ? .vertical : .horizontal
            // Guarded, or assigning inside a layout pass would loop forever.
            if axis != wanted { axis = wanted }
        }
        super.layoutSubviews()
    }
}
