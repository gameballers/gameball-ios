//
//  IAMStoreTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class IAMStoreTests: XCTestCase {

    /// A suite of its own, so no test can touch the suite the SDK ships with.
    private let testSuite = "co.gameball.inappmessaging.tests"

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: testSuite)
        super.tearDown()
    }

    // MARK: - Protocol behaviour, exercised against both implementations

    private func assertStoreContract(_ store: IAMStore, label: String) {
        XCTAssertNil(store.data(forKey: IAMStoreKey.variables), "\(label): should start empty")

        store.set(Data("first".utf8), forKey: IAMStoreKey.variables)
        XCTAssertEqual(store.data(forKey: IAMStoreKey.variables), Data("first".utf8), label)

        store.set(Data("second".utf8), forKey: IAMStoreKey.variables)
        XCTAssertEqual(store.data(forKey: IAMStoreKey.variables), Data("second".utf8),
                       "\(label): a write must overwrite")

        store.set(nil, forKey: IAMStoreKey.variables)
        XCTAssertNil(store.data(forKey: IAMStoreKey.variables), "\(label): nil must remove")

        store.set(Data("a".utf8), forKey: IAMStoreKey.displayHistory)
        store.set(Data("b".utf8), forKey: IAMStoreKey.campaignCache)
        store.removeAll()
        XCTAssertNil(store.data(forKey: IAMStoreKey.displayHistory), "\(label): removeAll")
        XCTAssertNil(store.data(forKey: IAMStoreKey.campaignCache), "\(label): removeAll")
    }

    func testInMemoryStoreHonoursTheContract() {
        assertStoreContract(InMemoryIAMStore(), label: "in-memory")
    }

    func testUserDefaultsStoreHonoursTheContract() {
        assertStoreContract(UserDefaultsIAMStore(suiteName: testSuite), label: "user-defaults")
    }

    // MARK: - Suite isolation

    /// The module's data must not land in the host app's preferences plist.
    func testUserDefaultsStoreWritesToItsSuiteNotStandard() {
        let store = UserDefaultsIAMStore(suiteName: testSuite)
        store.set(Data("payload".utf8), forKey: IAMStoreKey.campaignCache)

        XCTAssertNil(UserDefaults.standard.data(forKey: IAMStoreKey.campaignCache),
                     "the module wrote into UserDefaults.standard")
        XCTAssertEqual(UserDefaults(suiteName: testSuite)?.data(forKey: IAMStoreKey.campaignCache),
                       Data("payload".utf8))
    }

    /// `removeAll` clears what the module owns and nothing else, so a shared suite cannot
    /// have unrelated keys wiped out from under it.
    func testRemoveAllLeavesForeignKeysAlone() {
        let defaults = UserDefaults(suiteName: testSuite)
        defaults?.set(Data("host".utf8), forKey: "host_owned_key")

        let store = UserDefaultsIAMStore(suiteName: testSuite)
        store.set(Data("ours".utf8), forKey: IAMStoreKey.variables)
        store.removeAll()

        XCTAssertNil(store.data(forKey: IAMStoreKey.variables))
        XCTAssertEqual(defaults?.data(forKey: "host_owned_key"), Data("host".utf8),
                       "removeAll deleted a key the module does not own")
    }

    func testEveryStoreKeyCarriesTheModulePrefix() {
        for key in [IAMStoreKey.displayHistory, IAMStoreKey.campaignCache,
                    IAMStoreKey.analyticsOutbox, IAMStoreKey.variables] {
            XCTAssertTrue(key.hasPrefix(IAMStoreKey.prefix),
                          "\(key) would survive removeAll")
        }
    }

    // MARK: - Customer scoping

    func testCustomerScopedDecodesForTheMatchingCustomer() {
        let encoded = CustomerScoped.encoded(["points": "1250"], customerId: "cust-1")
        XCTAssertEqual(CustomerScoped<[String: String]>.decode(encoded, customerId: "cust-1"),
                       ["points": "1250"])
    }

    /// One slot stamped with its owner, rather than one key per customer — which would
    /// retain every previous customer's data indefinitely, PII included.
    func testCustomerScopedReturnsNilForADifferentCustomer() {
        let encoded = CustomerScoped.encoded(["points": "1250"], customerId: "cust-1")
        XCTAssertNil(CustomerScoped<[String: String]>.decode(encoded, customerId: "cust-2"))
    }

    func testCustomerScopedReturnsNilForCorruptOrAbsentData() {
        XCTAssertNil(CustomerScoped<[String: String]>.decode(nil, customerId: "cust-1"))
        XCTAssertNil(CustomerScoped<[String: String]>.decode(Data("garbage".utf8),
                                                            customerId: "cust-1"))
    }

    func testCustomerScopedRoundTripsThroughAStore() {
        let store = InMemoryIAMStore()
        store.set(CustomerScoped.encoded([1, 2, 3], customerId: "cust-1"),
                  forKey: IAMStoreKey.displayHistory)

        let loaded = CustomerScoped<[Int]>.decode(store.data(forKey: IAMStoreKey.displayHistory),
                                                 customerId: "cust-1")
        XCTAssertEqual(loaded, [1, 2, 3])
    }
}
