//
//  CompatibilityTests.swift
//  GameballTests
//
//  The isolation guarantee: upgrading to a version that contains this module must change nothing
//  for an integrator who never opts in. `GameballApp.swift` gained exactly two guarded lines, and
//  these tests are what make that claim checkable rather than asserted.
//

import XCTest
@testable import Gameball

final class CompatibilityTests: XCTestCase {

    private var app: GameballApp { return GameballApp.getInstance() }

    override func setUp() {
        super.setUp()
        InAppMessagingCoordinator.shared.resetForTesting()
    }

    override func tearDown() {
        InAppMessagingCoordinator.shared.resetForTesting()
        super.tearDown()
    }

    /// The `initializeCustomer` hook, invoked exactly as `GameballApp` invokes it, must do nothing
    /// when the host never opted in — no service, no request, no storage write.
    func testCustomerHookIsInertWithoutOptIn() {
        InAppMessagingCoordinator.shared.notifyCustomerChanged("cust-widget-only")

        XCTAssertFalse(app.isInAppMessagingStarted)
        for key in [IAMStoreKey.displayHistory, IAMStoreKey.campaignCache,
                    IAMStoreKey.analyticsOutbox, IAMStoreKey.variables] {
            XCTAssertNil(UserDefaults.standard.data(forKey: key))
        }
    }

    /// The `sendEvent` hook likewise. A widget-only integrator sends events all day.
    func testEventHookIsInertWithoutOptIn() {
        InAppMessagingCoordinator.shared.notifyEvents([
            "place_order": ["price": 100, "currency": "USD"],
            "view_product_page": ["productId": "sku-1"]
        ])

        XCTAssertFalse(app.isInAppMessagingStarted)
        XCTAssertNil(UserDefaults.standard.data(forKey: IAMStoreKey.analyticsOutbox))
    }

    /// Neither hook may throw into the widget's code path, whatever it is handed.
    func testHooksSurviveDegenerateInput() {
        InAppMessagingCoordinator.shared.notifyCustomerChanged("")
        InAppMessagingCoordinator.shared.notifyEvents([:])
        InAppMessagingCoordinator.shared.notifyEvents(["": [:]])
        XCTAssertFalse(app.isInAppMessagingStarted)
    }

    /// The module's data belongs in its own suite, never in the host app's preferences plist.
    func testIAMStorageIsInItsOwnSuite() {
        let suite = "co.gameball.inappmessaging.compat-test"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let store = UserDefaultsIAMStore(suiteName: suite)
        store.set(Data("history".utf8), forKey: IAMStoreKey.displayHistory)
        store.set(Data("payload".utf8), forKey: IAMStoreKey.campaignCache)
        store.set(Data("outbox".utf8), forKey: IAMStoreKey.analyticsOutbox)
        store.set(Data("values".utf8), forKey: IAMStoreKey.variables)

        for key in [IAMStoreKey.displayHistory, IAMStoreKey.campaignCache,
                    IAMStoreKey.analyticsOutbox, IAMStoreKey.variables] {
            XCTAssertNil(UserDefaults.standard.data(forKey: key),
                         "\(key) leaked into UserDefaults.standard")
        }
    }

    func testStandardDefaultsHoldNoModuleKeys() {
        let leaked = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(IAMStoreKey.prefix) }
        XCTAssertTrue(leaked.isEmpty, "the module left keys in UserDefaults.standard: \(leaked)")
    }

    /// Nothing schedules work before opt-in: no analytics timer, no sync, no prefetch.
    func testNoServiceExistsBeforeOptIn() {
        var built = 0
        InAppMessagingCoordinator.shared.serviceBuilderOverride = { customerId in
            built += 1
            return IAMEndToEndHarness().makeService(customerId: customerId)
        }

        InAppMessagingCoordinator.shared.notifyCustomerChanged("cust-1")
        InAppMessagingCoordinator.shared.notifyEvents(["e": [:]])
        InAppMessagingCoordinator.shared.logPurchase(productId: "sku", price: 1,
                                                     currency: "USD", quantity: 1,
                                                     properties: nil)

        XCTAssertEqual(built, 0, "a service was assembled without the host opting in")
        XCTAssertFalse(app.isInAppMessagingStarted)
    }

    /// Opting in and out must leave the widget surface exactly as it was.
    func testWidgetSurfaceIsUnchangedByStartingAndStopping() {
        let initializedBefore = app.initialized
        let configBefore = app.currentConfig
        let customerBefore = app.currentCustomerId

        InAppMessagingCoordinator.shared.serviceBuilderOverride = { customerId in
            return IAMEndToEndHarness().makeService(customerId: customerId)
        }
        app.startInAppMessaging(customerId: "cust-1")
        app.stopInAppMessaging()

        XCTAssertEqual(app.initialized, initializedBefore)
        XCTAssertTrue(app.currentConfig == nil ? configBefore == nil : configBefore != nil)
        XCTAssertEqual(app.currentCustomerId, customerBefore)
    }

    /// The public in-app messaging surface must not have displaced any widget entry point.
    func testWidgetEntryPointsStillExist() {
        XCTAssertNotNil(GameballApp.getInstance())
        // Compile-time proof the widget signatures are intact; never invoked.
        let _: (GameballConfig, ((Error?) -> Void)?) -> Void = { config, completion in
            GameballApp.getInstance().`init`(config: config, completion: completion)
        }
        let _: (ShowProfileRequest) -> Void = { request in
            GameballApp.getInstance().showProfile(request)
        }
        let _: () -> Void = { GameballApp.getInstance().hideProfile() }
    }
}
