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

    // MARK: - Artwork must not be cropped when the artwork *is* the message

    private func imageViews(in view: UIView) -> [UIImageView] {
        var found: [UIImageView] = []
        for subview in view.subviews {
            if let image = subview as? UIImageView { found.append(image) }
            found.append(contentsOf: imageViews(in: subview))
        }
        return found
    }

    /// A solid image of a given size, so the aspect ratio under test is the one intended rather
    /// than whatever a fixture happens to be.
    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// How much of the asset survives, given the mode the SDK chose and the bounds it laid out.
    /// `1.0` is the whole image; `0.24` means three quarters of it was cropped away.
    private func visibleFraction(of image: UIImage, in view: UIImageView) -> CGFloat {
        let bounds = view.bounds.size
        let asset = image.size
        guard bounds.width > 0, bounds.height > 0, asset.width > 0, asset.height > 0 else { return 0 }
        switch view.contentMode {
        case .scaleAspectFit:
            return 1
        case .scaleAspectFill:
            let scale = max(bounds.width / asset.width, bounds.height / asset.height)
            let visible = CGSize(width: min(asset.width, bounds.width / scale),
                                 height: min(asset.height, bounds.height / scale))
            return (visible.width * visible.height) / (asset.width * asset.height)
        default:
            return 1
        }
    }

    /// Both image-only compositions crop, and that is the spec's rule rather than an oversight:
    /// when the artwork *is* the message it goes full-bleed, and letterboxing it would frame a
    /// poster inside bars. A hero image inside a card is the opposite case — see the test below.
    ///
    /// IAM-8 was filed as "four of five views crop artwork", narrowed to the modal/fullscreen
    /// image-only disagreement, and then fixed on the wrong side: commit bada75d made fullscreen
    /// `contain`, when the UI spec says both image-only views are `cover` and it was the *modal*
    /// that disagreed. This asserts the spec.
    func testBothImageOnlyCompositionsFillTheirSurface() {
        let asset = image(width: 1200, height: 628)

        let fullscreenHost = IAMLayoutHost(size: CGSize(width: 375, height: 812))
        let fullscreen = FullscreenImageMessageView(
            message: makeMessage(type: .fullscreen, layout: .imageOnly),
            attributes: .defaults, image: asset, icon: nil, coordinator: nil)
        fullscreenHost.install(fullscreen)

        let modalHost = IAMLayoutHost(size: CGSize(width: 375, height: 812))
        let modal = ModalImageMessageView(
            message: makeMessage(type: .modal, layout: .imageOnly),
            attributes: .defaults, image: asset, icon: nil, coordinator: nil)
        modalHost.install(modal)

        guard let fullscreenImage = imageViews(in: fullscreen).first,
              let modalImage = imageViews(in: modal).first else {
            return XCTFail("expected an image view in each")
        }
        XCTAssertEqual(fullscreenImage.contentMode, .scaleAspectFill,
                       "an image-only fullscreen is full-bleed")
        XCTAssertEqual(modalImage.contentMode, .scaleAspectFill,
                       "an image-only modal fills its card for the same reason")
        XCTAssertEqual(fullscreenImage.contentMode, modalImage.contentMode,
                       "the two image-only compositions must agree")
    }

    /// The other half of the rule. A hero image sits *inside* a card alongside copy, so it is
    /// contained: never cropped, never distorted. This is the view IAM-8 should have changed.
    func testAHeroImageInsideACardIsContainedNotCropped() {
        let host = IAMLayoutHost(size: CGSize(width: 375, height: 812))
        let view = ModalMessageView(
            message: makeMessage(type: .modal, layout: .textWithImage),
            attributes: .defaults, image: image(width: 1200, height: 628),
            icon: nil, coordinator: nil)
        host.install(view)

        guard let imageView = imageViews(in: view).first else {
            return XCTFail("no hero image view")
        }
        XCTAssertEqual(imageView.contentMode, .scaleAspectFit,
                       "a hero image is contained; cropping it would cut copy baked into the art")
    }

    /// The deliberate exception, asserted so nobody "fixes" it by sweeping every view at once. A
    /// slideup icon is a small square thumbnail: filling its box is correct, and fitting would
    /// letterbox a 44pt icon with dead space.
    func testTheSlideupIconDeliberatelyFillsItsBox() {
        let host = IAMLayoutHost(size: CGSize(width: 375, height: 812))
        let view = SlideupMessageView(
            message: makeMessage(type: .slideup, iconURL: URL(string: "https://e.com/i.png")),
            attributes: .defaults, image: nil, icon: image(width: 200, height: 200),
            coordinator: nil)
        host.install(view)

        guard let imageView = imageViews(in: view).first else {
            return XCTFail("no icon view")
        }
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill,
                       "an icon fills its box on purpose; this is not the IAM-8 case")
    }

    // MARK: - Buttons are sized to their content, not to the leftover space

    /// Finds every `MessageButtonView` under a view, at any depth.
    private func buttonViews(in view: UIView) -> [MessageButtonView] {
        var found: [MessageButtonView] = []
        for subview in view.subviews {
            if let button = subview as? MessageButtonView { found.append(button) }
            found.append(contentsOf: buttonViews(in: subview))
        }
        return found
    }

    private func fullscreen(buttons: [GameballMessageButton],
                            body: String? = "Body",
                            size: CGSize,
                            contentSize: UIContentSizeCategory? = nil)
        -> (IAMLayoutHost, FullscreenMessageView) {
        let host = IAMLayoutHost(size: size, contentSize: contentSize)
        let view = FullscreenMessageView(message: makeMessage(type: .fullscreen,
                                                              body: body,
                                                              buttons: buttons),
                                         attributes: .defaults,
                                         image: nil,
                                         icon: nil,
                                         coordinator: nil)
        host.install(view)
        return (host, view)
    }

    /// The defect: the fullscreen content stack is pinned to both the top and the bottom of the
    /// screen, so something has to absorb the leftover height. The copy block pins its own height
    /// to its content at priority 250 and will not grow, and the button stack has no intrinsic
    /// size at all — so the buttons absorbed the difference. 465pt of a 667pt screen here, and
    /// 26% on a device, where artwork had already taken its share.
    ///
    /// **One button, specifically.** With two arranged buttons the stack resolves to its content
    /// height on its own, which is why the sibling two-button test below passes with or without
    /// the fix. The live campaign that showed this — 2055, "Track my order" — has exactly one.
    ///
    /// A single-line button is about 47pt against a 667pt screen: 7%. The bound is 15%, loose
    /// enough to survive a font change and tight enough to catch a stretch.
    func testFullscreenButtonIsSizedToItsContent() {
        let (_, view) = fullscreen(buttons: [makeButton()], size: CGSize(width: 375, height: 667))

        guard let button = buttonViews(in: view).first else {
            return XCTFail("the fullscreen view has no button")
        }
        let share = button.bounds.height / view.bounds.height
        XCTAssertLessThan(share, 0.15,
                          "button is \(Int(share * 100))% of the screen "
                        + "(\(Int(button.bounds.height))pt of \(Int(view.bounds.height))pt)")
    }

    /// A small screen has less slack to hand out, so a version of this that only checked a large
    /// screen could pass while the bug was still there.
    func testFullscreenButtonIsSizedToItsContentOnASmallScreen() {
        let (_, view) = fullscreen(buttons: [makeButton()], size: smallScreen)

        guard let button = buttonViews(in: view).first else {
            return XCTFail("the fullscreen view has no button")
        }
        XCTAssertLessThan(button.bounds.height / view.bounds.height, 0.15)
    }

    /// Short copy is the worst case: the less room the text needs, the more is left to absorb.
    func testShortCopyDoesNotInflateTheButton() {
        let (_, view) = fullscreen(buttons: [makeButton()], body: "Hi",
                                   size: CGSize(width: 375, height: 812))

        guard let button = buttonViews(in: view).first else {
            return XCTFail("the fullscreen view has no button")
        }
        XCTAssertLessThan(button.bounds.height / view.bounds.height, 0.15)
    }

    /// A regression guard, not a proof: this passed before the fix as well, because the
    /// stretch only ever happened with a single button. Kept so a future change to the button
    /// stack cannot break the two-button case unnoticed.
    func testTwoFullscreenButtonsAreBothSizedToTheirContent() {
        let (_, view) = fullscreen(buttons: [makeButton(id: "a", text: "Yes"),
                                             makeButton(id: "b", text: "No")],
                                   size: CGSize(width: 375, height: 667))

        let buttons = buttonViews(in: view)
        XCTAssertEqual(buttons.count, 2)
        for button in buttons {
            XCTAssertLessThan(button.bounds.height / view.bounds.height, 0.15)
        }
    }

    /// The slack has to go somewhere. It belongs to the copy, which can scroll — not to the
    /// button, which cannot. This is the positive half of the assertion above: without it, a
    /// fix that shrank the button and left a hole in the middle would pass.
    func testTheCopyAbsorbsTheLeftoverHeight() {
        let (_, view) = fullscreen(buttons: [makeButton()], body: "Hi",
                                   size: CGSize(width: 375, height: 812))

        guard let scroll = firstScrollView(in: view),
              let button = buttonViews(in: view).first else {
            return XCTFail("expected both a copy area and a button")
        }
        XCTAssertGreaterThan(scroll.bounds.height, button.bounds.height * 2,
                             "the copy area should take the slack, not the button")
    }

    /// Sizing to content must not shrink the button below the 44pt touch target — the fix for
    /// one accessibility problem must not create another.
    func testAContentSizedButtonStillMeetsTheTouchTarget() {
        let (_, view) = fullscreen(buttons: [makeButton()], size: CGSize(width: 375, height: 667))

        guard let button = buttonViews(in: view).first else {
            return XCTFail("the fullscreen view has no button")
        }
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
    }

    /// At the largest accessibility size the label wraps and the button legitimately grows. It
    /// still must not be claiming the leftover space, so the bound is looser rather than absent.
    func testAtTheLargestTextSizeTheButtonGrowsButDoesNotStretch() {
        let (_, view) = fullscreen(buttons: [makeButton(text: "Claim your reward now")],
                                   size: CGSize(width: 375, height: 667),
                                   contentSize: .accessibilityExtraExtraExtraLarge)

        guard let button = buttonViews(in: view).first else {
            return XCTFail("the fullscreen view has no button")
        }
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
        XCTAssertLessThan(button.bounds.height / view.bounds.height, 0.40)
    }

    /// The modal sizes its card to its content, so its buttons were never stretched. Asserted
    /// anyway: the fix touches shared button views, and a change that fixed fullscreen by
    /// pinning a height would break this.
    func testModalButtonsRemainSizedToTheirContent() {
        let host = IAMLayoutHost(size: CGSize(width: 375, height: 667))
        let view = ModalMessageView(message: makeMessage(type: .modal,
                                                         buttons: [makeButton()]),
                                    attributes: .defaults,
                                    image: nil,
                                    icon: nil,
                                    coordinator: nil)
        host.install(view)

        guard let button = buttonViews(in: view).first else {
            return XCTFail("the modal has no button")
        }
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
        XCTAssertLessThan(button.bounds.height, 120)
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
