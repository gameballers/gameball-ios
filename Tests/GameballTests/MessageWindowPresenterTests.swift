//
//  MessageWindowPresenterTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// A minimal `InAppMessageView` that occupies a band at the bottom, so the window's
/// passthrough rule can be exercised without any real layout.
final class StubMessageView: UIView, InAppMessageView {
    weak var coordinator: MessageViewCoordinating?
    private(set) var presented = false

    /// When true, `present` does not report `didPresent` — a message torn down mid-entrance.
    var suppressDidPresent = false

    init(frame: CGRect, coordinator: MessageViewCoordinating? = nil) {
        self.coordinator = coordinator
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { return nil }

    func present(completion: (() -> Void)?) {
        willPresent()
        presented = true
        if !suppressDidPresent { didPresent() }
        completion?()
    }

    func dismiss(completion: (() -> Void)?) {
        willDismiss()
        presented = false
        didDismiss()
        completion?()
    }
}

final class MessageWindowPresenterTests: XCTestCase {

    private var shown = 0
    private var dismissed = 0
    private var buttonsPressed: [String] = []
    private var surfacePresses = 0
    private var builtViews: [StubMessageView] = []

    override func setUp() {
        super.setUp()
        shown = 0
        dismissed = 0
        buttonsPressed = []
        surfacePresses = 0
        builtViews = []
    }

    private func makePresenter(headless: Bool = true,
                               viewFrame: CGRect = CGRect(x: 0, y: 500, width: 320, height: 68))
        -> MessageWindowPresenter {
        var presenter: MessageWindowPresenter!
        presenter = MessageWindowPresenter(viewFactory: { _ in
            let view = StubMessageView(frame: viewFrame, coordinator: presenter)
            self.builtViews.append(view)
            return view
        })
        presenter.headless = headless
        return presenter
    }

    private func handlers() -> PresentationHandlers {
        return PresentationHandlers(onShown: { self.shown += 1 },
                                    onButtonPressed: { self.buttonsPressed.append($0.id) },
                                    onMessagePressed: { self.surfacePresses += 1 },
                                    onDismissed: { self.dismissed += 1 })
    }

    private func context(type: GameballMessageType = .slideup,
                         autoDismissAfter: TimeInterval? = nil,
                         buttons: [GameballMessageButton] = []) -> PresentationContext {
        return PresentationContext(message: makeMessage(type: type,
                                                        buttons: buttons,
                                                        autoDismissAfter: autoDismissAfter))
    }

    // MARK: - Obstacles

    func testPresentReturnsNoSurfaceWhenThereIsNoWindow() {
        let presenter = makePresenter(headless: false)
        presenter.surfaceProvider = { nil }
        XCTAssertEqual(presenter.present(context: context(), handlers: handlers()), .noSurface)
        XCTAssertFalse(presenter.isShowing)
    }

    func testPresentReturnsAlreadyShowingWhenOneIsUp() {
        let presenter = makePresenter()
        XCTAssertNil(presenter.present(context: context(), handlers: handlers()))
        XCTAssertEqual(presenter.present(context: context(), handlers: handlers()), .alreadyShowing)
    }

    func testPresentReturnsNotMainThreadOffMain() {
        let presenter = makePresenter()
        let done = expectation(description: "off-main attempt")
        DispatchQueue.global().async {
            let obstacle = presenter.present(context: self.context(), handlers: self.handlers())
            XCTAssertEqual(obstacle, .notMainThread)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertFalse(presenter.isShowing)
    }

    func testHeadlessPresentsWithoutAHostApp() {
        let presenter = makePresenter(headless: true)
        presenter.surfaceProvider = { nil }
        XCTAssertNil(presenter.present(context: context(), handlers: handlers()))
        XCTAssertTrue(presenter.isShowing)
    }

    // MARK: - Window configuration

    /// Taking key status would steal the host's first responder and dismiss its keyboard.
    func testWindowIsNotMadeKey() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(), handlers: handlers())
        XCTAssertTrue(presenter.isShowing)

