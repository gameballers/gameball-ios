//
//  FullscreenImageMessageView.swift
//  Gameball
//

import UIKit

/// A full-bleed poster with no copy.
final class FullscreenImageMessageView: UIView, InAppMessageView {

    weak var coordinator: MessageViewCoordinating?
    private(set) var presented = false

    private let message: GameballInAppMessage
    private let attributes: MessageViewAttributes.Fullscreen
    private let imageView = UIImageView()

    init(message: GameballInAppMessage,
         attributes: MessageViewAttributes,
         image: UIImage?,
         icon: UIImage?,
         coordinator: MessageViewCoordinating?) {
        self.message = message
        self.attributes = attributes.fullscreen
        self.coordinator = coordinator
        super.init(frame: .zero)
        imageView.image = image
        build()
    }

    required init?(coder: NSCoder) { return nil }

    private func build() {
        accessibilityIdentifier = GameballAccessibility.surface(for: .fullscreen)
        backgroundColor = message.style.backgroundColor ?? MessageTheme.background

        // Cover, per the cross-platform UI spec. An image-only campaign is a poster: the artwork
        // is the whole message and it goes edge to edge, running under the notch and the home
        // indicator. Containing it would frame a poster inside bars, which is the one thing a
        // full-bleed composition exists not to do.
        //
        // This is the opposite of the hero image inside a modal card, which *is* contained — there
        // the copy carries the message and the artwork must not be cropped. The two rules look
        // contradictory and are not: what changes is whether the image is the message.
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = UIAccessibilityTraits.image
        imageView.accessibilityLabel = message.header ?? message.body
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        if message.clickAction != nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.delegate = self
            addGestureRecognizer(tap)
        }

        // Buttons, over the artwork. A poster drops its *copy* — that is the composition, and the
        // dashboard guards it so every platform agrees — but never its call to action, which on an
        // image-only campaign is the only affordance beyond a tap on the surface.
        //
        // Floated rather than stacked beneath: a full-bleed poster reaching every edge is the
        // whole point of this composition, and a row below the image would letterbox it.
        // Android does the same in `bindImageOnly`.
        if !message.buttons.isEmpty {
            let buttons = MessageButtonStack()
            // Stacked and stretched, as on the copy composition: a fullscreen surface has the room.
            buttons.axis = .vertical
            buttons.distribution = .fill
            buttons.alignment = .fill
            buttons.spacing = attributes.buttonSpacing
            buttons.translatesAutoresizingMaskIntoConstraints = false
            for button in message.buttons {
                let view = MessageButtonView(button: button, style: button.style,
                                             typography: .fullscreenButton,
                                             contentInsets: attributes.buttonPadding)
                view.onTap = { [weak self] tapped in
                    self?.process(action: tapped.action, buttonId: tapped.id)
                }
                buttons.addArrangedSubview(view)
            }
            addSubview(buttons)

            // Inside the safe area, unlike the artwork, which runs under the home indicator.
            let insets = attributes.imageOnlyButtonsPadding
            NSLayoutConstraint.activate([
                buttons.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor,
                                                 constant: insets.left),
                buttons.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor,
                                                  constant: -insets.right),
                buttons.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor,
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
                close.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
                close.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor,
                                                constant: -8)
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
        UIView.animate(withDuration: MessageMotion.fadeDuration,
                       delay: 0,
                       options: [.curveEaseOut],
                       animations: { self.alpha = 1 },
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
        // Immediate, per the spec: there is no exit animation on this type. A dismissal is a
        // decision the customer already made, and animating it out delays the app coming back.
        alpha = 0
        finish()
    }

    @objc private func handleClose() {
        dismiss(completion: nil)
    }

    @objc private func handleTap() {
        guard let action = message.clickAction else { return }
        process(action: action, buttonId: nil)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension FullscreenImageMessageView: UIGestureRecognizerDelegate {

    /// A tap that lands on a campaign button belongs to that button.
    ///
    /// Not merely a question of which action runs: a recogniser on the surface cancels the touch
    /// tracking of any control beneath it, so without this the button never fires at all and the
    /// tap is reported as a tap on the poster.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        return MessageButtonView.surfaceGestureShouldReceive(touchOn: touch.view)
    }
}
