//
//  BatchedMessageAnalyticsTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// A transport that can hold a request open, so "one in flight at a time" is observable.
final class OutboxTransport: IAMTransport {
    private let lock = NSLock()
    private var paths: [String] = []
    private var bodies: [[String: Any]] = []
    private var held: [(IAMHTTPOutcome) -> Void] = []
    private var scripted: [IAMHTTPOutcome] = []
    private var sawOffMainThread = false

    /// Queued outcomes, consumed in order. When empty the request is *held* open.
    func script(_ outcomes: [IAMHTTPOutcome]) {
        lock.lock(); scripted = outcomes; lock.unlock()
    }

    var postCount: Int {
        lock.lock(); defer { lock.unlock() }
        return paths.count
    }

    var inFlight: Int {
        lock.lock(); defer { lock.unlock() }
        return held.count
    }

    var allPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return paths
    }

    var wasCalledOffTheMainThread: Bool {
        lock.lock(); defer { lock.unlock() }
        return sawOffMainThread
    }

    /// Every event uid the transport has been handed, in request order.
    var sentUids: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return bodies.map { body in
            let events = body["events"] as? [[String: Any]] ?? []
            return events.compactMap { $0["eventUid"] as? String }
        }
    }

    var sentBatchSizes: [Int] {
        lock.lock(); defer { lock.unlock() }
        return bodies.map { ($0["events"] as? [[String: Any]] ?? []).count }
    }

    var lastBody: [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return bodies.last
    }

    /// Answers the oldest held request.
    func release(_ outcome: IAMHTTPOutcome) {
        lock.lock()
        let completion = held.isEmpty ? nil : held.removeFirst()
        lock.unlock()
        completion?(outcome)
    }

    func post(path: String,
              body: [String: Any],
              completion: @escaping (IAMHTTPOutcome) -> Void) {
        lock.lock()
        paths.append(path)
        bodies.append(body)
        if !Thread.isMainThread { sawOffMainThread = true }
        let outcome: IAMHTTPOutcome? = scripted.isEmpty ? nil : scripted.removeFirst()
        if outcome == nil { held.append(completion) }
        lock.unlock()

        if let outcome = outcome { completion(outcome) }
    }
}

final class BatchedMessageAnalyticsTests: XCTestCase {

    private let occurred = Date(timeIntervalSince1970: 1_755_597_600)
    private var transport: OutboxTransport!
    private var store: InMemoryIAMStore!

    override func setUp() {
        super.setUp()
        transport = OutboxTransport()
        store = InMemoryIAMStore()
    }

    private func makeOutbox(flushInterval: TimeInterval = 3600,
                            flushThreshold: Int = 10,
                            batchSize: Int = 50,
                            ceiling: Int = 500) -> BatchedMessageAnalytics {
        return BatchedMessageAnalytics(transport: transport,
                                       store: store,
                                       customerId: "cust-1",
                                       flushInterval: flushInterval,
                                       flushThreshold: flushThreshold,
                                       batchSize: batchSize,
                                       ceiling: ceiling)
    }

    private func event(_ index: Int = 0,
                       type: MessageEventType = .impression) -> MessageEvent {
        return MessageEvent(campaignId: 1000 + index,
                            variationId: nil,
                            dispatchId: nil,
                            type: type,
                            occurredAt: occurred)
    }

    /// `log` and `flush` are asynchronous by contract, so every assertion about what the
    /// transport saw has to drain the outbox's queue first. Reading `pendingCount` does
    /// that — it is a synchronous hop onto the same serial queue.
    private func drain(_ outbox: BatchedMessageAnalytics) {
        _ = outbox.pendingCount
    }

    private func log(_ outbox: BatchedMessageAnalytics, count: Int) {
        for index in 0..<count { outbox.log(event(index)) }
        drain(outbox)
    }

    /// Waits out a window in which nothing should happen.
    private func expectQuiet(for seconds: TimeInterval) {
        let quiet = expectation(description: "no activity")
        quiet.isInverted = true
        wait(for: [quiet], timeout: seconds)
    }

    // MARK: - Non-blocking

    /// The caller is a view's `didPresent`; it must never wait on a network request.
    func testLogDoesNotBlockTheCaller() {
        transport.script([.success(Data("{}".utf8))])
        let outbox = makeOutbox(flushThreshold: 1)
        XCTAssertTrue(Thread.isMainThread, "precondition: the test logs from main")

        outbox.log(event())
        XCTAssertEqual(outbox.pendingCount, 0, "the batch should have been sent and cleared")
        XCTAssertTrue(transport.wasCalledOffTheMainThread,
                      "the request ran on the calling thread")
    }

    // MARK: - Flush triggers

