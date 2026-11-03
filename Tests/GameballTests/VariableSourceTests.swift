//
//  VariableSourceTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class VariableSourceTests: XCTestCase {

    private var transport: OutboxTransport!
    private var store: InMemoryIAMStore!
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    private let body = Data("{\"variables\":{\"points\":\"1,250\",\"player_email\":\"a@b.co\"}}".utf8)

    override func setUp() {
        super.setUp()
        transport = OutboxTransport()
        store = InMemoryIAMStore()
        clock = Date(timeIntervalSince1970: 1_700_000_000)
    }

    private func makeSource(customerId: String = "cust-1",
                            timeout: TimeInterval = 2,
                            cacheTTL: TimeInterval = 60) -> VariableSource {
        return VariableSource(transport: transport,
                              store: store,
                              customerId: customerId,
                              timeout: timeout,
                              cacheTTL: cacheTTL,
                              now: { self.clock })
    }

    private func values(_ source: VariableSource,
                        tokens: Set<String> = ["points"],
                        timeout: TimeInterval = 5) -> [String: String]? {
        var captured: [String: String]?
        let done = expectation(description: "values returned")
        source.values(neededTokens: tokens) {
            captured = $0
            done.fulfill()
        }
        wait(for: [done], timeout: timeout)
        return captured
    }

    // MARK: - Success

    func testSuccessfulFetchReturnsValues() {
        transport.script([.success(body)])
        XCTAssertEqual(values(makeSource())?["points"], "1,250")
        XCTAssertEqual(transport.allPaths, [IAMEndpoint.variables])
    }

    func testRequestCarriesTheCustomerId() {
        transport.script([.success(body)])
        _ = values(makeSource(customerId: "cust-9"))
        XCTAssertEqual(transport.lastBody?["customerId"] as? String, "cust-9")
    }

    /// No tokens means no reason to ask. This is what keeps personalisation entirely inert for
    /// campaigns that do not use it — and the variables endpoint is not deployed yet.
    func testNoNeededTokensSkipsTheRequestEntirely() {
        transport.script([.success(body)])
        XCTAssertEqual(values(makeSource(), tokens: [])?.isEmpty, true)
        XCTAssertEqual(transport.postCount, 0)
    }

    // MARK: - Failure

    func testFailureReturnsEmptyNotAnError() {
        for outcome in [IAMHTTPOutcome.permanentFailure(status: 404),
                        .permanentFailure(status: 422),
                        .retryableFailure(status: 503),
                        .retryableFailure(status: nil)] {
            transport = OutboxTransport()
            store = InMemoryIAMStore()
            transport.script([outcome])
            XCTAssertEqual(values(makeSource())?.isEmpty, true, "outcome \(outcome)")
        }
    }

    func testUnreadableBodyReturnsEmpty() {
        transport.script([.success(Data("not json".utf8))])
        XCTAssertEqual(values(makeSource())?.isEmpty, true)
    }

    /// A display must never wait on personalisation, so the bound is independent of the
    /// transport. Whatever is already held is served.
    func testTimeoutReturnsWhatIsHeld() {
        // Seed a persisted value, then hold the request open forever.
        let seeded = makeSource()
        seeded.setPersistableTokens(["points"])
        transport.script([.success(body)])
        _ = values(seeded)
        XCTAssertNotNil(store.data(forKey: IAMStoreKey.variables))

        transport = OutboxTransport()   // no scripted outcome: the request hangs
        let source = makeSource(timeout: 0.3)
        XCTAssertEqual(values(source, timeout: 5)?["points"], "1,250",
                       "the timeout should fall back to persisted values")
    }

    // MARK: - Caching

    func testValuesAreCachedForTheTTL() {
        transport.script([.success(body), .success(body)])
        let source = makeSource(cacheTTL: 60)

        _ = values(source)
        clock = clock.addingTimeInterval(30)
        _ = values(source)
        XCTAssertEqual(transport.postCount, 1, "a second call inside the TTL refetched")

        clock = clock.addingTimeInterval(31)
        _ = values(source)
        XCTAssertEqual(transport.postCount, 2, "the TTL should have expired")
    }

    /// Called on every event, never on session start: a balance can change between two events
    /// in a session, but nothing changed before the session began.
    func testForgetCachedValuesForcesARefetch() {
        transport.script([.success(body), .success(body)])
        let source = makeSource()

        _ = values(source)
        XCTAssertEqual(transport.postCount, 1)

        source.forgetCachedValues()
        _ = values(source)
        XCTAssertEqual(transport.postCount, 2)
    }

    // MARK: - PII filtering

    /// The response can carry anything the backend chose to send. Persisting a value no campaign
    /// references would be storing PII for no reason.
    func testOnlyNeededTokensArePersisted() {
        transport.script([.success(body)])
        let source = makeSource()
        source.setPersistableTokens(["points"])
        _ = values(source)

        let persisted = CustomerScoped<[String: String]>
            .decode(store.data(forKey: IAMStoreKey.variables), customerId: "cust-1")
        XCTAssertEqual(persisted?["points"], "1,250")
        XCTAssertNil(persisted?["player_email"], "an email address was written to disk")
    }

    func testNoNeededTokensPersistsNothing() {
        transport.script([.success(body)])
        let source = makeSource()
        source.setPersistableTokens([])
        _ = values(source)
        XCTAssertNil(store.data(forKey: IAMStoreKey.variables))
    }

    func testPersistedValuesSurviveReload() {
        transport.script([.success(body)])
        let source = makeSource()
        source.setPersistableTokens(["points"])
        _ = values(source)

        // A fresh instance over the same store, with the request hanging.
        transport = OutboxTransport()
        let reloaded = makeSource(timeout: 0.3)
        XCTAssertEqual(values(reloaded, timeout: 5)?["points"], "1,250")
    }

    func testPersistedValuesForADifferentCustomerAreNotAdopted() {
        transport.script([.success(body)])
        let source = makeSource(customerId: "cust-1")
        source.setPersistableTokens(["points"])
        _ = values(source)

        transport = OutboxTransport()
        let other = makeSource(customerId: "cust-2", timeout: 0.3)
        XCTAssertEqual(values(other, timeout: 5)?.isEmpty, true)
    }

    // MARK: - Clearing

    func testClearRemovesStoredValues() {
        transport.script([.success(body)])
        let source = makeSource()
        source.setPersistableTokens(["points"])
        _ = values(source)
        XCTAssertNotNil(store.data(forKey: IAMStoreKey.variables))

        source.clear()
        // `clear` is queued; a subsequent queued read observes it.
        let drained = expectation(description: "clear applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertNil(store.data(forKey: IAMStoreKey.variables))
    }

    /// The race this encodes was real: a customer check performed *before* the request is sent
    /// always passes, because the clear has not been issued yet. The check has to happen after
    /// the response arrives.
    func testPendingWriteCannotResurrectClearedValues() {
        let source = makeSource()
        source.setPersistableTokens(["points"])

        // Request in flight and held open.
        var returned: [String: String]?
        let done = expectation(description: "values returned")
        source.values(neededTokens: ["points"]) {
            returned = $0
            done.fulfill()
        }

        // Wait for the transport to have been called, then clear before answering.
        let sent = expectation(description: "request sent")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.transport.postCount == 1 { sent.fulfill() }
        }
        wait(for: [sent], timeout: 2)

        source.clear()
        let cleared = expectation(description: "clear applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { cleared.fulfill() }
        wait(for: [cleared], timeout: 2)

        transport.release(.success(body))
        wait(for: [done], timeout: 5)

        XCTAssertEqual(returned?.isEmpty, true, "a cleared fetch still returned values")
        XCTAssertNil(store.data(forKey: IAMStoreKey.variables),
                     "a pending write resurrected cleared values")
    }
}