        let window = builtViews.first?.window
        XCTAssertNotNil(window)
        XCTAssertFalse(window?.isKeyWindow ?? true, "the message window took key status")
    }

    /// Above `.normal` the message would cover the status bar and call banner.
    func testWindowLevelIsNormal() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(), handlers: handlers())
        XCTAssertEqual(builtViews.first?.window?.windowLevel, UIWindow.Level.normal)
    }

    func testSlideupIsNotAccessibilityModalButModalIs() {
        let slideupPresenter = makePresenter()
        _ = slideupPresenter.present(context: context(type: .slideup), handlers: handlers())
        XCTAssertEqual(builtViews.first?.window?.rootViewController?.view.accessibilityViewIsModal,
                       false)

        builtViews = []
        let modalPresenter = makePresenter()
        _ = modalPresenter.present(context: context(type: .modal), handlers: handlers())
        XCTAssertEqual(builtViews.first?.window?.rootViewController?.view.accessibilityViewIsModal,
                       true)
    }

    func testRootViewIsTransparent() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(), handlers: handlers())
        let background = builtViews.first?.window?.rootViewController?.view.backgroundColor
        XCTAssertTrue(background == nil || background == UIColor.clear,
                      "the root view must not paint over the host")
    }

    // MARK: - Ordering

    /// The impression anchor is visibility, not insertion.
    func testOnShownFiresAfterDidPresentNotAtInsertion() {
        let presenter = makePresenter()
        builtViews = []

        var presenterRef: MessageWindowPresenter!
        presenterRef = MessageWindowPresenter(viewFactory: { _ in
            let view = StubMessageView(frame: .zero, coordinator: presenterRef)
            view.suppressDidPresent = true
            self.builtViews.append(view)
            return view
        })
        presenterRef.headless = true

        XCTAssertNil(presenterRef.present(context: context(), handlers: handlers()))
        XCTAssertEqual(shown, 0, "onShown fired before the view reported it was visible")

        builtViews.first?.didPresent()
        XCTAssertEqual(shown, 1)
    }

    func testOnShownIsReportedOnlyOnce() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(), handlers: handlers())
        builtViews.first?.didPresent()
        builtViews.first?.didPresent()
        XCTAssertEqual(shown, 1)
    }

    // MARK: - Auto dismiss

    func testAutoDismissTimerStartsAtVisibility() {
        var presenterRef: MessageWindowPresenter!
        presenterRef = MessageWindowPresenter(viewFactory: { _ in
            let view = StubMessageView(frame: .zero, coordinator: presenterRef)
            view.suppressDidPresent = true
            self.builtViews.append(view)
            return view
        })
        presenterRef.headless = true

        _ = presenterRef.present(context: context(autoDismissAfter: 0.3), handlers: handlers())

        // Never became visible, so the clock never started.
        let quiet = expectation(description: "no auto dismiss")
        quiet.isInverted = true
        wait(for: [quiet], timeout: 0.6)
        XCTAssertEqual(dismissed, 0, "auto-dismiss ran for a message that was never visible")

        // Once visible, it fires.
        builtViews.first?.didPresent()
        let fired = expectation(description: "auto dismissed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if self.dismissed == 1 { fired.fulfill() }
        }
        wait(for: [fired], timeout: 3)
    }

    func testNoAutoDismissWhenUnset() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(autoDismissAfter: nil), handlers: handlers())
        let quiet = expectation(description: "stays up")
        quiet.isInverted = true
        wait(for: [quiet], timeout: 0.5)
        XCTAssertEqual(dismissed, 0)
        XCTAssertTrue(presenter.isShowing)
    }

    // MARK: - Teardown

    func testDismissTearsDownTheWindow() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(), handlers: handlers())
        let window = builtViews.first?.window
        XCTAssertNotNil(window)

        presenter.dismiss()
        XCTAssertFalse(presenter.isShowing)
        XCTAssertEqual(dismissed, 1)
        XCTAssertNil(window?.rootViewController, "the window kept its controller alive")
    }

    func testPresentingAgainAfterDismissWorks() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(), handlers: handlers())
        presenter.dismiss()
        XCTAssertNil(presenter.present(context: context(), handlers: handlers()))
        XCTAssertTrue(presenter.isShowing)
    }

    func testDismissOnAnIdlePresenterIsHarmless() {
        let presenter = makePresenter()
        presenter.dismiss()
        XCTAssertFalse(presenter.isShowing)
        XCTAssertEqual(dismissed, 0)
    }

    // MARK: - Clicks

    func testButtonClickIsRoutedToTheMatchingButton() {
        let button = makeButton(id: "cta", text: "Go")
        let presenter = makePresenter()
        _ = presenter.present(context: context(type: .modal, buttons: [button]),
                              handlers: handlers())

        builtViews.first?.logClick(buttonId: "cta")
        XCTAssertEqual(buttonsPressed, ["cta"])
        XCTAssertEqual(surfacePresses, 0)
    }

    func testSurfaceClickReportsWithoutAButton() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(), handlers: handlers())

        builtViews.first?.logClick(buttonId: nil)
        XCTAssertEqual(surfacePresses, 1)
        XCTAssertTrue(buttonsPressed.isEmpty)
    }

    /// An id that does not match any button is reported as a surface press rather than
    /// dropped, so a stale id cannot lose the engagement entirely.
    func testUnknownButtonIdFallsBackToASurfacePress() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(type: .modal, buttons: [makeButton(id: "cta")]),
                              handlers: handlers())

        builtViews.first?.logClick(buttonId: "not-a-button")
        XCTAssertEqual(surfacePresses, 1)
        XCTAssertTrue(buttonsPressed.isEmpty)
    }

    func testDismissActionDismisses() {
        let presenter = makePresenter()
        _ = presenter.present(context: context(), handlers: handlers())
        builtViews.first?.process(action: .dismiss, buttonId: nil)
        XCTAssertFalse(presenter.isShowing)
        XCTAssertEqual(dismissed, 1)
    }
}