    func testFlushesAtTenEvents() {
        transport.script([.success(Data("{}".utf8))])
        let outbox = makeOutbox(flushThreshold: 10)

        log(outbox, count: 9)
        XCTAssertEqual(transport.postCount, 0, "nine events must not trigger a flush")

        outbox.log(event(9))
        drain(outbox)
        XCTAssertEqual(transport.postCount, 1)
        XCTAssertEqual(outbox.pendingCount, 0)
    }

    func testFlushChunksAtFifty() {
        transport.script([.success(Data("{}".utf8)),
                          .success(Data("{}".utf8)),
                          .success(Data("{}".utf8))])
        // Threshold high enough that only the explicit flush sends.
        let outbox = makeOutbox(flushThreshold: 1000, batchSize: 50)

        log(outbox, count: 120)
        XCTAssertEqual(transport.postCount, 0)

        outbox.flush()
        drain(outbox)
        XCTAssertEqual(transport.sentBatchSizes, [50, 50, 20])
        XCTAssertEqual(outbox.pendingCount, 0)
    }

    func testTimerFlushesOnItsInterval() {
        transport.script([.success(Data("{}".utf8))])
        let outbox = makeOutbox(flushInterval: 0.2, flushThreshold: 1000)
        outbox.load()
        outbox.log(event())

        let sent = expectation(description: "timer flushed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if self.transport.postCount == 1 { sent.fulfill() }
        }
        wait(for: [sent], timeout: 2)
        outbox.dispose()
    }

    func testDisposeCancelsTheTimer() {
        transport.script([.success(Data("{}".utf8))])
        let outbox = makeOutbox(flushInterval: 0.2, flushThreshold: 1000)
        outbox.load()
        outbox.log(event())
        outbox.dispose()

        expectQuiet(for: 0.7)
        XCTAssertEqual(transport.postCount, 0, "a disposed outbox kept firing")
    }

    // MARK: - Request shape

    func testRequestGoesToTheEventsEndpointWithCustomerId() {
        transport.script([.success(Data("{}".utf8))])
        let outbox = makeOutbox(flushThreshold: 1)
        outbox.log(event())
        drain(outbox)

        XCTAssertEqual(transport.allPaths, [IAMEndpoint.events])
        XCTAssertEqual(transport.lastBody?["customerId"] as? String, "cust-1")
        XCTAssertNotNil(transport.lastBody?["events"] as? [[String: Any]])
    }

    // MARK: - Success handling

    func test2xxClearsTheBatch() {
        transport.script([.success(Data("{\"accepted\":1,\"rejected\":0}".utf8))])
        let outbox = makeOutbox(flushThreshold: 1)
        outbox.log(event())
        XCTAssertEqual(outbox.pendingCount, 0)
    }

    /// A mixed batch returns 202 with a rejected count. One bad event does not poison the
    /// good ones, so clearing is correct — but the rejection is reported, because those
    /// events can never succeed.
    func test2xxWithRejectedGreaterThanZeroStillClears() {
        transport.script([.success(Data("{\"accepted\":4,\"rejected\":2}".utf8))])
        let outbox = makeOutbox(flushThreshold: 5)

        // The barrier belongs inside the capture: the log line is emitted on the outbox's
        // queue, so without draining here the sink is torn down before it arrives.
        let logs = capturingIAMLog { log(outbox, count: 5) }
        XCTAssertEqual(outbox.pendingCount, 0)
        XCTAssertTrue(logs.contains { $0.contains("rejected") },
                      "a non-zero rejected count was not reported: \(logs)")
    }

    func testUnreadable2xxBodyStillAccepted() {
        transport.script([.success(Data("not json".utf8))])
        let outbox = makeOutbox(flushThreshold: 1)
        outbox.log(event())
        XCTAssertEqual(outbox.pendingCount, 0, "a 2xx is an accept regardless of its body")
    }

    // MARK: - Failure handling

    func testPermanentStatusDiscardsWithoutRetry() {
        for status in [400, 401, 404, 422] {
            transport = OutboxTransport()
            store = InMemoryIAMStore()
            transport.script([.permanentFailure(status: status)])
            let outbox = makeOutbox(flushThreshold: 1)

            let logs = capturingIAMLog {
                outbox.log(event())
                drain(outbox)
            }
            XCTAssertEqual(outbox.pendingCount, 0, "status \(status) should discard")
            XCTAssertEqual(transport.postCount, 1, "status \(status) must not be retried")
            XCTAssertTrue(logs.contains { $0.contains("DISCARDING") },
                          "status \(status) was discarded quietly: \(logs)")
        }
    }

