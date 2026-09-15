//
//  MessageTypography.swift
//  Gameball
//

import UIKit

/// One typographic slot from the cross-platform UI spec's table.
///
/// The spec states each slot as an absolute size, line height and weight — 22/28 at 700 for a modal
/// header — rather than as a platform text style. That is deliberate: `title3` on iOS and
/// `titleLarge` on Material are not the same size, so naming a style per platform is how the same
/// campaign ends up looking different on each.
///
/// The figures are the values **at the default content size**. They scale from there through
/// `UIFontMetrics`, so a customer who has enlarged text still gets the SDK's own proportions — the
/// spec's numbers and iOS's accessibility contract are only in tension if you read the numbers as
/// a cap, and a message the customer cannot read is worse than one that is 4pt off a reference.
struct MessageTypography {
    let size: CGFloat
    let lineHeight: CGFloat
    let weight: UIFont.Weight

    // Modal
    static let modalHeader = MessageTypography(size: 22, lineHeight: 28, weight: .bold)
    static let modalBody = MessageTypography(size: 14, lineHeight: 20, weight: .regular)
    static let modalButton = MessageTypography(size: 14, lineHeight: 20, weight: .medium)

    // Slideup — one slot; a banner has no header row.
    static let slideupCopy = MessageTypography(size: 14, lineHeight: 20, weight: .regular)

    // Fullscreen — larger and heavier throughout than a modal's, because the surface is.
    static let fullscreenHeader = MessageTypography(size: 24, lineHeight: 32, weight: .bold)
    static let fullscreenBody = MessageTypography(size: 16, lineHeight: 24, weight: .regular)
    static let fullscreenButton = MessageTypography(size: 16, lineHeight: 24, weight: .semibold)

    /// Scaled for the given content size category.
    func font(for traits: UITraitCollection? = nil) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let traits = traits else {
            return UIFontMetrics.default.scaledFont(for: base)
        }
        return UIFontMetrics.default.scaledFont(for: base, compatibleWith: traits)
    }

    func scaledLineHeight(for traits: UITraitCollection? = nil) -> CGFloat {
        guard let traits = traits else {
            return UIFontMetrics.default.scaledValue(for: lineHeight)
        }
        return UIFontMetrics.default.scaledValue(for: lineHeight, compatibleWith: traits)
    }
}

/// A label that honours a `MessageTypography` slot, line height included.
///
/// A plain `UILabel` with `adjustsFontForContentSizeCategory` scales its font but has no notion of
/// line height, and the spec's leading is not iOS's default: 16/24 for a fullscreen body is a
/// quarter more open than the system's own 16pt leading. Forcing it needs attributed text — which
/// is exactly what turns Dynamic Type off, because that flag only applies to plain text. So this
/// rebuilds itself when the content size category changes, which is the part a naive attributed
/// label silently loses.
final class MessageLabel: UILabel {

    private let typography: MessageTypography
    private let content: String
    private let contentColor: UIColor

    init(text: String,
         typography: MessageTypography,
         color: UIColor,
         alignment: NSTextAlignment,
         numberOfLines: Int = 0) {
        self.typography = typography
        self.content = text
        self.contentColor = color
        super.init(frame: .zero)
        self.textAlignment = alignment
        self.numberOfLines = numberOfLines
        apply()
    }

    required init?(coder: NSCoder) { return nil }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory
        else { return }
        apply()
    }

    private func apply() {
        let font = typography.font(for: traitCollection)
        let lineHeight = typography.scaledLineHeight(for: traitCollection)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        // Both bounds, so the line box is the spec's height whether the glyphs are tall or short.
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = numberOfLines == 1 ? .byTruncatingTail : .byWordWrapping
        // Deferred to draw time, which is the only point at which the direction is known.
        paragraph.baseWritingDirection = .natural

        // Forcing a line height pins the text to the top of its line box; this re-centres it.
        // Quarter rather than half because the offset moves the baseline, not the box.
        let baseline = (lineHeight - font.lineHeight) / 4

        attributedText = NSAttributedString(string: content, attributes: [
            .font: font,
            .foregroundColor: contentColor,
            .paragraphStyle: paragraph,
            .baselineOffset: baseline
        ])
    }
}
