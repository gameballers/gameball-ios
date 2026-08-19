//
//  PublicAPITests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// A delegate that records what it was asked, and can be deallocated on demand so the weak
/// reference can be proven.
final class RecordingIAMDelegate: GameballInAppMessagingDelegate {
    var decision: GameballDisplayDecision = .show
    var handleAction = false
    private(set) var selected: [String] = []
    private(set) var navigations: [(String, [String: Any]?)] = []
    private(set) var displayQueries = 0

    func gameballShouldDisplay(_ message: GameballInAppMessage) -> GameballDisplayDecision {
        displayQueries += 1
        return decision
    }

    func gameballDidHandleAction(_ message: GameballInAppMessage,
                                button: GameballMessageButton?,
                                action: GameballClickAction) -> Bool {
        return handleAction
    }

    func gameballDidSelectMessage(_ message: GameballInAppMessage) {
        selected.append(message.id)
    }

    func gameballShouldNavigate(route: String, arguments: [String: Any]?) {
        navigations.append((route, arguments))
    }
}

/// Implements nothing, to prove every protocol method has a working default.
final class BareIAMDelegate: GameballInAppMessagingDelegate {}

final class PublicAPITests: XCTestCase {

    private var app: GameballApp { return GameballApp.getInstance() }

    override func setUp() {
        super.setUp()
        InAppMessagingCoordinator.shared.resetForTesting()
    }

    override func tearDown() {
        InAppMessagingCoordinator.shared.resetForTesting()
        super.tearDown()
    }

    // MARK: - Default state

    func testInAppMessagingIsNotStartedInitially() {
        XCTAssertFalse(app.isInAppMessagingStarted)
    }

    /// Dormant until a customer exists — and it must not crash, throw, or start anything.
    func testStartingWithoutACustomerStaysDormantAndSaysSo() {
        let logs = capturingIAMLog { self.app.startInAppMessaging(customerId: nil) }
        XCTAssertFalse(app.isInAppMessagingStarted)
        XCTAssertTrue(logs.contains { $0.contains("before a customer was identified") },
                      "the dormant reason was not reported: \(logs)")
    }

    func testEmptyCustomerIdIsTreatedAsAbsent() {
        app.startInAppMessaging(customerId: "")
        XCTAssertFalse(app.isInAppMessagingStarted)
    }

    // MARK: - Delegate

    /// `GameballApp` is an immortal singleton, so a strong reference would leak the host's view
    /// controller for the life of the app.
    func testDelegateIsHeldWeakly() {
        autoreleasepool {
            let delegate = RecordingIAMDelegate()
            app.inAppMessagingDelegate = delegate
            XCTAssertNotNil(app.inAppMessagingDelegate)
        }
        XCTAssertNil(app.inAppMessagingDelegate, "the delegate was retained")
    }

    func testDelegateCanBeAssignedBeforeStarting() {
        let delegate = RecordingIAMDelegate()
        app.inAppMessagingDelegate = delegate
        XCTAssertTrue(app.inAppMessagingDelegate === delegate,
                      "assigning before start must be honoured — ordering should not matter")
    }

    func testDelegateCanBeCleared() {
        let delegate = RecordingIAMDelegate()
        app.inAppMessagingDelegate = delegate
        app.inAppMessagingDelegate = nil
        XCTAssertNil(app.inAppMessagingDelegate)
    }

    func testProtocolDefaultsCoverEveryMethod() {
        let bare = BareIAMDelegate()
        let message = makeMessage()
        XCTAssertEqual(bare.gameballShouldDisplay(message), .show)
        XCTAssertFalse(bare.gameballDidHandleAction(message, button: nil, action: .dismiss))
        // Neither of these should do anything, and neither should trap.
        bare.gameballDidSelectMessage(message)
        bare.gameballShouldNavigate(route: "orders", arguments: nil)
    }

    // MARK: - logPurchase

    func testLogPurchaseBeforeStartingIsANoOpThatSaysSo() {
        let logs = capturingIAMLog {
            self.app.logPurchase(productId: "sku-1", price: 10, currency: "USD")
        }
        XCTAssertTrue(logs.contains { $0.contains("logPurchase") },
                      "an ignored purchase was not reported: \(logs)")
    }

    func testLogPurchaseHasDefaultQuantityAndProperties() {
        // Compiles with only the three required arguments — the surface an integrator will use.
        app.logPurchase(productId: "sku-1", price: 10, currency: "USD")
    }

    // MARK: - Idempotence and customer change

    func testStartingTwiceForTheSameCustomerBuildsOneService() {
        var built: [String] = []
        InAppMessagingCoordinator.shared.serviceBuilderOverride = { customerId in
            built.append(customerId)
            return IAMEndToEndHarness().makeService(customerId: customerId)
        }

        app.startInAppMessaging(customerId: "cust-1")
        app.startInAppMessaging(customerId: "cust-1")

        XCTAssertEqual(built, ["cust-1"], "the same customer should not rebuild the service")
        XCTAssertTrue(app.isInAppMessagingStarted)
    }

    /// A different customer refetches and resets, so the host need not stop first.
    func testStartingForADifferentCustomerRebuildsAndResets() {
        var built: [String] = []
        InAppMessagingCoordinator.shared.serviceBuilderOverride = { customerId in
            built.append(customerId)
            return IAMEndToEndHarness().makeService(customerId: customerId)
        }

        app.startInAppMessaging(customerId: "cust-1")
        app.startInAppMessaging(customerId: "cust-2")

        XCTAssertEqual(built, ["cust-1", "cust-2"])
        XCTAssertTrue(app.isInAppMessagingStarted)
    }

    func testStopFlipsItBack() {
        InAppMessagingCoordinator.shared.serviceBuilderOverride = { customerId in
            return IAMEndToEndHarness().makeService(customerId: customerId)
        }
        app.startInAppMessaging(customerId: "cust-1")
        XCTAssertTrue(app.isInAppMessagingStarted)

        app.stopInAppMessaging()
        XCTAssertFalse(app.isInAppMessagingStarted)
    }

    /// Opting in before a customer exists must start the module as soon as one is identified,
    /// which is what the `initializeCustomer` hook is for.
    func testCustomerIdentifiedAfterOptInStartsTheModule() {
        var built: [String] = []
        InAppMessagingCoordinator.shared.serviceBuilderOverride = { customerId in
            built.append(customerId)
            return IAMEndToEndHarness().makeService(customerId: customerId)
        }

        app.startInAppMessaging(customerId: nil)
        XCTAssertFalse(app.isInAppMessagingStarted)

        InAppMessagingCoordinator.shared.notifyCustomerChanged("cust-7")
        XCTAssertEqual(built, ["cust-7"])
        XCTAssertTrue(app.isInAppMessagingStarted)
    }

    /// And a customer change without opting in must do nothing at all.
    func testCustomerChangeWithoutOptInDoesNothing() {
        var built: [String] = []
        InAppMessagingCoordinator.shared.serviceBuilderOverride = { customerId in
            built.append(customerId)
            return IAMEndToEndHarness().makeService(customerId: customerId)
        }

        InAppMessagingCoordinator.shared.notifyCustomerChanged("cust-7")
        XCTAssertTrue(built.isEmpty)
        XCTAssertFalse(app.isInAppMessagingStarted)
    }

    func testEventsWithoutOptInDoNothing() {
        InAppMessagingCoordinator.shared.notifyEvents(["place_order": ["price": 100]])
        XCTAssertFalse(app.isInAppMessagingStarted)
    }
}
