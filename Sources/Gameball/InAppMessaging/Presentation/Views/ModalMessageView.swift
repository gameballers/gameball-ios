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
        content.spacing = attributes.spacing
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
            imageView.heightAnchor.constraint(equalToConstant: attributes.imageHeight).isActive = true
            content.addArrangedSubview(imageView)
        }

        if let text = MessageTextBlock.make(header: message.header,
                                            body: message.body,
                                            headerFont: attributes.headerFont,
                                            bodyFont: attributes.bodyFont,
                                            headerColor: message.style.headerColor
                                                ?? message.style.textColor
                                                ?? MessageTheme.primaryText,
                                            bodyColor: message.style.textColor
                                                ?? MessageTheme.secondaryText,
                                            headerAlignment: message.style.headerAlignment.textAlignment,
                                            bodyAlignment: message.style.bodyAlignment.textAlignment,
                                            spacing: attributes.labelsSpacing) {
            content.addArrangedSubview(text)
        }

        if !message.buttons.isEmpty {
            let buttons = MessageButtonStack()
            buttons.axis = .horizontal
            buttons.distribution = .fillEqually
            buttons.spacing = 12
            buttons.translatesAutoresizingMaskIntoConstraints = false
            for button in message.buttons {
                let view = MessageButtonView(button: button, style: button.style)
                view.onTap = { [weak self] tapped in
                    self?.process(action: tapped.action, buttonId: tapped.id)
                }
                buttons.addArrangedSubview(view)
            }
            content.addArrangedSubview(buttons)
        }

        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor,
                                         constant: attributes.padding.top),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor,
                                            constant: -attributes.padding.bottom),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor,
                                             constant: attributes.padding.left),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor,
                                              constant: -attributes.padding.right)
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
        // Preferred width, yielding to the screen on a device narrower than `minWidth`.
        let preferred = card.widthAnchor.constraint(greaterThanOrEqualToConstant: attributes.minWidth)
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
            card.heightAnchor.constraint(lessThanOrEqualToConstant: attributes.maxHeight)
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