    func testRetryableStatusKeepsTheBatch() {
        for status in [408, 429, 500, 503] {
            transport = OutboxTransport()
            store = InMemoryIAMStore()
            transport.script([.retryableFailure(status: status)])
            let outbox = makeOutbox(flushThreshold: 1)

            outbox.log(event())
            XCTAssertEqual(outbox.pendingCount, 1, "status \(status) should be retried")
        }
    }

    func testTransportErrorKeepsTheBatch() {
        transport.script([.retryableFailure(status: nil)])
        let outbox = makeOutbox(flushThreshold: 1)
        outbox.log(event())
        XCTAssertEqual(outbox.pendingCount, 1)
    }

    /// Regenerating the uid on retry would make a retried impression count twice.
    func testEventUidIsNotRegeneratedOnRetry() {
        transport.script([.retryableFailure(status: 503), .success(Data("{}".utf8))])
        let outbox = makeOutbox(flushThreshold: 1)

        outbox.log(event())
        XCTAssertEqual(outbox.pendingCount, 1)

        outbox.flush()
        drain(outbox)
        XCTAssertEqual(outbox.pendingCount, 0)

        let uids = transport.sentUids
        XCTAssertEqual(uids.count, 2)
        XCTAssertEqual(uids[0], uids[1], "the uid changed between attempts")
    }

    // MARK: - Persistence

    func testOutboxSurvivesReload() {
        transport.script([.retryableFailure(status: 503)])
        let outbox = makeOutbox(flushThreshold: 1)
        outbox.log(event())
        XCTAssertEqual(outbox.pendingCount, 1)

        let reloaded = makeOutbox(flushThreshold: 1000)
        reloaded.load()
        XCTAssertEqual(reloaded.pendingCount, 1)
    }

    func testOutboxForADifferentCustomerIsNotAdopted() {
        transport.script([.retryableFailure(status: 503)])
        let outbox = makeOutbox(flushThreshold: 1)
        outbox.log(event())
        drain(outbox)

        let other = BatchedMessageAnalytics(transport: transport,
                                            store: store,
                                            customerId: "cust-2",
                                            flushInterval: 3600,
                                            flushThreshold: 1000,
                                            batchSize: 50,
                                            ceiling: 500)
        other.load()
        XCTAssertEqual(other.pendingCount, 0)
    }

    // MARK: - Ceiling

    func testCeilingDropsOldestAndLogs() {
        let outbox = makeOutbox(flushThreshold: 1000, ceiling: 3)

        let first = event(0)
        outbox.log(first)
        let logs = capturingIAMLog {
            outbox.log(event(1))
            outbox.log(event(2))
            outbox.log(event(3))
            drain(outbox)
        }

        XCTAssertEqual(outbox.pendingCount, 3, "the ceiling must bound the outbox")
        XCTAssertTrue(logs.contains { $0.lowercased().contains("dropped") },
                      "an eviction was not reported: \(logs)")

        // The oldest went, not the newest.
        transport.script([.success(Data("{}".utf8))])
        outbox.flush()
        drain(outbox)
        XCTAssertFalse(transport.sentUids.first?.contains(first.eventUid) ?? true,
                       "the oldest event should have been evicted")
    }

    // MARK: - Concurrency

    func testOneRequestInFlightAtATime() {
        // No scripted outcomes, so the first request is held open.
        let outbox = makeOutbox(flushThreshold: 1000)
        log(outbox, count: 4)

        outbox.flush()
        drain(outbox)
        XCTAssertEqual(transport.postCount, 1)
        XCTAssertEqual(transport.inFlight, 1)

        outbox.flush()
        drain(outbox)
        XCTAssertEqual(transport.postCount, 1, "a second flush double-sent while one was open")

        transport.release(.success(Data("{}".utf8)))
        XCTAssertEqual(outbox.pendingCount, 0)
    }

    /// The outbox is FIFO, so one permanently-rejected batch at the head would otherwise
    /// take every event behind it down until the ceiling rotated it out.
    func testPoisonBatchDoesNotBlockLaterEvents() {
        transport.script([.permanentFailure(status: 400), .success(Data("{}".utf8))])
        let outbox = makeOutbox(flushThreshold: 2, batchSize: 2)

        log(outbox, count: 2)          // first batch: rejected permanently, discarded
        XCTAssertEqual(outbox.pendingCount, 0)
        XCTAssertEqual(transport.postCount, 1)

        log(outbox, count: 2)          // second batch must still go out
        XCTAssertEqual(transport.postCount, 2)
        XCTAssertEqual(outbox.pendingCount, 0)
    }

    func testFlushOnAnEmptyOutboxSendsNothing() {
        let outbox = makeOutbox()
        outbox.flush()
        drain(outbox)
        XCTAssertEqual(transport.postCount, 0)
    }
}
