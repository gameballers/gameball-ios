//
//  ImageOnlyButtonsTests.swift
//  GameballTests
//
//  An `image_only` campaign drops its copy — that is the composition, and the dashboard guards it
//  so every platform agrees. It does **not** drop its buttons: the poster is the message and the
//  button is the only way to act on it beyond a tap on the surface.
//
//  Both image-only views were written without a button block, so a campaign carrying one rendered
//  the artwork and nothing else. Live proof: campaign 2144 "Saudi National Day - Fullscreen -
//  Image only" ships `buttons: [btn_1 "اطلب الحين"]` and showed no button at all.
//
//  Android has drawn these since the start — `bindImageOnly` re-parents the row over the artwork
//  using `IMAGE_ONLY_BUTTONS_PADDING_*`, whose iOS counterparts already existed here as
//  `imageOnlyButtonsPadding` and were read by nothing.
//

import XCTest
@testable import Gameball

final class ImageOnlyButtonsTests: XCTestCase {

    private var hosts: [IAMLayoutHost] = []
    private let attributes = MessageViewAttributes.defaults

    override func setUp() {
        super.setUp()
        iamReduceMotionEnabled = { true }
    }

    override func tearDown() {
        hosts.removeAll()
        iamReduceMotionEnabled = { UIAccessibility.isReduceMotionEnabled }
        super.tearDown()
    }

    private func artwork() -> UIImage {
        let size = CGSize(width: 40, height: 80)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func host(_ view: InAppMessageView, size: CGSize = CGSize(width: 390, height: 844))
        -> IAMLayoutHost {
        let host = IAMLayoutHost(size: size)
        hosts.append(host)
        host.install(view)
        host.layout()
        return host
    }

    private func descendants(of view: UIView) -> [UIView] {
        return view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private func buttonViews(in view: UIView) -> [MessageButtonView] {
        return descendants(of: view).compactMap { $0 as? MessageButtonView }
    }

    // MARK: - The defect

    func testAFullscreenPosterRendersItsButtons() {
        let view = FullscreenImageMessageView(
            message: makeMessage(type: .fullscreen, header: nil, body: nil,
                                 buttons: [makeButton(id: "btn_1", text: "اطلب الحين")],
                                 layout: .imageOnly),
            attributes: attributes, image: artwork(), icon: nil, coordinator: nil)
        _ = host(view)

        let buttons = buttonViews(in: view)
        XCTAssertEqual(buttons.count, 1, "the poster's only call to action was dropped")
        XCTAssertEqual(buttons.first?.title(for: .normal), "اطلب الحين")
        XCTAssertEqual(buttons.first?.accessibilityIdentifier,
                       GameballAccessibility.button("btn_1"))
    }

    func testAModalPosterRendersItsButtons() {
        let view = ModalImageMessageView(
            message: makeMessage(type: .modal, header: nil, body: nil,
                                 buttons: [makeButton(id: "btn_1", text: "Order now")],
                                 layout: .imageOnly),
            attributes: attributes, image: artwork(), icon: nil, coordinator: nil)
        _ = host(view)

        let buttons = buttonViews(in: view)
        XCTAssertEqual(buttons.count, 1, "the poster's only call to action was dropped")
        XCTAssertEqual(buttons.first?.title(for: .normal), "Order now")
    }

    /// The buttons float *over* the surface, so a surface recogniser sits above them and would
    /// cancel their touch tracking — leaving a button that draws correctly and does nothing. The
    /// poster's own tap action is the common case: `content.action` plus `content.buttons`.
    func testATapOnAButtonIsNotTakenByTheSurface() {
        let button = MessageButtonView(button: makeButton(), style: makeButton().style,
                                       typography: .fullscreenButton,
                                       contentInsets: .zero)
        let wrapper = UIView()
        wrapper.addSubview(button)
        let label = UILabel()
        button.addSubview(label)

        XCTAssertFalse(MessageButtonView.surfaceGestureShouldReceive(touchOn: button),
                       "a touch on the button itself belongs to the button")
        XCTAssertFalse(MessageButtonView.surfaceGestureShouldReceive(touchOn: label),
                       "so does a touch on something inside it")
        XCTAssertTrue(MessageButtonView.surfaceGestureShouldReceive(touchOn: wrapper),
                      "a touch on the surface around it is the surface's")
        XCTAssertTrue(MessageButtonView.surfaceGestureShouldReceive(touchOn: nil))
    }

    /// Over the artwork and inset from the bottom, per `imageOnlyButtonsPadding` — not stacked
    /// below it, which on a full-bleed poster would mean letterboxing the very thing that is
    /// meant to reach every edge.
    func testFullscreenPosterButtonsFloatOverTheArtwork() {
        let view = FullscreenImageMessageView(
            message: makeMessage(type: .fullscreen, header: nil, body: nil,
                                 buttons: [makeButton()], layout: .imageOnly),
            attributes: attributes, image: artwork(), icon: nil, coordinator: nil)
        _ = host(view)

        guard let button = buttonViews(in: view).first else {
            return XCTFail("no button to place")
        }
        let frame = button.convert(button.bounds, to: view)
        let imageView = descendants(of: view).compactMap { $0 as? UIImageView }.first
        XCTAssertNotNil(imageView, "the poster itself is missing")

        XCTAssertGreaterThan(frame.minY, view.bounds.midY, "the row belongs at the foot")
        XCTAssertLessThan(frame.maxY, view.bounds.maxY,
                          "the row must sit inside the surface, not past its bottom edge")
        XCTAssertEqual(view.bounds.maxY - frame.maxY,
                       attributes.fullscreen.imageOnlyButtonsPadding.bottom
                           + view.safeAreaInsets.bottom,
                       accuracy: 1,
                       "the spec's bottom inset, measured from the safe area")
    }
}
