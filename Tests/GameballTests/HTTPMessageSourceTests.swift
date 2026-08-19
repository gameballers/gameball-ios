//
//  HTTPMessageSourceTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// Records what it was asked to send and replies with whatever the test queued.
final class RecordingTransport: IAMTransport {
    var outcomes: [IAMHTTPOutcome] = []
    private(set) var paths: [String] = []
    private(set) var bodies: [[String: Any]] = []

    var postCount: Int { return paths.count }
    var lastBody: [String: Any]? { return bodies.last }

    init(outcomes: [IAMHTTPOutcome] = []) {
        self.outcomes = outcomes
    }

    func post(path: String,
              body: [String: Any],
              completion: @escaping (IAMHTTPOutcome) -> Void) {
        paths.append(path)
        bodies.append(body)
        let outcome: IAMHTTPOutcome
        if outcomes.count > 1 {
            outcome = outcomes.removeFirst()
        } else {
            outcome = outcomes.first ?? .success(Data("{}".utf8))
        }
        completion(outcome)
    }
}

final class HTTPMessageSourceTests: XCTestCase {

    private func makeSource(_ transport: IAMTransport) -> HTTPMessageSource {
        return HTTPMessageSource(transport: transport,
                                 appVersion: "1.2.3",
                                 sdkVersion: "3.3.0",
                                 locale: "en")
    }

    private func fetch(_ source: HTTPMessageSource,
                       customerId: String = "cust-1") -> Result<SyncResult, Error>? {
        var captured: Result<SyncResult, Error>?
        let done = expectation(description: "fetch completed")
        source.fetch(customerId: customerId) {
            captured = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return captured
    }

    // MARK: - Request shape

    func testFetchPostsToTheSyncEndpoint() {
        let transport = RecordingTransport(outcomes: [.success(Data("{}".utf8))])
        _ = fetch(makeSource(transport))
        XCTAssertEqual(transport.paths, [IAMEndpoint.sync])
    }

    func testBodyCarriesCustomerIdLocaleAppVersionAndSdkVersion() {
        let transport = RecordingTransport(outcomes: [.success(Data("{}".utf8))])
        _ = fetch(makeSource(transport), customerId: "cust-9")

        let body = transport.lastBody
        XCTAssertEqual(body?["customerId"] as? String, "cust-9")
        XCTAssertEqual(body?["locale"] as? String, "en")
        XCTAssertEqual(body?["appVersion"] as? String, "1.2.3")
        XCTAssertEqual(body?["sdkVersion"] as? String, "3.3.0")
    }

    // MARK: - Success

    func testSuccessParsesThePayload() {
        let transport = RecordingTransport(outcomes: [.success(IAMFixture.data("v4-sync-response"))])
        guard case .some(.success(let result)) = fetch(makeSource(transport)) else {
            return XCTFail("expected a parsed result")
        }
        XCTAssertEqual(result.campaigns.count, 8)
        XCTAssertEqual(result.cooldown, 30)
    }

    /// The bytes are retained so the cache stores a payload rather than objects.
    func testSuccessRetainsTheRawPayload() {
        let payload = IAMFixture.data("v4-sync-response")
        let transport = RecordingTransport(outcomes: [.success(payload)])
        guard case .some(.success(let result)) = fetch(makeSource(transport)) else {
            return XCTFail("expected a parsed result")
        }
        XCTAssertEqual(result.rawPayload, payload)
    }

    /// An empty but successful sync is a real answer — the customer has no live campaigns —
    /// and must not look like a failure, or the caller would resurrect stale cached ones.
    func testEmptySuccessIsASuccessNotAFailure() {
        let transport = RecordingTransport(outcomes: [.success(Data("{\"messages\":[]}".utf8))])
        guard case .some(.success(let result)) = fetch(makeSource(transport)) else {
            return XCTFail("an empty sync must succeed")
        }
        XCTAssertTrue(result.campaigns.isEmpty)
        XCTAssertNotNil(result.rawPayload)
    }

    // MARK: - Failure

    /// Both failure kinds surface as `.failure`, so the caller falls back to cache without
    /// having to know the difference. Retry policy is the outbox's concern, not sync's.
    func testPermanentFailureSurfacesAsFailure() {
        let transport = RecordingTransport(outcomes: [.permanentFailure(status: 401)])
        guard case .some(.failure) = fetch(makeSource(transport)) else {
            return XCTFail("expected a failure")
        }
    }

    func testRetryableFailureSurfacesAsFailure() {
        let transport = RecordingTransport(outcomes: [.retryableFailure(status: 503)])
        guard case .some(.failure) = fetch(makeSource(transport)) else {
            return XCTFail("expected a failure")
        }
    }

    func testTransportErrorSurfacesAsFailure() {
        let transport = RecordingTransport(outcomes: [.retryableFailure(status: nil)])
        guard case .some(.failure) = fetch(makeSource(transport)) else {
            return XCTFail("expected a failure")
        }
    }

    /// Malformed bytes are a parse problem, not a transport one, and must not be mistaken
    /// for a successful empty sync — that would clobber a good cache.
    func testUnparseableSuccessBodySurfacesAsFailure() {
        let transport = RecordingTransport(outcomes: [.success(Data("{ not json".utf8))])
        guard case .some(.failure) = fetch(makeSource(transport)) else {
            return XCTFail("unparseable bytes must not be reported as an empty success")
        }
    }

    // MARK: - Stub source

    func testStubMessageSourceCountsFetches() {
        let stub = StubMessageSource(result: .success(.empty))
        XCTAssertEqual(stub.fetchCount, 0)

        stub.fetch(customerId: "cust-1") { _ in }
        stub.fetch(customerId: "cust-1") { _ in }
        XCTAssertEqual(stub.fetchCount, 2)
    }

    func testStubMessageSourceReplaysItsResult() {
        let campaign = makeCampaign(campaignId: 77)
        let result = SyncResult(campaigns: [campaign], cooldown: 15, rawPayload: nil)
        let stub = StubMessageSource(result: .success(result))

        var captured: [InAppMessageCampaign] = []
        stub.fetch(customerId: "cust-1") {
            if case .success(let value) = $0 { captured = value.campaigns }
        }
        XCTAssertEqual(captured.map { $0.campaignId }, [77])
    }
}
