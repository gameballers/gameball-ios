//
//  FullscreenMessageView.swift
//  Gameball
//

import UIKit

/// Artwork, copy and buttons filling the screen.
final class FullscreenMessageView: UIView, InAppMessageView {

    weak var coordinator: MessageViewCoordinating?
    private(set) var presented = false

    private let message: GameballInAppMessage
    private let attributes: MessageViewAttributes.Fullscreen
    private let image: UIImage?
    private var imageView: UIImageView?

    init(message: GameballInAppMessage,
         attributes: MessageViewAttributes,
         image: UIImage?,
         icon: UIImage?,
         coordinator: MessageViewCoordinating?) {
        self.message = message
        self.attributes = attributes.fullscreen
        self.image = image
        self.coordinator = coordinator
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { return nil }

    private func build() {
        accessibilityIdentifier = GameballAccessibility.surface(for: .fullscreen)
        backgroundColor = message.style.backgroundColor ?? MessageTheme.background

        let content = UIStackView()
        content.axis = .vertical
        // Zero, for the same reason as the modal: the copy block and the button block carry
        // their own insets (24/24/24/0 and 24/28/24/24), and the artwork runs flush.
        content.spacing = 0
        // Stated rather than inherited. `.fill` stretches whichever arranged view hugs least,
        // and this stack is pinned to both the top and the bottom of the screen — so on any
        // screen taller than its content, something is going to be stretched. Which one is
        // decided by the hugging priorities set below, not left to the UIKit default where the
        // copy and the buttons both sit at 250 and the winner is undefined.
        content.distribution = .fill
        content.translatesAutoresizingMaskIntoConstraints = false

        if let image = image {
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.translatesAutoresizingMaskIntoConstraints = false
            imageView = view
            content.addArrangedSubview(view)
        }

        if let text = MessageTextBlock.make(header: message.header,
                                            body: message.body,
                                            headerTypography: .fullscreenHeader,
                                            bodyTypography: .fullscreenBody,
                                            headerColor: message.style.headerColor
                                                ?? message.style.textColor
                                                ?? MessageTheme.primaryText,
                                            bodyColor: message.style.textColor
                                                ?? MessageTheme.secondaryText,
                                            headerAlignment: message.style.headerAlignment.textAlignment,
                                            bodyAlignment: message.style.bodyAlignment.textAlignment,
                                            spacing: attributes.labelsSpacing) {
            // The copy takes the slack, and takes it without anything set here: the block
            // carries its own `height == content` at priority 250, which is the lowest-priority
            // height constraint in the stack and so the first to yield. Setting hugging on it
            // would do nothing — a scroll view has no intrinsic size to hug.
            content.addArrangedSubview(MessageInset.wrap(text, insets: attributes.padding))
        }

        if !message.buttons.isEmpty {
            let buttons = MessageButtonStack()
            // Stacked and stretched full width, never side by side. A fullscreen surface has the
            // room, and the modal's compact trailing row looks lost at this size.
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
            content.addArrangedSubview(MessageInset.wrap(buttons,
                                                         insets: attributes.buttonsPadding))
        }

        addSubview(content)

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

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
        ])
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

        // Proportional rather than fixed, so the poster keeps its share of a small screen and
        // does not crowd the copy out.
        if let imageView = imageView {
            let height = imageView.heightAnchor.constraint(
                equalTo: container.heightAnchor,
                multiplier: attributes.imageHeightFraction)
            height.priority = UILayoutPriority(999)
            height.isActive = true
        }
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
}
