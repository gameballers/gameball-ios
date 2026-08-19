//
//  MessageActionRouterTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class MessageActionRouterTests: XCTestCase {

    private var openedURLs: [(URL, Bool)] = []
    private var navigations: [(String, [String: Any]?)] = []
    private var dismissals = 0

    private func makeRouter() -> MessageActionRouter {
        return MessageActionRouter(openURL: { self.openedURLs.append(($0, $1)) },
                                   navigate: { self.navigations.append(($0, $1)) },
                                   dismiss: { self.dismissals += 1 })
    }

    override func setUp() {
        super.setUp()
        openedURLs = []
        navigations = []
        dismissals = 0
    }

    func testDismissDismisses() {
        XCTAssertNil(makeRouter().perform(.dismiss))
        XCTAssertEqual(dismissals, 1)
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertTrue(navigations.isEmpty)
    }

    func testOpenURLInAppReturnsTheURLForReporting() {
        let url = URL(string: "https://example.com/offer")!
        let reported = makeRouter().perform(.openURL(url: url, external: false))

        XCTAssertEqual(reported, "https://example.com/offer")
        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(openedURLs.first?.0, url)
        XCTAssertEqual(openedURLs.first?.1, false)
    }

    func testOpenURLExternallyMarksItExternal() {
        let url = URL(string: "https://example.com")!
        _ = makeRouter().perform(.openURL(url: url, external: true))
        XCTAssertEqual(openedURLs.first?.1, true)
    }

    /// Route and arguments are forwarded untouched — the host's router is the only thing that
    /// knows what they mean.
    func testNavigateForwardsRouteAndArgumentsUntouched() {
        let reported = makeRouter().perform(.navigate(route: "orders",
                                                      arguments: ["id": 7, "ref": "email"]))
        XCTAssertNil(reported, "a navigation has no URL to attribute")
        XCTAssertEqual(navigations.count, 1)
        XCTAssertEqual(navigations.first?.0, "orders")
        XCTAssertEqual(navigations.first?.1?["id"] as? Int, 7)
        XCTAssertEqual(navigations.first?.1?["ref"] as? String, "email")
    }

    /// The host may want the message to stay up while it pushes; dismissing here would take
    /// that choice away.
    func testNavigateDoesNotDismiss() {
        _ = makeRouter().perform(.navigate(route: "orders", arguments: nil))
        XCTAssertEqual(dismissals, 0)
    }

    func testNavigateWithNoArgumentsPassesNil() {
        _ = makeRouter().perform(.navigate(route: "home", arguments: nil))
        // `?? nil` flattens the double optional; `?? [:]` would substitute a non-nil value
        // and assert nothing.
        XCTAssertNil(navigations.first?.1 ?? nil)
    }

    func testUnsupportedActionLogsAndDoesNothing() {
        let logs = capturingIAMLog {
            XCTAssertNil(self.makeRouter().perform(.unsupported(type: "log_event")))
        }
        XCTAssertEqual(dismissals, 0)
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertTrue(navigations.isEmpty)
        XCTAssertTrue(logs.contains { $0.contains("log_event") },
                      "an unsupported action was ignored silently: \(logs)")
    }
}
