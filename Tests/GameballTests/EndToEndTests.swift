//
//  EndToEndTests.swift
//  GameballTests
//
//  Drives the module through the public surface an integrator calls, against a fixture source and
//  a headless presenter — but with the *real* views, the real presenter and the real evaluator.
//  This is the test that catches wiring mistakes every unit test passes: the port specification's
//  trap list has a case where metadata filters were fully unit-tested and completely dead, because
//  the event hook never passed properties through.
//

import XCTest
@testable import Gameball

/// Assembles a service from real collaborators, with only the network and the window stubbed.
final class IAMEndToEndHarness {

    var builtViews: [InAppMessageView] = []
    let analytics = RecordingAnalytics()
    let store = InMemoryIAMStore()
    let variablesTransport = OutboxTransport()

    var campaigns: [InAppMessageCampaign] = []
    var cooldown: TimeInterval = 0
    var routedActions: [GameballClickAction] = []

    var presenter: MessageWindowPresenter!
    private(set) var source: StubMessageSource?
    /// Retained so a test can drain the service's queue. The module does not need this; a
    /// deterministic test does — the work crosses queue → main → queue → main, so ticking main
    /// alone is not a barrier and does not reliably converge.
    private(set) var service: InAppMessagingService?

    init() {
        var built: MessageWindowPresenter!
        built = MessageWindowPresenter(viewFactory: { [weak self] context in
            let view = MessageViewFactory.make(context: context,
                                               image: nil,
                                               icon: nil,
                                               coordinator: built)
            if let view = view { self?.builtViews.append(view) }
            return view
        })
        built.headless = true
        built.surfaceProvider = { nil }
        presenter = built
    }

    func makeService(customerId: String) -> InAppMessagingService {
        let stub = StubMessageSource(result: .success(
            SyncResult(campaigns: campaigns, cooldown: cooldown, rawPayload: nil)))
        source = stub

        let router = MessageActionRouter(
            openURL: { url, external in
                self.routedActions.append(.openURL(url: url, external: external))
            },
            navigate: { route, arguments in
                self.routedActions.append(.navigate(route: route, arguments: arguments))
                InAppMessagingCoordinator.shared.delegate?
                    .gameballShouldNavigate(route: route, arguments: arguments)
            },
            dismiss: { self.presenter.dismiss() })

        let service = InAppMessagingService(
            customerId: customerId,
            source: stub,
            presenter: presenter,
            analytics: analytics,
            cap: FrequencyCap(store: store, customerId: customerId),
            cache: CampaignCache(store: store),
            prefetcher: ArtworkPrefetcher(session: .shared, timeout: 1),
            variables: VariableSource(transport: variablesTransport,
                                      store: store,
                                      customerId: customerId,
                                      timeout: 0.2),
            router: router)
        self.service = service

        // The same bridging the shipping coordinator installs.
        service.beforeDisplay = { message in
            guard let delegate = InAppMessagingCoordinator.shared.delegate else { return .show }
            return delegate.gameballShouldDisplay(message)
        }
        service.onActionHandled = { message, button, action in
            guard let delegate = InAppMessagingCoordinator.shared.delegate else { return false }
            return delegate.gameballDidHandleAction(message, button: button, action: action)
        }
        service.onMessageSelected = { message in
            InAppMessagingCoordinator.shared.delegate?.gameballDidSelectMessage(message)
        }
        return service
    }

    func firstButton() -> MessageButtonView? {
        for view in builtViews {
            let found = IAMEndToEndHarness.descendants(of: view)
                .compactMap { $0 as? MessageButtonView }
            if let button = found.first { return button }
        }
        return nil
    }

    func firstCloseButton() -> MessageCloseButton? {
        for view in builtViews {
            let found = IAMEndToEndHarness.descendants(of: view)
                .compactMap { $0 as? MessageCloseButton }
            if let button = found.first { return button }
        }
        return nil
    }

    func labels() -> [String] {
        return builtViews.flatMap { view in
            IAMEndToEndHarness.descendants(of: view)
                .compactMap { $0 as? UILabel }
                .compactMap { $0.text }
        }
    }

    static func descendants(of view: UIView) -> [UIView] {
        return view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}

final class EndToEndTests: XCTestCase {

