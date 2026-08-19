//
//  MessageTextBlock.swift
//  Gameball
//

import UIKit

/// Builds the scrollable copy block the modal, slideup and fullscreen compositions share.
///
/// Copy lives in a scroll view so long text — or text at an accessibility size — scrolls rather
/// than clipping. The subtlety is the other direction: the obvious "make it scrollable" fix
/// makes *every* card full height. So the scroll view carries a low-priority constraint pinning
/// its height to its content, which lets a one-line message stay one line while a long one is
/// clamped by whatever bound the parent imposes.
enum MessageTextBlock {

    static func make(header: String?,
                     body: String?,
                     headerFont: UIFont,
                     bodyFont: UIFont,
                     headerColor: UIColor,
                     bodyColor: UIColor,
                     headerAlignment: NSTextAlignment,
                     bodyAlignment: NSTextAlignment,
                     spacing: CGFloat) -> UIScrollView? {
        var labels: [UILabel] = []
        if let header = header {
            labels.append(label(header, font: headerFont, color: headerColor,
                                alignment: headerAlignment))
        }
        if let body = body {
            labels.append(label(body, font: bodyFont, color: bodyColor,
                                alignment: bodyAlignment))
        }
        guard !labels.isEmpty else { return nil }

        let stack = UIStackView(arrangedSubviews: labels)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        // The "stay short" half of the rule. Low priority, so a parent bound wins when the
        // copy is genuinely too long.
        let hug = scroll.heightAnchor.constraint(equalTo: stack.heightAnchor)
        hug.priority = UILayoutPriority(250)
        hug.isActive = true

        return scroll
    }

    private static func label(_ text: String,
                              font: UIFont,
                              color: UIColor,
                              alignment: NSTextAlignment) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = 0
        // Dynamic Type without the host opting in.
        label.adjustsFontForContentSizeCategory = true
        return label
    }
}
