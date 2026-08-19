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
    private let imageView = UIImageView()

    init(message: GameballInAppMessage,
         attributes: MessageViewAttributes,
         image: UIImage?,
         icon: UIImage?,
         coordinator: MessageViewCoordinating?) {
        self.message = message
        self.coordinator = coordinator
        super.init(frame: .zero)
        imageView.image = image
        build()
    }

    required init?(coder: NSCoder) { return nil }

    private func build() {
        backgroundColor = message.style.backgroundColor ?? MessageTheme.background

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
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        }

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

    @objc private func handleTap() {
        guard let action = message.clickAction else { return }
        process(action: action, buttonId: nil)
    }
}
