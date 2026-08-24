//
//  ModalImageMessageView.swift
//  Gameball
//

import UIKit

/// A centred artwork card over a scrim, with no copy.
///
/// A separate class from `ModalMessageView` rather than the same one with the labels hidden:
/// `image_only` is a different composition — the artwork sizes the card instead of sitting
/// above text, so the constraints are not the same shape.
final class ModalImageMessageView: UIView, InAppMessageView {

    weak var coordinator: MessageViewCoordinating?
    private(set) var presented = false

    private let message: GameballInAppMessage
    private let attributes: MessageViewAttributes.Modal
    private let card = UIView()
    private let imageView = UIImageView()

    init(message: GameballInAppMessage,
         attributes: MessageViewAttributes,
         image: UIImage?,
         icon: UIImage?,
         coordinator: MessageViewCoordinating?) {
        self.message = message
        self.attributes = attributes.modal
        self.coordinator = coordinator
        super.init(frame: .zero)
        imageView.image = image
        build()
    }

    required init?(coder: NSCoder) { return nil }

    private func build() {
        accessibilityIdentifier = GameballAccessibility.surface(for: .modal)
        backgroundColor = MessageTheme.scrim
        if message.dismissOnScrimTap {
            addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                        action: #selector(handleScrimTap(_:))))
        }

        card.layer.cornerRadius = attributes.cornerRadius
        card.clipsToBounds = true
        card.backgroundColor = message.style.backgroundColor ?? MessageTheme.background
        card.accessibilityIdentifier = GameballAccessibility.card
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = UIAccessibilityTraits.image
        imageView.accessibilityLabel = message.header ?? message.body
        imageView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: card.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        if message.clickAction != nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleCardTap))
            card.addGestureRecognizer(tap)
            card.isUserInteractionEnabled = true
        }

        if message.showCloseButton {
            let close = MessageCloseButton(tintColor: message.style.closeButtonColor)
            close.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
            addSubview(close)
            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: card.topAnchor),
                close.trailingAnchor.constraint(equalTo: card.trailingAnchor)
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
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor,
                                          constant: attributes.margin.left),
            card.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor,
                                           constant: -attributes.margin.right),
            card.topAnchor.constraint(greaterThanOrEqualTo: guide.topAnchor,
                                      constant: attributes.margin.top),
            card.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor,
                                         constant: -attributes.margin.bottom),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: attributes.maxWidth),
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
            settle()
            return
        }

        alpha = 0
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 1 },
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
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 },
                       completion: { _ in finish() })
    }

    @objc private func handleClose() {
        dismiss(completion: nil)
    }

    @objc private func handleCardTap() {
        guard let action = message.clickAction else { return }
        process(action: action, buttonId: nil)
    }

    @objc private func handleScrimTap(_ gesture: UITapGestureRecognizer) {
        guard !card.frame.contains(gesture.location(in: self)) else { return }
        dismiss(completion: nil)
    }
}
