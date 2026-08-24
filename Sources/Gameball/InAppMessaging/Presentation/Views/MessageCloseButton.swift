//
//  MessageCloseButton.swift
//  Gameball
//

import UIKit

/// A 44×44 close affordance with a vector glyph.
///
/// Drawn rather than shipped as an asset: the SDK carries no image bundle, and a stroked path
/// stays crisp at every scale and tints to whatever the campaign asked for. The 44pt floor is
/// the Human Interface Guidelines minimum — below it the customer cannot reliably escape.
final class MessageCloseButton: UIButton {

    private let glyphColor: UIColor

    init(tintColor: UIColor?) {
        self.glyphColor = tintColor ?? MessageTheme.secondaryText
        super.init(frame: .zero)

        backgroundColor = .clear
        isOpaque = false
        accessibilityLabel = "Close"
        // Stable across campaigns, so a host UI test can find it without knowing the copy.
        accessibilityIdentifier = GameballAccessibility.closeButton
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 44, height: 44)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        // A 16pt cross centred in the 44pt target: the touch area stays large while the glyph
        // stays visually light.
        let side: CGFloat = 16
        let origin = CGPoint(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2)

        let path = UIBezierPath()
        path.move(to: origin)
        path.addLine(to: CGPoint(x: origin.x + side, y: origin.y + side))
        path.move(to: CGPoint(x: origin.x + side, y: origin.y))
        path.addLine(to: CGPoint(x: origin.x, y: origin.y + side))

        path.lineWidth = 2
        path.lineCapStyle = .round
        glyphColor.setStroke()
        path.stroke()
    }
}
