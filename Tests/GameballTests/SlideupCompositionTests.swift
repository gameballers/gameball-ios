//
//  SlideupCompositionTests.swift
//  GameballTests
//
//  The slideup renders one composition, and the UI spec is unusually prescriptive about it: three
//  lines then ellipsis, a fixed 40-square icon, a chevron only when the campaign set an action.
//  None of it is reachable from the live account — no campaign has an icon, and none sets
//  `content.action` — so this is the only place any of it is checked.
//

import XCTest
@testable import Gameball

final class SlideupCompositionTests: XCTestCase {

    private var hosts: [IAMLayoutHost] = []
    private let attributes = MessageViewAttributes.Slideup.defaults

    override func setUp() {
        super.setUp()
        iamReduceMotionEnabled = { true }
    }

    override func tearDown() {
        hosts.removeAll()
        iamReduceMotionEnabled = { UIAccessibility.isReduceMotionEnabled }
        super.tearDown()
    }

    private func slideup(body: String? = "Nice pick — it earns you points!",
                         header: String? = nil,
                         action: GameballClickAction? = nil,
                         icon: UIImage? = nil,
                         screen: CGSize = CGSize(width: 390, height: 844))
        -> (view: SlideupMessageView, host: IAMLayoutHost) {
        let host = IAMLayoutHost(size: screen)
        hosts.append(host)
        let view = SlideupMessageView(
            message: makeMessage(type: .slideup, header: header, body: body,
                                 clickAction: action),
            attributes: .defaults, image: nil, icon: icon, coordinator: nil)
        host.install(view)
        host.layout()
        return (view, host)
    }

    private func descendants(of view: UIView) -> [UIView] {
        return view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    // MARK: - The chevron

    /// Drawn only when the campaign set a message action, so the affordance matches the behaviour.
    /// A chevron on an inert banner promises a tap that does nothing.
    func testTheChevronAppearsOnlyWithAnAction() {
        let withAction = slideup(action: .dismiss).view
        XCTAssertEqual(descendants(of: withAction).filter { $0 is SlideupChevron }.count, 1)

        let without = slideup(action: nil).view
        XCTAssertTrue(descendants(of: without).filter { $0 is SlideupChevron }.isEmpty,
                      "an inert banner must not promise a tap")
    }

    func testTheChevronIsTheSpecsSize() {
        let view = slideup(action: .dismiss).view
        guard let chevron = descendants(of: view).first(where: { $0 is SlideupChevron }) else {
            return XCTFail("no chevron")
        }
        XCTAssertEqual(chevron.bounds.width, attributes.chevronSize, accuracy: 0.5)
        XCTAssertEqual(chevron.bounds.height, attributes.chevronSize, accuracy: 0.5)
    }

    /// It is decoration. The banner itself is the accessibility element, and announcing a chevron
    /// offers a screen-reader user a control they cannot act on separately.
    func testTheChevronIsHiddenFromAssistiveTechnology() {
        let view = slideup(action: .dismiss).view
        guard let chevron = descendants(of: view).first(where: { $0 is SlideupChevron }) else {
            return XCTFail("no chevron")
        }
        XCTAssertFalse(chevron.isAccessibilityElement)
    }

    // MARK: - The three-line clamp

    /// The clamp is what keeps a banner a band. Without it a slideup grows with its copy and
    /// eventually covers the screen it exists not to block.
    func testCopyIsClampedToThreeLines() {
        let long = String(repeating: "This is a long line of campaign copy that will wrap. ", count: 12)
        let view = slideup(body: long).view

        let labels = descendants(of: view).compactMap { $0 as? UILabel }
        guard let copy = labels.first else { return XCTFail("no copy label") }
        XCTAssertEqual(copy.numberOfLines, attributes.maxTextLines)

        let ceiling = CGFloat(attributes.maxTextLines) * MessageTypography.slideupCopy.lineHeight
            + attributes.padding.top + attributes.padding.bottom
        XCTAssertLessThanOrEqual(view.bounds.height, ceiling + 1,
                                 "the banner grew past three lines")
    }

    /// A banner has no header row: it renders `locale.message`, falling back to `locale.header` so
    /// a campaign that filled the wrong field still says something.
    func testHeaderIsUsedOnlyWhenThereIsNoBody() {
        let bodyOnly = slideup(body: "Body", header: "Header").view
        let texts = descendants(of: bodyOnly).compactMap { ($0 as? UILabel)?.text }
        XCTAssertEqual(texts, ["Body"], "the header must not add a second row")

        let headerOnly = slideup(body: nil, header: "Header").view
        XCTAssertEqual(descendants(of: headerOnly).compactMap { ($0 as? UILabel)?.text },
                       ["Header"], "a campaign that filled the wrong field still says something")
    }

    // MARK: - Geometry

    func testTheIconIsAFixedSquare() {
        let asset = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100)).image { c in
            UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 300, height: 100))
        }
        let view = slideup(icon: asset).view
        guard let icon = descendants(of: view).compactMap({ $0 as? UIImageView }).first else {
            return XCTFail("no icon")
        }
        // Fixed, not sized to its own ratio: a per-campaign icon shape would change the banner's
        // height from campaign to campaign.
        XCTAssertEqual(icon.bounds.width, attributes.iconSize.width, accuracy: 0.5)
        XCTAssertEqual(icon.bounds.height, attributes.iconSize.height, accuracy: 0.5)
        XCTAssertEqual(icon.layer.cornerRadius, attributes.iconCornerRadius)
        XCTAssertEqual(icon.contentMode, .scaleAspectFill, "a 3:1 asset fills its square")
    }

    /// On a phone the margins decide the width; on a tablet the banner stops growing rather than
    /// stretching into a panel.
    func testTheBannerStopsGrowingOnAWideScreen() {
        let phone = slideup().view
        XCTAssertEqual(phone.bounds.width,
                       390 - attributes.margin.left - attributes.margin.right, accuracy: 0.5)

        let tablet = slideup(screen: CGSize(width: 1024, height: 1366)).view
        XCTAssertEqual(tablet.bounds.width, attributes.maxWidth, accuracy: 0.5,
                       "the banner should cap at \(attributes.maxWidth), not fill the iPad")
    }

    func testTheBannerCarriesTheSpecsRadiusAndShadow() {
        let view = slideup().view
        XCTAssertEqual(view.layer.cornerRadius, attributes.cornerRadius)
        // It floats with no scrim, so the shadow is what separates it from app content.
        XCTAssertGreaterThan(view.layer.shadowOpacity, 0)
        XCTAssertFalse(view.layer.masksToBounds, "masking would clip the shadow away")
    }

    /// The spec is explicit that a slideup has no close glyph: a swipe towards its own edge and the
    /// timer are its exits.
    func testTheBannerNeverDrawsACloseGlyph() {
        let view = slideup().view
        XCTAssertTrue(descendants(of: view).filter { $0 is MessageCloseButton }.isEmpty)
    }
}
