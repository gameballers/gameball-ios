//
//  MessageLayoutResilienceTests.swift
//  GameballTests
//
//  The defects the port specification ranks most expensive are all layout: copy that clips,
//  buttons that overflow, a card that fills the screen because someone made it scrollable, a
//  close button too small to hit. Every test here is one of those.
//

import XCTest
@testable import Gameball

/// Hosts a message view in a real window so Auto Layout actually runs, with optional trait
/// overrides for content size and layout direction.
final class IAMLayoutHost {
    let window: UIWindow
    let root: UIViewController
    let child: UIViewController

    init(size: CGSize,
         contentSize: UIContentSizeCategory? = nil,
         rightToLeft: Bool = false) {
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        root = UIViewController()
        window.rootViewController = root
        window.isHidden = false

        child = UIViewController()
        root.addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: root.view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: root.view.trailingAnchor)
        ])
        child.didMove(toParent: root)

        if let contentSize = contentSize {
            root.setOverrideTraitCollection(
                UITraitCollection(preferredContentSizeCategory: contentSize), forChild: child)
        }
        if rightToLeft {
            // The *test* forces the direction. The SDK must never assign this itself, which is
            // what `testRTLDoesNotMutateGlobalAppearance` guards.
            child.view.semanticContentAttribute = .forceRightToLeft
        }
    }

    func install(_ view: InAppMessageView) {
        view.install(in: child.view)
        layout()
    }

    func layout() {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        child.view.setNeedsLayout()
        child.view.layoutIfNeeded()
    }
}

final class MessageLayoutResilienceTests: XCTestCase {

    private let smallScreen = CGSize(width: 320, height: 568)

    private let longCopy = String(repeating: "This is a fairly long sentence of campaign copy "
                                + "that a marketer pasted in without checking the preview. ",
                                  count: 12)

    override func setUp() {
        super.setUp()
        iamReduceMotionEnabled = { true }   // no animation in layout tests
    }

    override func tearDown() {
        iamReduceMotionEnabled = { UIAccessibility.isReduceMotionEnabled }
        super.tearDown()
    }

    private func modal(header: String? = "Header",
                       body: String? = "Body",
                       image: UIImage? = nil,
                       buttons: [GameballMessageButton] = [],
                       showCloseButton: Bool = true) -> ModalMessageView {
        return ModalMessageView(message: makeMessage(type: .modal,
                                                     header: header,
                                                     body: body,
                                                     buttons: buttons,
                                                     showCloseButton: showCloseButton),
                                attributes: .defaults,
                                image: image,
                                icon: nil,
                                coordinator: nil)
    }

    // MARK: - Overflow

