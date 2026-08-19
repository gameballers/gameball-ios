//
//  IAMHTTPClientTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class IAMHTTPClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        IAMHTTPStub.reset()
    }

    override func tearDown() {
        IAMHTTPStub.reset()
        super.tearDown()
    }

    private func makeClient(apiKey: String = "test-api-key",
                            language: String = "en") -> IAMHTTPClient {
        return IAMHTTPClient(session: IAMHTTPStub.session(),
                             baseURL: { "https://api.gameball.co" },
                             apiKey: { apiKey },
                             language: { language })
    }

    private func post(_ client: IAMHTTPClient,
                      path: String = IAMEndpoint.sync,
                      body: [String: Any] = ["customerId": "cust-1"]) -> IAMHTTPOutcome? {
        var outcome: IAMHTTPOutcome?
        let done = expectation(description: "post completed")
        client.post(path: path, body: body) {
            outcome = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return outcome
    }

    // MARK: - URL pinning

    /// v4.1 answers 401 to APIKey auth, and `NetworkManager`'s URL extension switches to it
    /// whenever a session token is present. This client must never route through that.
    func testSyncPathIsPinnedToV40() {
        IAMHTTPStub.replies = [.status(200)]
        _ = post(makeClient())
        XCTAssertEqual(IAMHTTPStub.lastRequest?.url?.absoluteString,
                       "https://api.gameball.co/api/v4.0/integrations/inapp-messages/sync")
    }

    func testEveryEndpointIsPinnedToV40() {
        for path in [IAMEndpoint.sync, IAMEndpoint.events, IAMEndpoint.variables] {
            XCTAssertTrue(path.hasPrefix("/api/v4.0/integrations/inapp-messages/"),
                          "\(path) is not pinned to v4.0")
        }
    }

    /// `NetworkManager`'s `URLRequest` extension rewrites `/events` and `/customers` to
    /// v4.1 whenever a session token is passed, and v4.1 answers 401 to APIKey auth. This
    /// client builds its own request and must carry no version logic at all — proven by
    /// handing it the very path that would trigger the rewrite and seeing it pass through.
    func testClientNeverRewritesThePath() {
        IAMHTTPStub.replies = [.status(200)]
        _ = post(makeClient(), path: "/events")
        XCTAssertEqual(IAMHTTPStub.lastRequest?.url?.absoluteString,
                       "https://api.gameball.co/events")
    }

    func testMethodIsPost() {
        IAMHTTPStub.replies = [.status(200)]
        _ = post(makeClient())
        XCTAssertEqual(IAMHTTPStub.lastRequest?.httpMethod, "POST")
    }

    // MARK: - Headers

    func testRequestCarriesAPIKeyAndAgentHeaders() {
        IAMHTTPStub.replies = [.status(200)]
        _ = post(makeClient(apiKey: "key-123", language: "ar"))

        let headers = IAMHTTPStub.lastRequest?.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["APIKey"], "key-123")
        XCTAssertEqual(headers["x-gb-agent"], SDKInfo.userAgent)
        XCTAssertEqual(headers["lang"], "ar")
        XCTAssertEqual(headers["Content-Type"], "application/json")
    }

    /// Read at request time through closures, so a key registered after the client was
    /// built is still used.
    func testCredentialsAreReadAtRequestTime() {
        var key = "first"
        let client = IAMHTTPClient(session: IAMHTTPStub.session(),
                                   baseURL: { "https://api.gameball.co" },
                                   apiKey: { key },
                                   language: { "en" })
        IAMHTTPStub.replies = [.status(200)]
        _ = post(client)
        XCTAssertEqual(IAMHTTPStub.lastRequest?.allHTTPHeaderFields?["APIKey"], "first")

        key = "second"
        _ = post(client)
        XCTAssertEqual(IAMHTTPStub.lastRequest?.allHTTPHeaderFields?["APIKey"], "second")
    }

    // MARK: - Body

    func testBodyCarriesCustomerIdAndPlatformOne() {
        IAMHTTPStub.replies = [.status(200)]
        _ = post(makeClient(), body: ["customerId": "cust-7"])

        let json = IAMHTTPStub.lastBodyJSON()
        XCTAssertEqual(json?["customerId"] as? String, "cust-7")
        XCTAssertEqual(json?["platform"] as? Int, 1)
    }

    func testCallerSuppliedFieldsSurvive() {
        IAMHTTPStub.replies = [.status(200)]
        _ = post(makeClient(), body: ["customerId": "cust-7", "locale": "en", "appVersion": "1.2.3"])

        let json = IAMHTTPStub.lastBodyJSON()
        XCTAssertEqual(json?["locale"] as? String, "en")
        XCTAssertEqual(json?["appVersion"] as? String, "1.2.3")
    }

    /// A platform code other than iOS or Android is a wiring mistake that would silently
    /// mis-attribute every event, so it is logged before the request goes out.
    func testUnexpectedPlatformIsLoggedLoudly() {
        IAMHTTPStub.replies = [.status(200)]
        let logs = capturingIAMLog {
            _ = post(makeClient(), body: ["customerId": "cust-1", "platform": 9])
        }
        XCTAssertTrue(logs.contains { $0.contains("platform") },
                      "an unexpected platform code was not logged: \(logs)")
    }

    func testNonSerialisableBodyDoesNotCrash() {
        // A Date is not JSON-serialisable through JSONSerialization.
        let outcome = post(makeClient(), body: ["customerId": "cust-1", "bad": Date()])
        guard case .some(.permanentFailure) = outcome else {
            return XCTFail("expected a permanent failure, got \(String(describing: outcome))")
        }
        XCTAssertTrue(IAMHTTPStub.requests.isEmpty, "nothing should have been sent")
    }

    // MARK: - Status mapping

    func test2xxIsSuccess() {
        for status in [200, 201, 204] {
            IAMHTTPStub.reset()
            IAMHTTPStub.replies = [.status(status, body: Data("{\"ok\":true}".utf8))]
            guard case .some(.success(let data)) = post(makeClient()) else {
                XCTFail("status \(status) should be a success")
                continue
            }
            XCTAssertEqual(data, Data("{\"ok\":true}".utf8))
        }
    }

    func testPermanentStatusesAreNeverRetried() {
        for status in [400, 401, 403, 404, 422] {
            IAMHTTPStub.reset()
            IAMHTTPStub.replies = [.status(status)]
            guard case .some(.permanentFailure(let reported)) = post(makeClient()) else {
                XCTFail("status \(status) should be permanent")
                continue
            }
            XCTAssertEqual(reported, status)
        }
    }

    func testRetryableStatusesAreRetryable() {
        for status in [408, 429, 500, 502, 503, 504] {
            IAMHTTPStub.reset()
            IAMHTTPStub.replies = [.status(status)]
            guard case .some(.retryableFailure(let reported)) = post(makeClient()) else {
                XCTFail("status \(status) should be retryable")
                continue
            }
            XCTAssertEqual(reported, status)
        }
    }

    func testTransportErrorIsRetryable() {
        IAMHTTPStub.replies = [.transportError()]
        guard case .some(.retryableFailure(let status)) = post(makeClient()) else {
            return XCTFail("a transport error should be retryable")
        }
        XCTAssertNil(status)
    }

    /// A 404 with no body means the endpoint is not deployed for this tenant, which is a
    /// different conversation from a 404 that came back with an error document.
    func test404WithEmptyBodyIsLoggedAsNotDeployed() {
        IAMHTTPStub.replies = [.status(404, body: Data())]
        let logs = capturingIAMLog { _ = post(makeClient()) }
        XCTAssertTrue(logs.contains { $0.lowercased().contains("deployed") },
                      "a bodyless 404 was not called out: \(logs)")

        IAMHTTPStub.reset()
        IAMHTTPStub.replies = [.status(404, body: Data("{\"message\":\"no such customer\"}".utf8))]
        let withBody = capturingIAMLog { _ = post(makeClient()) }
        XCTAssertFalse(withBody.contains { $0.lowercased().contains("deployed") },
                       "a 404 with a body should not be reported as undeployed: \(withBody)")
    }

    func testMalformedBaseURLFailsWithoutCrashing() {
        let client = IAMHTTPClient(session: IAMHTTPStub.session(),
                                   baseURL: { "not a url at all" },
                                   apiKey: { "key" },
                                   language: { "en" })
        guard case .some(.permanentFailure) = post(client) else {
            return XCTFail("an unusable base URL should fail permanently")
        }
    }
}
