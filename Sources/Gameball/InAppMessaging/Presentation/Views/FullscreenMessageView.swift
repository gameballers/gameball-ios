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
        backgroundColor = message.style.backgroundColor ?? MessageTheme.background

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = attributes.spacing
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

        addSubview(content)

        if message.showCloseButton {
            let close = MessageCloseButton(tintColor: message.style.closeButtonColor)
            close.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
            addSubview(close)
            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
                close.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor,
                                                constant: -8)
            ])
        }

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor,
                                         constant: attributes.padding.top),
            content.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor,
                                            constant: -attributes.padding.bottom),
            content.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor,
                                             constant: attributes.padding.left),
            content.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor,
                                              constant: -attributes.padding.right)
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