// MARK: - Window passthrough

final class MessageWindowTests: XCTestCase {

    /// The single rule that makes a slideup non-blocking and a modal blocking, with no
    /// per-type branch anywhere.
    func testHitTestPassesThroughOutsideTheMessageView() {
        let window = MessageWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let controller = UIViewController()
        let message = StubMessageView(frame: CGRect(x: 0, y: 500, width: 320, height: 68))
        controller.view.addSubview(message)
        window.rootViewController = controller
        window.isHidden = false

        // Inside the banner: captured.
        XCTAssertNotNil(window.hitTest(CGPoint(x: 160, y: 530), with: nil))
        // Outside it: passed to the app underneath.
        XCTAssertNil(window.hitTest(CGPoint(x: 160, y: 100), with: nil))
    }

    /// A subview of the message view still counts as the message view, or every button and
    /// label inside it would be untappable.
    func testHitTestCapturesTouchesOnSubviewsOfTheMessage() {
        let window = MessageWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let controller = UIViewController()
        let message = StubMessageView(frame: CGRect(x: 0, y: 400, width: 320, height: 168))
        let button = UIButton(frame: CGRect(x: 10, y: 10, width: 100, height: 44))
        message.addSubview(button)
        controller.view.addSubview(message)
        window.rootViewController = controller
        window.isHidden = false

        XCTAssertNotNil(window.hitTest(CGPoint(x: 40, y: 420), with: nil))
    }

    /// A modal blocks because its scrim is part of the message view — the same rule, not an
    /// exception to it.
    func testFullBleedMessageViewCapturesEverything() {
        let window = MessageWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let controller = UIViewController()
        let message = StubMessageView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        controller.view.addSubview(message)
        window.rootViewController = controller
        window.isHidden = false

        XCTAssertNotNil(window.hitTest(CGPoint(x: 160, y: 100), with: nil))
        XCTAssertNotNil(window.hitTest(CGPoint(x: 5, y: 560), with: nil))
    }
}
