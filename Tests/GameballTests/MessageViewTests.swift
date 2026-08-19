//
//  MessageViewTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// Records everything a view reports, so the wiring between a tap and a click can be asserted.
final class RecordingCoordinator: MessageViewCoordinating {
    var willPresentCount = 0
    var didPresentCount = 0
    var willDismissCount = 0
    var didDismissCount = 0
    var clicks: [String?] = []
    var actions: [(GameballClickAction, String?)] = []

    func viewWillPresent() { willPresentCount += 1 }
    func viewDidPresent() { didPresentCount += 1 }
    func viewWillDismiss() { willDismissCount += 1 }
    func viewDidDismiss() { didDismissCount += 1 }
    func viewDidClick(buttonId: String?) { clicks.append(buttonId) }
    func viewDidRequest(action: GameballClickAction, buttonId: String?) {
        actions.append((action, buttonId))
    }
}

final class MessageViewTests: XCTestCase {

    private let screen = CGSize(width: 375, height: 667)
    private var coordinator: RecordingCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = RecordingCoordinator()
        iamReduceMotionEnabled = { true }
    }

    override func tearDown() {
        iamReduceMotionEnabled = { UIAccessibility.isReduceMotionEnabled }
        super.tearDown()
    }

    private func host(_ view: InAppMessageView) -> IAMLayoutHost {
        let host = IAMLayoutHost(size: screen)
        host.install(view)
        return host
    }

    private func modal(buttons: [GameballMessageButton] = [],
                       clickAction: GameballClickAction? = nil,
                       showCloseButton: Bool = true,
                       dismissOnScrimTap: Bool = true) -> ModalMessageView {
        return ModalMessageView(message: makeMessage(type: .modal,
                                                     clickAction: clickAction,
                                                     buttons: buttons,
                                                     showCloseButton: showCloseButton,
                                                     dismissOnScrimTap: dismissOnScrimTap),
                                attributes: .defaults,
                                image: nil,
                                icon: nil,
                                coordinator: coordinator)
    }

    private func slideup(clickAction: GameballClickAction? = nil) -> SlideupMessageView {
        return SlideupMessageView(message: makeMessage(type: .slideup, clickAction: clickAction),
                                  attributes: .defaults,
                                  image: nil,
                                  icon: nil,
                                  coordinator: coordinator)
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        return view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private func tapRecognizers(on view: UIView) -> [UITapGestureRecognizer] {
        return (view.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }
    }

    // MARK: - Clicks

    func testButtonTapReportsClickWithButtonId() {
        let view = modal(buttons: [makeButton(id: "cta", text: "Go",
                                              action: .navigate(route: "orders", arguments: nil))])
        _ = host(view)

        guard let button = allSubviews(of: view)
            .compactMap({ $0 as? MessageButtonView }).first else {
            return XCTFail("no button was built")
        }
        simulateTap(button)

        XCTAssertEqual(coordinator.clicks.count, 1)
        XCTAssertEqual(coordinator.clicks.first ?? nil, "cta")
        XCTAssertEqual(coordinator.actions.count, 1)
        if case .navigate(let route, _) = coordinator.actions.first?.0 {
            XCTAssertEqual(route, "orders")
        } else {
            XCTFail("the button's action was not forwarded")
        }
    }

    /// Every tap reports a click, a dismiss button included — engagement is engagement
    /// regardless of where it leads.
    func testDismissButtonStillReportsAClick() {
        let view = modal(buttons: [makeButton(id: "no-thanks", action: .dismiss)])
        _ = host(view)

        if let button = allSubviews(of: view).compactMap({ $0 as? MessageButtonView }).first {
            simulateTap(button)
        }

        XCTAssertEqual(coordinator.clicks.first ?? nil, "no-thanks")
    }

    func testEachButtonReportsItsOwnId() {
        let view = modal(buttons: [makeButton(id: "yes", text: "Yes"),
                                   makeButton(id: "no", text: "No")])
        _ = host(view)

        let buttons = allSubviews(of: view).compactMap { $0 as? MessageButtonView }
        XCTAssertEqual(buttons.count, 2)
        simulateTap(buttons[1])

        XCTAssertEqual(coordinator.clicks.compactMap { $0 }, ["no"])
    }

    // MARK: - Surface taps

    /// A surface with an action is tappable as a whole.
    func testSlideupWithAnActionIsTappable() {
        let view = slideup(clickAction: .openURL(url: URL(string: "https://example.com")!,
                                                 external: false))
        _ = host(view)
        XCTAssertEqual(tapRecognizers(on: view).count, 1,
                       "a slideup with an action should be tappable")
    }

    /// `nil` means inert — not dismiss. Installing a recogniser anyway would steal taps the
    /// campaign never claimed.
    func testSlideupWithoutAnActionIsInert() {
        let view = slideup(clickAction: nil)
        _ = host(view)
        XCTAssertTrue(tapRecognizers(on: view).isEmpty,
                      "an actionless slideup installed a tap recogniser")
        XCTAssertTrue(coordinator.clicks.isEmpty)
    }

    func testSurfaceClickReportsWithoutAButtonId() {
        let view = slideup(clickAction: .dismiss)
        _ = host(view)

        // `process` is the path a surface tap takes.
        view.process(action: .dismiss, buttonId: nil)
        XCTAssertEqual(coordinator.clicks.count, 1)
        XCTAssertNil(coordinator.clicks.first ?? nil)
    }

    // MARK: - Close and scrim

    func testCloseButtonDismisses() {
        let view = modal(showCloseButton: true)
        _ = host(view)

        guard let close = allSubviews(of: view)
            .compactMap({ $0 as? MessageCloseButton }).first else {
            return XCTFail("no close button was built")
        }
        simulateTap(close)

        XCTAssertEqual(coordinator.willDismissCount, 1)
        XCTAssertEqual(coordinator.didDismissCount, 1)
        XCTAssertFalse(view.presented)
    }

    /// Closing does not report a click: dismissing is not engagement.
    func testCloseButtonReportsNoClick() {
        let view = modal(showCloseButton: true)
        _ = host(view)
        if let close = allSubviews(of: view).compactMap({ $0 as? MessageCloseButton }).first {
            simulateTap(close)
        }
        XCTAssertTrue(coordinator.clicks.isEmpty)
    }

    func testScrimIsTappableOnlyWhenTheCampaignAllowsIt() {
        let allowed = modal(dismissOnScrimTap: true)
        _ = host(allowed)
        XCTAssertEqual(tapRecognizers(on: allowed).count, 1,
                       "dismissOnScrimTap should install a recogniser")

        coordinator = RecordingCoordinator()
        let refused = modal(dismissOnScrimTap: false)
        _ = host(refused)
        XCTAssertTrue(tapRecognizers(on: refused).isEmpty,
                      "a modal the marketer wants acknowledged must not close on a stray tap")
    }

    // MARK: - Lifecycle reporting

    func testPresentReportsWillAndDidPresent() {
        let view = modal()
        _ = host(view)
        view.present(completion: nil)

        XCTAssertEqual(coordinator.willPresentCount, 1)
        XCTAssertEqual(coordinator.didPresentCount, 1)
        XCTAssertTrue(view.presented)
    }

    func testDismissReportsWillAndDidDismiss() {
        let view = modal()
        _ = host(view)
        view.present(completion: nil)
        view.dismiss(completion: nil)

        XCTAssertEqual(coordinator.willDismissCount, 1)
        XCTAssertEqual(coordinator.didDismissCount, 1)
        XCTAssertFalse(view.presented)
    }

    func testCompletionsAreCalled() {
        let view = modal()
        _ = host(view)

        var presented = false
        var dismissed = false
        view.present { presented = true }
        view.dismiss { dismissed = true }

        XCTAssertTrue(presented)
        XCTAssertTrue(dismissed)
    }

    // MARK: - Factory

    func testFactoryPicksTheCompositionForEachType() {
        func made(_ type: GameballMessageType,
                  layout: GameballMessageLayout,
                  image: UIImage?) -> InAppMessageView? {
            let context = PresentationContext(message: makeMessage(type: type, layout: layout))
            return MessageViewFactory.make(context: context, image: image, icon: nil,
                                           coordinator: coordinator)
        }

        let image = UIImage()
        XCTAssertTrue(made(.slideup, layout: .textWithImage, image: nil) is SlideupMessageView)
        XCTAssertTrue(made(.modal, layout: .textWithImage, image: nil) is ModalMessageView)
        XCTAssertTrue(made(.modal, layout: .imageOnly, image: image) is ModalImageMessageView)
        XCTAssertTrue(made(.fullscreen, layout: .textWithImage, image: nil)
                        is FullscreenMessageView)
        XCTAssertTrue(made(.fullscreen, layout: .imageOnly, image: image)
                        is FullscreenImageMessageView)
        XCTAssertNil(made(.unsupported, layout: .textWithImage, image: nil))
    }

    /// `image_only` with no usable artwork would draw an empty card, so it falls back to the
    /// copy composition rather than rendering nothing.
    func testImageOnlyWithoutArtworkFallsBackToTheCopyComposition() {
        let context = PresentationContext(message: makeMessage(type: .modal, layout: .imageOnly))
        let view = MessageViewFactory.make(context: context, image: nil, icon: nil,
                                           coordinator: coordinator)
        XCTAssertTrue(view is ModalMessageView)
        XCTAssertFalse(view is ModalImageMessageView)
    }
}
