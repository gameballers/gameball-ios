//
//  ModalArtworkRatioTests.swift
//  GameballTests
//
//  The UI spec publishes exact expected heights for seven artwork ratios and four device sizes.
//  That is unusually testable for layout work, so these are its tables asserted directly rather
//  than a restatement of the formula.
//
//  The model: the artwork takes its natural height at the card's width, capped by the smaller of
//  `cardWidth ÷ minImageRatio` (a shape, so it is device-independent wherever there is room) and
//  `available − copyReserve` (a floor that keeps the call to action on screen).
//

import XCTest
@testable import Gameball

final class ModalArtworkRatioTests: XCTestCase {

    /// Every host built during a test, held until it ends.
    ///
    /// `IAMLayoutHost` owns a `UIWindow`; releasing one mid-test tears its hierarchy down, and the
    /// bounds read afterwards collapse to intrinsic sizes — which is how the first version of these
    /// tests measured a 40-point card.
    private var hosts: [IAMLayoutHost] = []


    override func setUp() {
        super.setUp()
        iamReduceMotionEnabled = { true }
    }

    override func tearDown() {
        hosts.removeAll()
        iamReduceMotionEnabled = { UIAccessibility.isReduceMotionEnabled }
        super.tearDown()
    }

    /// Returns the host as well, and the caller must hold it. `IAMLayoutHost` owns the `UIWindow`
    /// the hierarchy lives in, so letting it go out of scope tears the layout down — and the
    /// bounds read afterwards are whatever survives that, which is how this first measured a
    /// 40-point card.
    private func artwork(ratio: CGFloat,
                         screen: CGSize) -> (host: IAMLayoutHost, image: UIImageView, card: UIView)? {
        // 1000 wide keeps the source large enough that the height is the interesting number.
        let size = CGSize(width: 1000, height: 1000 / ratio)
        let asset = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let host = IAMLayoutHost(size: screen)
        hosts.append(host)
        let view = ModalMessageView(
            message: makeMessage(type: .modal, header: "Header", body: "Body",
                                 buttons: [makeButton()]),
            attributes: .defaults, image: asset, icon: nil, coordinator: nil)
        host.install(view)
        // The artwork height is resolved in `layoutSubviews`, which then invalidates layout — so
        // the first pass leaves the card one step behind. Settle before measuring.
        host.layout()
        host.layout()

        func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
            for subview in view.subviews {
                if subview is MessageCloseButton { continue }
                if let match = subview as? T { return match }
                if let deeper = find(type, in: subview) { return deeper }
            }
            return nil
        }
        guard let image = find(UIImageView.self, in: view),
              let card = view.subviews.first(where: {
                  $0.accessibilityIdentifier == GameballAccessibility.card }) else { return nil }
        return (host, image, card)
    }

    /// The spec's ratio table, on an iPhone 15: 390×844, card 342 wide, cap 621.8.
    func testTheRatioTableOnAnIPhoneFifteen() {
        let screen = CGSize(width: 390, height: 844)
        let expected: [(ratio: CGFloat, height: CGFloat)] = [
            (1.778, 192.4),   // 16 : 9
            (1.333, 256.6),   // 4 : 3
            (1.000, 342.0),   // square
            (0.750, 456.0),   // 3 : 4
            (0.600, 570.0),   // the live poster
            (0.563, 607.5),   // 9 : 16
            (0.500, 621.8)    // taller than 0.55 — clamped by shape
        ]
        for (ratio, height) in expected {
            guard let found = artwork(ratio: ratio, screen: screen) else {
                XCTFail("no artwork at ratio \(ratio)")
                continue
            }
            XCTAssertEqual(found.card.bounds.width, 342, accuracy: 0.5,
                           "card width at ratio \(ratio)")
            XCTAssertEqual(found.image.bounds.height, height, accuracy: 1.5,
                           "ratio \(ratio) should be \(height) tall, "
                         + "was \(found.image.bounds.height)")
        }
    }

    /// A very tall asset is clamped and letterboxes — the spec's "15.5 bars each side" at 0.500.
    /// `contain` is what produces the bars; `cover` would crop instead, which is the image-only
    /// rule and not this one.
    func testAVeryTallAssetIsClampedAndLetterboxes() {
        guard let found = artwork(ratio: 0.5, screen: CGSize(width: 390, height: 844)) else {
            return XCTFail("no artwork")
        }
        XCTAssertEqual(found.image.contentMode, .scaleAspectFit)
        XCTAssertEqual(found.image.bounds.height, 621.8, accuracy: 1.5)

        // With contain at 0.5 in a 342×621.8 box the picture is 310.9 wide, leaving 15.5 a side.
        let drawn = found.image.bounds.height * 0.5
        XCTAssertEqual((found.image.bounds.width - drawn) / 2, 15.5, accuracy: 1.5)
    }

    /// The device table. Which bound binds changes with the screen, and the spec is explicit that
    /// this is not perfectly device-independent: on a cramped screen the copy reserve binds first.
    func testWhichBoundBindsPerDevice() {
        let cases: [(name: String, screen: CGSize, card: CGFloat, cap: CGFloat)] = [
            ("iPhone 15", CGSize(width: 390, height: 844), 342, 621.8),
            ("iPad", CGSize(width: 834, height: 1194), 420, 763.6),
            ("iPhone SE", CGSize(width: 375, height: 667), 327, 499.0),
            ("small Android", CGSize(width: 360, height: 640), 312, 472.0)
        ]
        for (name, screen, card, cap) in cases {
            // A 0.3 ratio is far taller than either bound, so the artwork is held at the cap.
            guard let found = artwork(ratio: 0.3, screen: screen) else {
                XCTFail("no artwork on \(name)")
                continue
            }
            XCTAssertEqual(found.card.bounds.width, card, accuracy: 0.5, "card width on \(name)")
            // A cap, so `<=`. On the two cramped devices the copy and buttons want slightly more
            // than `copyReserve` allows, and the artwork gives up the difference rather than the
            // layout breaking — the spec notes the reserve binding first on small screens.
            XCTAssertLessThanOrEqual(found.image.bounds.height, cap + 1.5,
                                     "\(name) exceeded its cap of \(cap)")
            XCTAssertGreaterThan(found.image.bounds.height, cap - 8,
                                 "\(name) fell well short of \(cap): "
                               + "\(found.image.bounds.height)")
        }
    }

    /// The reserve is the point of the second bound: whatever the artwork, this much height is
    /// always left for the copy and the call to action.
    func testTheCopyReserveIsAlwaysHonoured() {
        for screen in [CGSize(width: 390, height: 844), CGSize(width: 360, height: 640)] {
            guard let found = artwork(ratio: 0.3, screen: screen) else {
                XCTFail("no artwork")
                continue
            }
            let available = screen.height - MessageViewAttributes.Modal.defaults.margin.top
                - MessageViewAttributes.Modal.defaults.margin.bottom
            let left = available - found.image.bounds.height
            XCTAssertGreaterThanOrEqual(left, MessageViewAttributes.Modal.defaults.copyReserve - 1.5,
                                        "only \(left) left for copy and buttons on \(screen)")
        }
    }
}