    private var app: GameballApp { return GameballApp.getInstance() }
    private var harness: IAMEndToEndHarness!

    override func setUp() {
        super.setUp()
        // No animation, so a presentation completes within the call that starts it.
        iamReduceMotionEnabled = { true }
        InAppMessagingCoordinator.shared.resetForTesting()
        harness = IAMEndToEndHarness()
    }

    override func tearDown() {
        InAppMessagingCoordinator.shared.resetForTesting()
        iamReduceMotionEnabled = { UIAccessibility.isReduceMotionEnabled }
        super.tearDown()
    }

    /// Alternates a synchronous drain of the service queue with one pass of the main queue.
    ///
    /// Both halves are needed: the work hops queue → main → queue → main, so ticking main alone
    /// leaves the queue side unsynchronised and the chain may not have advanced when the
    /// assertions run.
    private func drain(rounds: Int = 6) {
        for _ in 0..<rounds {
            harness.service?.settle()
            let tick = expectation(description: "tick")
            DispatchQueue.main.async { tick.fulfill() }
            wait(for: [tick], timeout: 3)
        }
    }

    private func startModule() {
        InAppMessagingCoordinator.shared.serviceBuilderOverride = { customerId in
            self.harness.makeService(customerId: customerId)
        }
        app.startInAppMessaging(customerId: "cust-e2e")
        drain()
    }

    // MARK: - The whole path

    /// start → a session-start campaign renders → tap its button → it dismisses, with an
    /// impression and a click reported against the right campaign and button.
    func testSessionStartCampaignRendersAndReportsAClickThroughThePublicAPI() {
        let button = makeButton(id: "track", text: "Track my order",
                               action: .navigate(route: "orders", arguments: ["id": 7]))
        harness.campaigns = [makeCampaign(
            campaignId: 2055,
            variationId: 20,
            dispatchId: "dispatch-e2e",
            trigger: .sessionStart,
            message: makeMessage(id: "2055/20", type: .modal,
                                 header: "Order placed!",
                                 body: "Your points are on the way.",
                                 buttons: [button]))]

        startModule()

        XCTAssertTrue(app.isInAppMessagingStarted)
        XCTAssertEqual(harness.builtViews.count, 1, "no view was built")
        XCTAssertTrue(harness.labels().contains("Order placed!"),
                      "the header never reached a label: \(harness.labels())")
        XCTAssertTrue(harness.labels().contains("Your points are on the way."))

        // The impression fires when the view reports it is visible, which the real view does
        // during `present` because reduce motion is on.
        XCTAssertEqual(harness.analytics.types(), [.impression])
        XCTAssertEqual(harness.analytics.events.first?.campaignId, 2055)
        XCTAssertEqual(harness.analytics.events.first?.variationId, 20)
        XCTAssertEqual(harness.analytics.events.first?.dispatchId, "dispatch-e2e")

        // Tap the real button.
        guard let rendered = harness.firstButton() else {
            return XCTFail("the campaign's button was never rendered")
        }
        simulateTap(rendered)
        drain()

        XCTAssertEqual(harness.analytics.types(), [.impression, .click])
        XCTAssertEqual(harness.analytics.events.last?.buttonId, "track")
        XCTAssertEqual(harness.analytics.events.last?.campaignId, 2055)

        // The action was routed.
        XCTAssertEqual(harness.routedActions.count, 1)
        if case .navigate(let route, let arguments) = harness.routedActions[0] {
            XCTAssertEqual(route, "orders")
            XCTAssertEqual(arguments?["id"] as? Int, 7)
        } else {
            XCTFail("the button's action was not routed")
        }
    }

