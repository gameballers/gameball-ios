//
//  CloseGlyphTests.swift
//  GameballTests
//
//  The close glyph is the one control that must stay legible against a surface the SDK has never
//  seen. A dark glyph on a dark card is not a styling flaw — it is a customer who cannot close the
//  message. Every case here is drawn from the cross-platform UI spec.
//

import XCTest
@testable import Gameball

final class CloseGlyphTests: XCTestCase {

    private func colour(_ hex: UInt32) -> UIColor {
        return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255,
                       alpha: 1)
    }

    /// WCAG 2.1 contrast ratio, computed independently of the SDK so the assertions below are a
    /// check rather than a restatement.
    private func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        func luminance(_ colour: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, alpha: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &bl, alpha: &alpha)
            func channel(_ c: CGFloat) -> CGFloat {
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(bl)
        }
        let first = luminance(a), second = luminance(b)
        let lighter = max(first, second), darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - The three cases, in order

    /// Case 1. A named colour is used exactly as asked, readable or not. Quietly substituting
    /// something more legible is how a brand colour becomes a colour nobody chose.
    func testACampaignColourIsUsedVerbatim() {
        let asked = colour(0xFF0000)
        XCTAssertEqual(MessageTheme.closeGlyphColor(named: asked, background: .white), asked)
        XCTAssertEqual(MessageTheme.closeGlyphColor(named: asked,
                                                    background: colour(0x111827)), asked)
    }

    /// Case 2. No named colour, but the campaign set a background — pick whichever half of the
    /// constant pair contrasts with it.
    func testTheGlyphIsDerivedFromTheBackground() {
        XCTAssertEqual(MessageTheme.closeGlyphColor(named: nil, background: colour(0xFFFFFF)),
                       MessageTheme.closeGlyphOnLight, "white card takes the dark glyph")
        XCTAssertEqual(MessageTheme.closeGlyphColor(named: nil, background: colour(0x111827)),
                       MessageTheme.closeGlyphOnDark, "the live slideup's dark ground")
        XCTAssertEqual(MessageTheme.closeGlyphColor(named: nil, background: colour(0xF5C518)),
                       MessageTheme.closeGlyphOnLight, "a saturated yellow is a light surface")
    }

    /// Case 3. Nothing named and no background: the platform's on-surface colour already contrasts
    /// with the surface it sits on, and computing our own would second-guess a solved problem.
    func testWithNoBackgroundTheHostThemeDecides() {
        XCTAssertEqual(MessageTheme.closeGlyphColor(named: nil, background: nil),
                       MessageTheme.primaryText)
    }

    // MARK: - The guarantee, not the mechanism

    /// The point of deriving rather than defaulting. Both halves of a fixed pair fail on live
    /// campaigns — a white glyph is 1.00:1 on a white card, a dark one is 1.00:1 on #111827 — and
    /// WCAG 2.1 asks 3:1 of a non-text control. This asserts the outcome across the spectrum.
    func testTheDerivedGlyphAlwaysClearsThreeToOne() {
        var worst = CGFloat.greatestFiniteMagnitude
        var worstBackground = ""
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 17) {
                for blue in stride(from: 0, through: 255, by: 17) {
                    let background = UIColor(red: CGFloat(red) / 255,
                                             green: CGFloat(green) / 255,
                                             blue: CGFloat(blue) / 255, alpha: 1)
                    let glyph = MessageTheme.closeGlyphColor(named: nil, background: background)
                    let ratio = contrast(glyph, background)
                    if ratio < worst {
                        worst = ratio
                        worstBackground = String(format: "#%02X%02X%02X", red, green, blue)
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(worst, 3.0,
                                    "worst case \(worst):1 on \(worstBackground)")
        // The spec states 3.8:1 at the threshold itself. Anything much below that means the
        // crossover moved.
        XCTAssertGreaterThan(worst, 3.5, "worst case \(worst):1 on \(worstBackground)")
    }

    /// The two live failures the derivation exists to prevent, asserted directly.
    func testTheTwoLiveFailuresAreFixed() {
        let whiteCard = colour(0xFFFFFF)
        XCTAssertGreaterThan(contrast(MessageTheme.closeGlyphColor(named: nil,
                                                                   background: whiteCard),
                                      whiteCard), 10,
                             "a fixed white glyph was 1.00:1 here")
        let darkCard = colour(0x111827)
        XCTAssertGreaterThan(contrast(MessageTheme.closeGlyphColor(named: nil,
                                                                   background: darkCard),
                                      darkCard), 10,
                             "a fixed dark glyph was 1.00:1 here")
    }

    // MARK: - Geometry

    /// 48 × 48 around a 24 glyph, on every type. The two numbers are deliberately separate: the
    /// target is the accessibility minimum, the glyph is what the customer sees.
    func testTheTargetIsFortyEightAroundATwentyFourGlyph() {
        let button = MessageCloseButton(tintColor: nil)
        XCTAssertEqual(button.intrinsicContentSize, CGSize(width: 48, height: 48))
        XCTAssertEqual(MessageCloseButton.glyphSize, 24)

        let host = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        button.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: host.topAnchor),
            button.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        ])
        host.layoutIfNeeded()
        XCTAssertGreaterThanOrEqual(button.bounds.width, 48)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 48)
    }

    /// The SDK ships two languages, so the label ships in two. There is no public iOS equivalent
    /// of Flutter's `MaterialLocalizations.closeButtonTooltip`, and the SDK's own localizator
    /// reads from the *host* bundle and traps when the file is absent — not something an
    /// accessibility label should be able to crash on.
    func testTheAccessibilityLabelFollowsTheSDKLanguage() {
        XCTAssertEqual(MessageCloseButton.accessibilityLabel(forLanguage: "en"), "Close")
        XCTAssertEqual(MessageCloseButton.accessibilityLabel(forLanguage: "ar"), "إغلاق")
        XCTAssertEqual(MessageCloseButton.accessibilityLabel(forLanguage: "AR"), "إغلاق",
                       "the wire sends a bare code and its case is not guaranteed")
        XCTAssertEqual(MessageCloseButton.accessibilityLabel(forLanguage: "fr"), "Close",
                       "a language the SDK does not ship falls back rather than showing nothing")
    }

    /// No disc, ring or shadow. The contrast comes from the glyph colour, which is the whole
    /// reason the derivation exists — a plate behind it would make the derivation pointless and
    /// add a surface the campaign never asked for.
    func testTheGlyphCarriesNoPlate() {
        let button = MessageCloseButton(tintColor: nil)
        XCTAssertEqual(button.backgroundColor, .clear)
        XCTAssertEqual(button.layer.cornerRadius, 0)
        XCTAssertEqual(button.layer.borderWidth, 0)
        XCTAssertEqual(button.layer.shadowOpacity, 0)
    }
}
