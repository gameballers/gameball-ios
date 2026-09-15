//
//  MessageCloseButton.swift
//  Gameball
//

import UIKit

/// The close affordance: a 24pt glyph centred in a 48×48 target, with no disc, ring or shadow.
///
/// The two sizes are deliberately separate numbers. 48 is the accessibility minimum on both
/// platforms (48dp Android, 44pt iOS) and is what the finger hits; 24 is what the customer sees.
/// Collapsing them into one value gives you either a glyph too big for the corner or a target too
/// small to hit.
///
/// Nothing sits behind the glyph. All of its contrast comes from its own colour, resolved by
/// `MessageTheme.closeGlyphColor` — which is why that resolution has to be right. A plate would
/// make it moot and would add a surface the campaign never asked for.
final class MessageCloseButton: UIButton {

    /// The glyph, not the target.
    static let glyphSize: CGFloat = 24

    /// The touch target. 48 rather than 44: it satisfies both platforms with one number, which is
    /// what the cross-platform spec asks for.
    static let targetSize: CGFloat = 48

    private let glyphColor: UIColor

    /// `tintColor` is the already-resolved glyph colour — the caller owns the three-case
    /// resolution, because only it knows the campaign's background.
    init(tintColor: UIColor?) {
        self.glyphColor = tintColor ?? MessageTheme.primaryText
        super.init(frame: .zero)

        backgroundColor = .clear
        isOpaque = false
        accessibilityLabel = MessageCloseButton.accessibilityLabel()
        // Stable across campaigns, so a host UI test can find it without knowing the copy.
        accessibilityIdentifier = GameballAccessibility.closeButton

        // SF Symbols where available: the platform glyph is what an iOS customer expects, and it
        // tracks the system's own weight and optical sizing. The drawn path below is the fallback
        // for iOS 11 and 12, which this SDK still supports.
        if #available(iOS 13.0, *) {
            let configuration = UIImage.SymbolConfiguration(
                pointSize: MessageCloseButton.glyphSize, weight: .medium)
            if let glyph = UIImage(systemName: "xmark", withConfiguration: configuration) {
                setImage(glyph.withRenderingMode(.alwaysTemplate), for: .normal)
                self.tintColor = glyphColor
                imageView?.contentMode = .scaleAspectFit
            }
        }

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: MessageCloseButton.targetSize),
            heightAnchor.constraint(greaterThanOrEqualToConstant: MessageCloseButton.targetSize)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: MessageCloseButton.targetSize, height: MessageCloseButton.targetSize)
    }

    /// The SDK ships two languages, so the label ships in two.
    ///
    /// There is no public iOS equivalent of Flutter's `MaterialLocalizations.closeButtonTooltip`,
    /// and the SDK's own `GB_Localizator` reads from the *host* bundle and traps when the file is
    /// missing — which an accessibility label must never be able to do. An unshipped language
    /// falls back to English rather than to an empty label, because an unlabelled button is worse
    /// to a screen-reader user than one labelled in the wrong language.
    static func accessibilityLabel(
        forLanguage language: String = LanguageHelper.resolveLanguage()) -> String {
        return language.lowercased().hasPrefix("ar") ? "إغلاق" : "Close"
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        // Only reached on iOS 11 and 12, where the SF Symbol is unavailable. A stroked path stays
        // crisp at every scale and needs no asset bundle.
        if #available(iOS 13.0, *) { return }

        let side = MessageCloseButton.glyphSize
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
