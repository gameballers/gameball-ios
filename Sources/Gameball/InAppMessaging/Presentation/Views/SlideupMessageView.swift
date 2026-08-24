//
//  SlideupMessageView.swift
//  Gameball
//

import UIKit

/// A non-blocking band at the top or bottom of the screen.
///
/// Occupies only its band, never the whole window — that extent is what makes
/// `MessageWindow.hitTest` pass the rest of the screen through to the host. No scrim, no
/// buttons: the whole surface is the affordance, and a swipe along its own edge dismisses it.
final class SlideupMessageView: UIView, InAppMessageView {

    weak var coordinator: MessageViewCoordinating?
    private(set) var presented = false

    private let message: GameballInAppMessage
    private let attributes: MessageViewAttributes.Slideup
    private let icon: UIImage?

    init(message: GameballInAppMessage,
         attributes: MessageViewAttributes,
         image: UIImage?,
         icon: UIImage?,
         coordinator: MessageViewCoordinating?) {
        self.message = message
        self.attributes = attributes.slideup
        self.icon = icon
        self.coordinator = coordinator
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { return nil }

    // MARK: - Composition

    private func build() {
        accessibilityIdentifier = GameballAccessibility.surface(for: .slideup)
        backgroundColor = message.style.backgroundColor ?? MessageTheme.background
        layer.cornerRadius = attributes.cornerRadius
        clipsToBounds = true
        // A slideup floats, so it needs its own separation from whatever is behind it.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.masksToBounds = false

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = attributes.spacing
        row.translatesAutoresizingMaskIntoConstraints = false

        if let icon = icon {
            let imageView = UIImageView(image: icon)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 6
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: attributes.iconSize.width),
                imageView.heightAnchor.constraint(equalToConstant: attributes.iconSize.height)
            ])
            row.addArrangedSubview(imageView)
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
            row.addArrangedSubview(text)
        }

        addSubview(row)
        // Directional anchors only. Assigning `semanticContentAttribute` here is what leaked
        // right-to-left layout into host apps in 3.2.1.
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: attributes.padding.top),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -attributes.padding.bottom),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: attributes.padding.left),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -attributes.padding.right)
        ])

        if message.clickAction != nil {
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        isAccessibilityElement = false
        accessibilityElements = [row]
    }

    func install(in container: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)

        let guide = container.safeAreaLayoutGuide
        var constraints = [
            leadingAnchor.constraint(equalTo: guide.leadingAnchor,
                                     constant: attributes.margin.left),
            trailingAnchor.constraint(equalTo: guide.trailingAnchor,
                                      constant: -attributes.margin.right),
            // A band, not a panel. Beyond this it stops reading as non-blocking.
            heightAnchor.constraint(lessThanOrEqualToConstant: attributes.maxHeight)
        ]
        switch message.slidePosition {
        case .top:
            constraints.append(topAnchor.constraint(equalTo: guide.topAnchor,
                                                    constant: attributes.margin.top))
        case .bottom:
            constraints.append(bottomAnchor.constraint(equalTo: guide.bottomAnchor,
                                                       constant: -attributes.margin.bottom))
        }
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Lifecycle

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
            transform = .identity
            settle()
            return
        }

        transform = offscreenTransform()
        UIView.animate(withDuration: 0.2,
                       delay: 0,
                       options: [.curveEaseOut],
                       animations: { self.transform = .identity },
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
                       animations: {
                           self.transform = self.offscreenTransform()
                           self.alpha = 0
                       },
                       completion: { _ in finish() })
    }

    private func offscreenTransform() -> CGAffineTransform {
        let distance = max(bounds.height, 1) + attributes.margin.top + attributes.margin.bottom
        return CGAffineTransform(translationX: 0,
                                 y: message.slidePosition == .top ? -distance : distance)
    }

    // MARK: - Gestures

    @objc private func handleTap() {
        guard let action = message.clickAction else { return }
        process(action: action, buttonId: nil)
    }

    /// Restricted to the band's own edge axis, so it cannot fight a host scroll view: a
    /// downward drag on a bottom slideup dismisses, an upward one does nothing.
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self).y
        let outward = message.slidePosition == .top ? min(translation, 0) : max(translation, 0)

        switch gesture.state {
        case .changed:
            transform = CGAffineTransform(translationX: 0, y: outward)
        case .ended, .cancelled:
            if abs(outward) > bounds.height / 3 {
                dismiss(completion: nil)
            } else {
                UIView.animate(withDuration: 0.15) { self.transform = .identity }
            }
        default:
            break
        }
    }
}
