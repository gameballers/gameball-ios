//
//  LogPurchaseTests.swift
//  GameballTests
//
//  `logPurchase` reports a purchase to Gameball as an event named `purchase`, sent through
//  `sendEvent` — the same contract as the Flutter SDK. These drive the real `GameballApp` against
//  a stubbed events endpoint.
//

import XCTest
@testable import Gameball

final class LogPurchaseTests: XCTestCase {

    private var app: GameballApp { return GameballApp.getInstance() }
    private var restoreNetwork: (() -> Void)?

    override func setUp() {
        super.setUp()
        InAppMessagingCoordinator.shared.resetForTesting()
        restoreNetwork = routeGameballRequestsThroughStub()
    }

    override func tearDown() {
        restoreNetwork?()
        InAppMessagingCoordinator.shared.resetForTesting()
        super.tearDown()
    }

    /// The case the method used to get wrong: a purchase logged while messaging was not running
    /// was dropped on the device, so Gameball never learned it happened.
    func testLogPurchaseBeforeStartingStillSendsThePurchaseToGameball() throws {
        XCTAssertFalse(app.isInAppMessagingStarted, "precondition: messaging never started")

        let sent = expectation(description: "the send completed")
        var succeeded: Bool?
        try app.logPurchase(customerId: "cust-1", productId: "sku-1",
                            price: 150, currency: "USD") { success, _ in
            succeeded = success
            sent.fulfill()
        }
        wait(for: [sent], timeout: 5)

        let bodies = IAMHTTPStub.eventBodies()
        XCTAssertEqual(bodies.count, 1, "the purchase never reached Gameball")
        XCTAssertEqual(bodies.first?["customerId"] as? String, "cust-1")
        let events = bodies.first?["events"] as? [String: Any]
        XCTAssertEqual(events.map { Array($0.keys) }, ["purchase"])
        XCTAssertEqual(succeeded, true)
    }

    /// Campaign filters read these fields by name, and Flutter sends exactly these — a field
    /// renamed or dropped here is a filter that silently never matches on iOS.
    func testLogPurchaseSendsItsFieldsAsThePurchaseMetadata() throws {
        let sent = expectation(description: "the send completed")
        try app.logPurchase(customerId: "cust-1", productId: "sku-1", price: 49.99,
                            currency: "USD", quantity: 2,
                            properties: ["source": "app"]) { _, _ in sent.fulfill() }
        wait(for: [sent], timeout: 5)

        let events = IAMHTTPStub.eventBodies().first?["events"] as? [String: Any]
        let purchase = events?["purchase"] as? [String: Any]
        XCTAssertEqual(purchase?["productId"] as? String, "sku-1")
        XCTAssertEqual(purchase?["price"] as? Double, 49.99)
        XCTAssertEqual(purchase?["currency"] as? String, "USD")
        XCTAssertEqual(purchase?["quantity"] as? Int, 2)
        XCTAssertEqual(purchase?["source"] as? String, "app")
        XCTAssertEqual(purchase?.count, 5, "unexpected fields: \(purchase ?? [:])")
    }

    /// `Event`'s own rule: a purchase must belong to someone. Nothing is sent and the completion
    /// is never called, so the throw is the whole answer.
    func testLogPurchaseWithAnEmptyCustomerIdThrowsAndSendsNothing() {
        let completed = expectation(description: "the completion was called")
        completed.isInverted = true

        XCTAssertThrowsError(try app.logPurchase(customerId: "", productId: "sku-1",
                                                 price: 10, currency: "USD") { _, _ in
            completed.fulfill()
        }) { error in
            guard case GameballError.emptyCustomerId? = error as? GameballError else {
                return XCTFail("expected emptyCustomerId, got \(error)")
            }
        }
        wait(for: [completed], timeout: 0.5)
        XCTAssertTrue(IAMHTTPStub.eventBodies().isEmpty, "a purchase with no customer was sent")
    }
}