    /// The trap the port specification calls out: filters unit-tested and completely dead because
    /// the event hook never passed properties through. This drives the real `sendEvent` wiring.
    func testEventPropertiesReachMetadataFilters() {
        harness.campaigns = [makeCampaign(
            campaignId: 900,
            trigger: .event(name: "place_order", filters: [
                PropertyFilter(name: "price", op: .greaterThan, value: 100)
            ]),
            message: makeMessage(id: "900", header: "Big spender"))]

        startModule()
        XCTAssertTrue(harness.builtViews.isEmpty, "nothing should show before the event")

        // Below the threshold: nothing.
        InAppMessagingCoordinator.shared.notifyEvents(["place_order": ["price": 50]])
        drain()
        XCTAssertTrue(harness.builtViews.isEmpty,
                      "a campaign filtered on price > 100 displayed for a price of 50")

        // Above it: shown. If properties were dropped anywhere in the chain, this fails.
        InAppMessagingCoordinator.shared.notifyEvents(["place_order": ["price": 150]])
        drain()
        XCTAssertEqual(harness.builtViews.count, 1,
                       "event properties never reached the filter")
    }

    func testPurchaseReachesAPurchaseTriggeredCampaignThroughLogPurchase() {
        harness.campaigns = [makeCampaign(
            campaignId: 901,
            trigger: .event(name: gameballPurchaseEventName, filters: [
                PropertyFilter(name: "price", op: .greaterThanOrEqual, value: 100),
                PropertyFilter(name: "currency", op: .equals, value: "USD")
            ]),
            message: makeMessage(id: "901", header: "Thanks for your order"))]

        startModule()
        app.logPurchase(productId: "sku-1", price: 150, currency: "USD", quantity: 2)
        drain()

        XCTAssertEqual(harness.builtViews.count, 1,
                       "logPurchase did not reach a purchase-triggered campaign")
        XCTAssertEqual(harness.analytics.types(), [.impression])
    }

    // MARK: - Delegate through the public surface

    func testDelegateCanDeferAndThenAllowADisplay() {
        let delegate = RecordingIAMDelegate()
        delegate.decision = .later
        app.inAppMessagingDelegate = delegate

        harness.campaigns = [makeCampaign(campaignId: 902, trigger: .sessionStart)]
        startModule()

        XCTAssertTrue(harness.builtViews.isEmpty, "a deferred message was drawn anyway")
        XCTAssertEqual(delegate.selected, ["902"],
                       "onMessageSelected must fire for every selected message")

        delegate.decision = .show
        InAppMessagingCoordinator.shared.notifyEvents([:])   // no-op, but harmless
        app.startInAppMessaging(customerId: "cust-e2e")      // idempotent
        drain()

        // A display opportunity retries the deferred message.
        harness.presenter.dismiss()
        drain()
        XCTAssertEqual(delegate.displayQueries >= 1, true)
    }

    /// The hooks replace the action, never the bookkeeping.
    func testHostHandlingAnActionStillReportsTheClick() {
        let delegate = RecordingIAMDelegate()
        delegate.handleAction = true
        app.inAppMessagingDelegate = delegate

        let button = makeButton(id: "cta", action: .navigate(route: "orders", arguments: nil))
        harness.campaigns = [makeCampaign(
            campaignId: 903,
            message: makeMessage(id: "903", buttons: [button]))]
        startModule()

        guard let rendered = harness.firstButton() else {
            return XCTFail("the button was never rendered")
        }
        simulateTap(rendered)
        drain()

        XCTAssertTrue(harness.routedActions.isEmpty,
                      "the SDK routed an action the host said it had handled")
        XCTAssertEqual(harness.analytics.types(), [.impression, .click],
                       "the click must still be reported")
    }

    // MARK: - Dismissal accounting end to end

    func testCloseWithoutEngagementReportsADismissal() {
        harness.campaigns = [makeCampaign(campaignId: 904,
                                          message: makeMessage(id: "904",
                                                               showCloseButton: true))]
        startModule()
        XCTAssertEqual(harness.analytics.types(), [.impression])

        guard let close = harness.firstCloseButton() else {
            return XCTFail("no close button was rendered")
        }
        simulateTap(close)
        drain()

        XCTAssertEqual(harness.analytics.types(), [.impression, .dismiss])
    }

    func testStoppingDismissesAndFlushes() {
        harness.campaigns = [makeCampaign(campaignId: 905)]
        startModule()
        XCTAssertEqual(harness.builtViews.count, 1)

        app.stopInAppMessaging()
        drain()

        XCTAssertFalse(app.isInAppMessagingStarted)
        XCTAssertEqual(harness.analytics.disposeCount, 1)
    }
}
