//
//  SlideupChevron.swift
//  Gameball
//

import UIKit

/// The trailing affordance on a tappable slideup.
///
/// Drawn rather than an SF Symbol so it behaves identically on iOS 11 and 12, where the SDK still
/// runs — the same reason the close glyph keeps a drawn fallback. It is a decoration, so it is
/// hidden from assistive technology: the banner itself is the accessibility element, and announcing
/// a chevron adds a control a screen-reader user cannot act on separately.
///
/// It **flips under right-to-left**, which is why the direction is read at draw time from the
/// effective layout direction rather than baked in.
final class SlideupChevron: UIView {

    private let color: UIColor
    private let size: CGFloat

    init(color: UIColor, size: CGFloat) {
        self.color = color
        self.size = size
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: size, height: size)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        // Read here, not in `init`: a view has no useful effective direction until it is in a
        // hierarchy, so resolving it earlier bakes in left-to-right and never mirrors.
        let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute)
            == .rightToLeft

        // Two insets, not one. A single value for both axes forces the glyph square, which puts
        // the arms at 26.6° and reads as a blunt `>`; half as wide as tall puts them at 45°,
        // matching the Android SDK's `gb_iam_ic_chevron`.
        let verticalInset = size / 4
        let horizontalInset = size * 3 / 8
        let near = rightToLeft ? size - horizontalInset : horizontalInset
        let far = rightToLeft ? horizontalInset : size - horizontalInset
        let top = CGPoint(x: near, y: verticalInset)
        let middle = CGPoint(x: far, y: size / 2)
        let bottom = CGPoint(x: near, y: size - verticalInset)

        let path = UIBezierPath()
        path.move(to: top)
        path.addLine(to: middle)
        path.addLine(to: bottom)
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
}
