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
            let scrim = UITapGestureRecognizer(target: self, action: #selector(handleScrimTap(_:)))
            scrim.delegate = self
            addGestureRecognizer(scrim)
        }

        card.layer.cornerRadius = attributes.cornerRadius
        card.clipsToBounds = true
        card.backgroundColor = message.style.backgroundColor ?? MessageTheme.background
        card.accessibilityIdentifier = GameballAccessibility.card
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        imageView.contentMode = .scaleAspectFill
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
            tap.delegate = self
            card.addGestureRecognizer(tap)
            card.isUserInteractionEnabled = true
        }

        // Buttons, over the artwork. A poster drops its *copy* — the composition, guarded in the
        // dashboard so every platform agrees — but never its call to action. Android does the same
        // in `bindImageOnly`.
        if !message.buttons.isEmpty {
            let buttons = MessageButtonStack()
            // Trailing-aligned and sized to their labels, as on the copy composition: a compact row
            // is the dialog convention, and `MessageButtonStack` wraps to a column when it must.
            buttons.axis = .horizontal
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
            card.addSubview(buttons)

            let insets = attributes.imageOnlyButtonsPadding
            NSLayoutConstraint.activate([
                buttons.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor,
                                                 constant: insets.left),
                buttons.trailingAnchor.constraint(equalTo: card.trailingAnchor,
                                                  constant: -insets.right),
                buttons.bottomAnchor.constraint(equalTo: card.bottomAnchor,
                                                constant: -insets.bottom)
            ])
        }

        if message.showCloseButton {
            // Three cases, resolved here because only the view knows the background the glyph
            // will sit on. See `MessageTheme.closeGlyphColor`.
            let close = MessageCloseButton(
                tintColor: MessageTheme.closeGlyphColor(named: message.style.closeButtonColor,
                                                        background: message.style.backgroundColor))
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
            // The artwork is the whole card here, so its cap is a share of the screen rather
            // than the copy reserve — past 65% the artwork crops instead of the card growing.
            card.heightAnchor.constraint(lessThanOrEqualTo: guide.heightAnchor,
                                         multiplier: attributes.imageOnlyHeightFraction)
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
        MessageMotion.animate(duration: MessageMotion.fadeDuration,
                              animations: { self.alpha = 1 },
                              completion: settle)
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
        // Immediate, per the spec: there is no exit animation on this type. A dismissal is a
        // decision the customer already made, and animating it out delays the app coming back.
        alpha = 0
        finish()
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


// MARK: - UIGestureRecognizerDelegate

extension ModalImageMessageView: UIGestureRecognizerDelegate {

    /// A tap that lands on a campaign button belongs to that button.
    ///
    /// Both recognisers here sit above the buttons — the scrim's on this view, the card's on the
    /// card — and either would cancel a button's touch tracking, leaving it inert.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        return MessageButtonView.surfaceGestureShouldReceive(touchOn: touch.view)
    }
}
