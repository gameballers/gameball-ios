//
//  InAppWidgetURLTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// The URL a game opens on, read the way the widget reads it.
final class InAppWidgetURLTests: XCTestCase {

    private func url(customerId: String? = "cust-1",
                     apiKey: String = "api-key",
                     sessionToken: String? = nil) -> URL? {
        return GameballApp.inAppWidgetURL(base: "https://m.gameball.app",
                                          customerId: customerId,
                                          language: "en",
                                          apiKey: apiKey,
                                          sessionToken: sessionToken,
                                          openDetail: "details_wheel_9645")
    }

    /// A value as the widget reads it: form decoding, where a raw `+` is a space.
    private func widgetReads(_ name: String, in url: URL?) -> String? {
        guard let url = url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .percentEncodedQueryItems,
              let raw = items.first(where: { $0.name == name })?.value else { return nil }
        return raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    /// `queryItems` leaves a `+` raw, which the widget reads as a space — so a customer id such as
    /// `ahmed+test@example.com` reached it as a customer who does not exist.
    func testAPlusInTheCustomerIdReachesTheWidget() {
        XCTAssertEqual(widgetReads("customerId", in: url(customerId: "ahmed+test@example.com")),
                       "ahmed+test@example.com")
    }

    /// Every value is encoded exactly once, whatever it holds.
    func testEveryValueArrivesAsItWasGiven() {
        XCTAssertEqual(widgetReads("customerId", in: url(customerId: "أحمد 1")), "أحمد 1")
        XCTAssertEqual(widgetReads("sessionToken", in: url(sessionToken: "a+b/c=")), "a+b/c=")
        XCTAssertEqual(widgetReads("apiKey", in: url(apiKey: "k&y=1")), "k&y=1")
    }

    func testTheGameOpensWithoutTheWidgetsNavigation() {
        let composed = url()
        XCTAssertEqual(composed?.host, "m.gameball.app")
        XCTAssertEqual(widgetReads("openDetail", in: composed), "details_wheel_9645")
        XCTAssertEqual(widgetReads("hideNavigation", in: composed), "true")
        XCTAssertEqual(widgetReads("os", in: composed), "iOS")
        XCTAssertEqual(widgetReads("lang", in: composed), "en")
    }

    func testASessionTokenIsSentOnlyWhenThereIsOne() {
        XCTAssertNil(widgetReads("sessionToken", in: url(sessionToken: nil)))
        XCTAssertNil(widgetReads("sessionToken", in: url(sessionToken: "")))
        XCTAssertEqual(widgetReads("sessionToken", in: url(sessionToken: "tok")), "tok")
    }
}
