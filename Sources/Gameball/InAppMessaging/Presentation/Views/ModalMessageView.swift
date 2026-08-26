//
//  ModalMessageView.swift
//  Gameball
//

import UIKit

/// A centred card over a scrim, with copy and up to two buttons.
///
/// Fills the window, and the scrim is a subview rather than a separate window — which is what
/// makes `MessageWindow.hitTest` block the host without any per-type branch in the window.
final class ModalMessageView: UIView, InAppMessageView {

    weak var coordinator: MessageViewCoordinating?
    private(set) var presented = false

    private let message: GameballInAppMessage
    private let attributes: MessageViewAttributes.Modal
    /// The artwork and the constraint that sizes it.
    ///
    /// Resolved in `layoutSubviews` rather than declared, because the spec's rule is a literal
    /// `min()` of three quantities and Auto Layout cannot express one. Declaring it as a ratio
    /// plus two `<=` caps looks equivalent and is not: every term is relative to a width, so the
    /// solver can satisfy all three by shrinking the card — which it did, collapsing a 0.5 poster
    /// to a 40-point card.
    private var artwork: UIImageView?
    private var artworkHeight: NSLayoutConstraint?
    private var artworkRatio: CGFloat = 0
    private let image: UIImage?
    private let card = UIView()

    init(message: GameballInAppMessage,
         attributes: MessageViewAttributes,
         image: UIImage?,
         icon: UIImage?,
         coordinator: MessageViewCoordinating?) {
        self.message = message
        self.attributes = attributes.modal
        self.image = image
        self.coordinator = coordinator
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { return nil }

    private func build() {
        accessibilityIdentifier = GameballAccessibility.surface(for: .modal)
        backgroundColor = MessageTheme.scrim
        if message.dismissOnScrimTap {
            addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                        action: #selector(handleScrimTap)))
        }

        card.backgroundColor = message.style.backgroundColor ?? MessageTheme.background
        card.layer.cornerRadius = attributes.cornerRadius
        card.clipsToBounds = true
        if let border = message.style.borderColor {
            card.layer.borderColor = border.cgColor
            card.layer.borderWidth = 1
        }
        card.accessibilityIdentifier = GameballAccessibility.card
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let content = UIStackView()
        content.axis = .vertical
        // No spacing and no padding on the stack itself. The spec gives the copy block and the
        // button block their own insets (20/20/20/0 and 20/20/20/16), and the artwork sits flush
        // to the card's edges so its top corners round with it.
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false

        // Skipped entirely when the artwork failed to load, so a dead URL costs the picture
        // rather than the message.
        if let image = image {
            let imageView = UIImageView(image: image)
            // Contain: a hero image sits inside a card alongside copy, so it is never cropped and
        // never distorted. Marketing artwork routinely bakes text into the image, and cropping
        // here cuts it. The image-only compositions are the deliberate exception — they cover.
        imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            self.artwork = imageView
            if image.size.width > 0 && image.size.height > 0 {
                self.artworkRatio = image.size.width / image.size.height
            }
            let height = imageView.heightAnchor.constraint(equalToConstant: 0)
            height.isActive = true
            self.artworkHeight = height
            content.addArrangedSubview(imageView)
        }

        if let text = MessageTextBlock.make(header: message.header,
                                            body: message.body,
                                            headerTypography: .modalHeader,
                                            bodyTypography: .modalBody,
                                            headerColor: message.style.headerColor
                                                ?? message.style.textColor
                                                ?? MessageTheme.primaryText,
                                            bodyColor: message.style.textColor
                                                ?? MessageTheme.secondaryText,
                                            headerAlignment: message.style.headerAlignment.textAlignment,
                                            bodyAlignment: message.style.bodyAlignment.textAlignment,
                                            spacing: attributes.labelsSpacing) {
            content.addArrangedSubview(MessageInset.wrap(text, insets: attributes.padding))
        }

        if !message.buttons.isEmpty {
            let buttons = MessageButtonStack()
            buttons.axis = .horizontal
            // Trailing-aligned and sized to their labels, not stretched: a compact row at the
            // card's trailing edge is the dialog convention. Fullscreen stretches instead.
            buttons.distribution = .fill
            buttons.alignment = .fill
            buttons.spacing = attributes.buttonSpacing
            buttons.translatesAutoresizingMaskIntoConstraints = false
            for button in message.buttons {
                let view = MessageButtonView(button: button, style: button.style,
                                             typography: .modalButton,
                                             contentInsets: attributes.buttonPadding)
                view.onTap = { [weak self] tapped in
                    self?.process(action: tapped.action, buttonId: tapped.id)
                }
                buttons.addArrangedSubview(view)
            }
            let row = MessageInset.wrap(buttons, insets: attributes.buttonsPadding,
                                        alignment: .trailing)
            content.addArrangedSubview(row)
        }

        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        if message.showCloseButton {
            // Three cases, resolved here because only the view knows the background the glyph
            // will sit on. See `MessageTheme.closeGlyphColor`.
            let close = MessageCloseButton(
                tintColor: MessageTheme.closeGlyphColor(named: message.style.closeButtonColor,
                                                        background: message.style.backgroundColor))
            close.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
            card.addSubview(close)
            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: card.topAnchor,
                                           constant: attributes.closeInset),
                close.trailingAnchor.constraint(equalTo: card.trailingAnchor,
                                                constant: -attributes.closeInset)
            ])
        }
    }

    /// Sizes the artwork to the spec's rule, which is a `min()` of three quantities:
    ///
    /// * the artwork's **natural** height at the card's width — what it wants;
    /// * `cardWidth ÷ minImageRatio` — a **shape** cap, so the crossover at 0.55 is the same on
    ///   every device that has room for it;
    /// * `available − copyReserve` — a **floor** under the copy and the call to action, which on a
    ///   cramped screen binds before the shape does.
    ///
    /// Run here rather than declared because Auto Layout has no `min()`, and the obvious
    /// encoding — a ratio plus two `<=` caps — is satisfiable by shrinking the card instead.
    override func layoutSubviews() {
        super.layoutSubviews()

        guard let constraint = artworkHeight, artworkRatio > 0 else { return }
        let cardWidth = card.bounds.width
        guard cardWidth > 0 else { return }

        let available = bounds.height - attributes.margin.top - attributes.margin.bottom
        let natural = cardWidth / artworkRatio
        let shapeCap = cardWidth / attributes.minImageRatio
        let reserveCap = available - attributes.copyReserve

        let height = min(natural, min(shapeCap, reserveCap))
        // Guarded, or assigning inside a layout pass would loop forever.
        if abs(constraint.constant - height) > 0.5 {
            constraint.constant = height
            setNeedsLayout()
        }
    }

    func install(in container: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: container.topAnchor),
            bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        let guide = container.safeAreaLayoutGuide
        let width = card.widthAnchor.constraint(lessThanOrEqualToConstant: attributes.maxWidth)
        // The card takes the width the margins leave it, up to `maxWidth`. There is no minimum:
        // the spec has none, and one would push the card past the margin on a narrow device.
        // Just below required. On a cramped screen the copy and buttons can want a few points
        // more than `copyReserve` allows for — the spec says the reserve binds first there — and
        // the card absorbing that is better than the artwork losing a hundred points to it. The
        // required top and bottom margin inequalities still stop the card leaving the screen.
        let cardHeightCap = card.heightAnchor.constraint(
            lessThanOrEqualTo: guide.heightAnchor,
            constant: -(attributes.margin.top + attributes.margin.bottom))
        cardHeightCap.priority = UILayoutPriority(999)

        let preferred = card.widthAnchor.constraint(equalTo: guide.widthAnchor,
                                                    constant: -(attributes.margin.left
                                                                + attributes.margin.right))
        // Above the artwork's natural ratio, so the card's width is settled first and the artwork
        // clamps against it rather than the other way round.
        preferred.priority = UILayoutPriority(750)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            width,
            preferred,
            card.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor,
                                          constant: attributes.margin.left),
            card.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor,
                                           constant: -attributes.margin.right),
            card.topAnchor.constraint(greaterThanOrEqualTo: guide.topAnchor,
                                      constant: attributes.margin.top),
            card.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor,
                                         constant: -attributes.margin.bottom),
            cardHeightCap
        ])


    }

    func present(completion: (() -> Void)?) {
        willPresent()
        superview?.layoutIfNeeded()

        let settle = { [weak self] in
            guard let self = self else { return }
            self.presented = true
            self.didPresent()
            completion?()
        }

        guard !iamReduceMotionEnabled() else {
            alpha = 1
            card.transform = .identity
            settle()
            return
        }

        alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.2,
                       delay: 0,
                       options: [.curveEaseOut],
                       animations: {
                           self.alpha = 1
                           self.card.transform = .identity
                       },
                       completion: { _ in settle() })
    }

    func dismiss(completion: (() -> Void)?) {
        willDismiss()

        let finish = { [weak self] in
            guard let self = self else { return }
            self.presented = false
            self.didDismiss()
            completion?()
        }

        guard !iamReduceMotionEnabled() else {
            finish()
            return
        }

        UIView.animate(withDuration: 0.2,
                       delay: 0,
                       options: [.curveEaseIn],
                       animations: { self.alpha = 0 },
                       completion: { _ in finish() })
    }

    @objc private func handleClose() {
        dismiss(completion: nil)
    }

    /// Only reachable when the campaign asked for it — the recogniser is not installed
    /// otherwise, so an accidental tap outside the card cannot close a message the marketer
    /// wanted acknowledged.
    @objc private func handleScrimTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        guard !card.frame.contains(point) else { return }
        dismiss(completion: nil)
    }
}