    func testModalWithLongCopyDoesNotOverflowOnSmallScreen() {
        let host = IAMLayoutHost(size: smallScreen)
        let view = modal(body: longCopy)
        host.install(view)

        XCTAssertLessThanOrEqual(view.bounds.height, smallScreen.height + 0.5)
        guard let scroll = firstScrollView(in: view) else {
            return XCTFail("copy is not in a scroll view, so it can only clip")
        }
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height,
                             "long copy should be scrollable")
        XCTAssertGreaterThan(scroll.bounds.height, 0)
    }

    func testModalAtDoubleTextScaleDoesNotOverflow() {
        let host = IAMLayoutHost(size: smallScreen,
                                 contentSize: .accessibilityExtraExtraExtraLarge)
        let view = modal(body: longCopy)
        host.install(view)

        XCTAssertLessThanOrEqual(view.bounds.height, smallScreen.height + 0.5)
        XCTAssertLessThanOrEqual(view.bounds.width, smallScreen.width + 0.5)
    }

    /// The obvious "make it scrollable" fix makes every card full height. A one-line message
    /// must stay small.
    func testShortModalStaysShort() {
        let host = IAMLayoutHost(size: smallScreen)
        let view = modal(header: "Hi", body: "Short.")
        host.install(view)

        guard let card = firstCard(in: view) else { return XCTFail("no card found") }
        XCTAssertLessThan(card.bounds.height, smallScreen.height * 0.6,
                          "a one-line message filled \(card.bounds.height)pt of a "
                        + "\(smallScreen.height)pt screen")
        XCTAssertGreaterThan(card.bounds.height, 0)
    }

    func testFullscreenLongCopyScrolls() {
        let host = IAMLayoutHost(size: smallScreen)
        let view = FullscreenMessageView(message: makeMessage(type: .fullscreen,
                                                              body: longCopy),
                                         attributes: .defaults,
                                         image: nil,
                                         icon: nil,
                                         coordinator: nil)
        host.install(view)

        guard let scroll = firstScrollView(in: view) else {
            return XCTFail("fullscreen copy is not scrollable")
        }
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertLessThanOrEqual(view.bounds.height, smallScreen.height + 0.5)
    }

    // MARK: - Buttons

    func testButtonsWrapRatherThanOverflow() {
        let host = IAMLayoutHost(size: smallScreen)
        let buttons = [makeButton(id: "a", text: "Twenty five characters ok"),
                       makeButton(id: "b", text: "Another twenty five chars")]
        let view = modal(buttons: buttons)
        host.install(view)

        let buttonViews = allSubviews(of: view).compactMap { $0 as? MessageButtonView }
        XCTAssertEqual(buttonViews.count, 2)

        guard let stack = allSubviews(of: view).compactMap({ $0 as? MessageButtonStack }).first else {
            return XCTFail("buttons are not in a wrapping stack")
        }
        XCTAssertEqual(stack.axis, .vertical,
                       "two long labels should have stacked vertically")
        for button in buttonViews {
            XCTAssertLessThanOrEqual(button.bounds.width, stack.bounds.width + 0.5,
                                     "a button overflowed its stack")
        }
    }

    func testShortButtonsStaySideBySide() {
        let host = IAMLayoutHost(size: smallScreen)
        let view = modal(buttons: [makeButton(id: "a", text: "Yes"),
                                   makeButton(id: "b", text: "No")])
        host.install(view)

        guard let stack = allSubviews(of: view).compactMap({ $0 as? MessageButtonStack }).first else {
            return XCTFail("buttons are not in a wrapping stack")
        }
        XCTAssertEqual(stack.axis, .horizontal, "two short labels should fit on one row")
    }

    // MARK: - Slideup extent

    /// A slideup must stay a band. If it filled the screen it would also swallow every touch,
    /// because the window's passthrough rule is defined by the message view's extent.
    func testSlideupFitsItsBandOnly() {
        let host = IAMLayoutHost(size: smallScreen)
        let view = SlideupMessageView(message: makeMessage(type: .slideup, body: longCopy),
                                       attributes: .defaults,
                                       image: nil,
                                       icon: nil,
                                       coordinator: nil)
        host.install(view)

        XCTAssertLessThanOrEqual(view.bounds.height,
                                 MessageViewAttributes.Slideup.defaults.maxHeight + 0.5,
                                 "the slideup grew past its band")
        XCTAssertLessThan(view.bounds.height, smallScreen.height / 2)
        XCTAssertGreaterThan(view.bounds.height, 0)
    }

    func testSlideupSitsAtItsConfiguredEdge() {
        let bottomHost = IAMLayoutHost(size: smallScreen)
        let bottom = SlideupMessageView(message: makeMessage(type: .slideup,
                                                             slidePosition: .bottom),
                                         attributes: .defaults, image: nil, icon: nil,
                                         coordinator: nil)
        bottomHost.install(bottom)
        XCTAssertGreaterThan(bottom.frame.midY, smallScreen.height / 2)

        let topHost = IAMLayoutHost(size: smallScreen)
        let top = SlideupMessageView(message: makeMessage(type: .slideup, slidePosition: .top),
                                      attributes: .defaults, image: nil, icon: nil,
                                      coordinator: nil)
        topHost.install(top)
        XCTAssertLessThan(top.frame.midY, smallScreen.height / 2)
    }

    // MARK: - Touch targets

    func testCloseButtonMeetsFortyFourPointTarget() {
        let host = IAMLayoutHost(size: smallScreen)
        let view = modal(showCloseButton: true)
        host.install(view)

        guard let close = allSubviews(of: view).compactMap({ $0 as? MessageCloseButton }).first else {
            return XCTFail("no close button was built")
        }
        XCTAssertGreaterThanOrEqual(close.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(close.bounds.height, 44)
    }

    func testCloseButtonIsAbsentWhenNotRequested() {
        let host = IAMLayoutHost(size: smallScreen)
        let view = modal(showCloseButton: false)
        host.install(view)
        XCTAssertTrue(allSubviews(of: view).compactMap { $0 as? MessageCloseButton }.isEmpty)
    }

    // MARK: - Right-to-left

    /// Mirroring is delivered by *directional* constraints, not by frame arithmetic.
    ///
    /// UIKit resolves `leading`/`trailing` against the application's layout direction, and
    /// `semanticContentAttribute` does not propagate to arbitrary subviews — so a unit test
    /// cannot make a subtree lay out right-to-left. What it can check is the thing this module
    /// actually controls: that no horizontal constraint was written with `.left` or `.right`,
    /// which are the attributes that would refuse to mirror in an Arabic locale.
    func testCloseButtonIsPinnedWithDirectionalConstraints() {
        let host = IAMLayoutHost(size: smallScreen)
        var checked = 0

        for view in everyViewKind() {
            host.install(view)
            guard let close = allSubviews(of: view)
                .compactMap({ $0 as? MessageCloseButton }).first else { continue }

            let candidates = (close.superview?.constraints ?? []) + close.constraints
            let horizontal = candidates.filter { constraint in
                constraint.firstItem === close || constraint.secondItem === close
            }
            XCTAssertFalse(horizontal.isEmpty,
                           "\(type(of: view)) close button has no constraints")

            for constraint in horizontal {
                for attribute in [constraint.firstAttribute, constraint.secondAttribute] {
                    XCTAssertNotEqual(attribute, .left,
                                      "\(type(of: view)) pins its close button with .left")
                    XCTAssertNotEqual(attribute, .right,
                                      "\(type(of: view)) pins its close button with .right")
                    XCTAssertNotEqual(attribute, .leftMargin,
                                      "\(type(of: view)) uses .leftMargin")
                    XCTAssertNotEqual(attribute, .rightMargin,
                                      "\(type(of: view)) uses .rightMargin")
                }
            }
            checked += 1
        }

        XCTAssertGreaterThan(checked, 0, "no view exposed a close button to check")
    }

    /// The same rule for the view-to-view constraints each view installs itself.
    ///
    /// Constraints involving a `UILayoutGuide` are skipped: UIKit generates the geometry
    /// constraints for `safeAreaLayoutGuide` itself with absolute `.left`/`.right` attributes,
    /// and those are its own, not ours. The anchors we attach to that guide are directional and
    /// are covered by the close-button test above.
    func testViewsUseNoAbsoluteHorizontalConstraints() {
        let host = IAMLayoutHost(size: smallScreen)
        for view in everyViewKind() {
            host.install(view)
            let ours = view.constraints.filter {
                $0.firstItem is UIView && ($0.secondItem == nil || $0.secondItem is UIView)
            }
            for constraint in ours {
                for attribute in [constraint.firstAttribute, constraint.secondAttribute] {
                    XCTAssertNotEqual(attribute, .left,
                                      "\(type(of: view)) installed a .left constraint")
                    XCTAssertNotEqual(attribute, .right,
                                      "\(type(of: view)) installed a .right constraint")
                }
            }
        }
    }

    /// This repo shipped exactly this bug — right-to-left layout leaking into the host app —
    /// and fixed it in 8f8f368. Building every view must leave the global proxy untouched.
    func testRTLDoesNotMutateGlobalAppearance() {
        let before = UIView.appearance().semanticContentAttribute
        XCTAssertEqual(before, .unspecified, "precondition: the proxy starts clean")

        let host = IAMLayoutHost(size: smallScreen, rightToLeft: true)
        for view in everyViewKind() {
            host.install(view)
            XCTAssertEqual(UIView.appearance().semanticContentAttribute, .unspecified,
                           "\(type(of: view)) mutated UIView.appearance()")
        }
    }

    // MARK: - Reduce motion

    func testReduceMotionSkipsEntranceAnimation() {
        iamReduceMotionEnabled = { true }
        let host = IAMLayoutHost(size: smallScreen)
        let view = modal()
        host.install(view)

        view.present(completion: nil)
        // No animation to wait for: presented is true by the time present returns.
        XCTAssertTrue(view.presented)
        XCTAssertEqual(view.alpha, 1, accuracy: 0.01)
    }

    /// With motion allowed, `didPresent` is deferred to the animation's completion rather than
    /// reported synchronously. That deferral is the contract — it is what anchors the impression
    /// to the message being visible rather than inserted.
    ///
    /// Only the deferral is asserted, not the eventual completion: CoreAnimation does not run
    /// reliably for a window that was never on a real screen, so waiting on it here would be
    /// testing UIKit's scheduler rather than this module.
    func testWithoutReduceMotionTheEntranceIsDeferred() {
        iamReduceMotionEnabled = { false }
        let host = IAMLayoutHost(size: smallScreen)
        let view = modal()
        host.install(view)

        view.present(completion: nil)
        XCTAssertFalse(view.presented,
                       "presented should wait for the entrance animation to finish")
    }

    // MARK: - Missing artwork

    /// A dead image URL costs the picture, never the message.
    func testDeadImageURLStillRendersTheMessage() {
        let host = IAMLayoutHost(size: smallScreen)
        let view = modal(header: "Still here", body: "And so is the body.", image: nil)
        host.install(view)

        let labels = copyLabels(in: view)
        XCTAssertTrue(labels.contains { $0.text == "Still here" })
        XCTAssertTrue(labels.contains { $0.text == "And so is the body." })
        XCTAssertTrue(allSubviews(of: view).compactMap { $0 as? UIImageView }.isEmpty,
                      "no image view should be built when there is no image")
    }

    func testLabelsOptIntoDynamicType() {
        let host = IAMLayoutHost(size: smallScreen)
        let view = modal()
        host.install(view)

        let labels = copyLabels(in: view)
        XCTAssertFalse(labels.isEmpty)
        for label in labels {
            XCTAssertTrue(label.adjustsFontForContentSizeCategory,
                          "a label does not follow Dynamic Type")
            XCTAssertEqual(label.numberOfLines, 0, "a label can truncate")
        }
    }

    // MARK: - Helpers

    private func everyViewKind() -> [InAppMessageView] {
        let image = UIImage()
        return [
            SlideupMessageView(message: makeMessage(type: .slideup), attributes: .defaults,
                               image: nil, icon: image, coordinator: nil),
            ModalMessageView(message: makeMessage(type: .modal), attributes: .defaults,
                             image: image, icon: nil, coordinator: nil),
            ModalImageMessageView(message: makeMessage(type: .modal, layout: .imageOnly),
                                  attributes: .defaults, image: image, icon: nil,
                                  coordinator: nil),
            FullscreenMessageView(message: makeMessage(type: .fullscreen), attributes: .defaults,
                                  image: image, icon: nil, coordinator: nil),
            FullscreenImageMessageView(message: makeMessage(type: .fullscreen,
                                                            layout: .imageOnly),
                                        attributes: .defaults, image: image, icon: nil,
                                        coordinator: nil)
        ]
    }

    /// Only the labels this module builds. A `UIButton` owns an internal `titleLabel` that
    /// UIKit configures, and asserting about it would be asserting about UIKit.
    private func copyLabels(in view: UIView) -> [UILabel] {
        return allSubviews(of: view).compactMap { $0 as? UILabel }.filter { label in
            var node = label.superview
            while let current = node {
                if current is UIButton { return false }
                node = current.superview
            }
            return true
        }
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        return view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        return allSubviews(of: view).compactMap { $0 as? UIScrollView }.first
    }

    /// The card is the modal's only rounded opaque child of the scrim.
    private func firstCard(in view: UIView) -> UIView? {
        return view.subviews.first { $0.layer.cornerRadius > 0 }
    }
}
