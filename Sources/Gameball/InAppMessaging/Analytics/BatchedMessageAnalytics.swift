//
//  BatchedMessageAnalytics.swift
//  Gameball
//

import Foundation

/// A persisted, batched outbox for message telemetry.
///
/// Every mutation happens on one serial queue, which is what makes `isSending` a reliable
/// single-in-flight guard without a lock. Events are written to the store after every change,
/// so a crash or a kill loses at most the events that never reached the queue.
///
/// The delivery semantics are the substance:
///
///   * `2xx` accepts the batch and clears it, whatever the body says. A mixed batch comes
///     back `202 {accepted, rejected}` — one bad event does not poison the good ones — so
///     clearing does not lose the accepted events. A non-zero `rejected` is reported because
///     those events can never succeed.
///   * `400`, `401`, `404`, `422` discard the batch permanently and loudly. Retrying cannot
///     change the answer, and the outbox is FIFO, so keeping a poison batch at the head would
///     take every event behind it down until the ceiling rotated it out.
///   * `408`, `429`, `5xx` and transport errors keep the batch for the next attempt.
final class BatchedMessageAnalytics: MessageAnalytics {
    private let transport: IAMTransport
    private let store: IAMStore
    private let customerId: String
    private let flushInterval: TimeInterval
    private let flushThreshold: Int
    private let batchSize: Int
    private let ceiling: Int

    private let queue = DispatchQueue(label: "co.gameball.inappmessaging.analytics")
    /// Marks the queue so `perform` can tell "already here" from "arriving from outside".
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var pending: [MessageEvent] = []
    private var isSending = false
    /// A `DispatchSourceTimer` rather than a `Timer`: it fires on the queue that owns the
    /// state and needs no run loop, so it behaves identically in an app and in a test.
    private var timer: DispatchSourceTimer?

    init(transport: IAMTransport,
         store: IAMStore,
         customerId: String,
         flushInterval: TimeInterval = 30,
         flushThreshold: Int = 10,
         batchSize: Int = 50,
         ceiling: Int = 500) {
        self.transport = transport
        self.store = store
        self.customerId = customerId
        self.flushInterval = flushInterval
        self.flushThreshold = flushThreshold
        self.batchSize = batchSize
        self.ceiling = ceiling
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        timer?.cancel()
    }

    /// Runs `work` with the queue's exclusivity, inline when the caller is already on it.
    ///
    /// The inline case matters for correctness, not just efficiency. A transport that answers
    /// synchronously calls back from inside `flushLocked`, still on this queue; re-dispatching
    /// there would let a later-enqueued read observe the batch as still pending, because the
    /// state change would be ordered behind it.
    private func perform(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.async(execute: work)
        }
    }

    /// Test visibility. Reading synchronously on the queue also serves as a barrier, so a
    /// test can assert state without sleeping.
    var pendingCount: Int {
        return queue.sync { pending.count }
    }

    // MARK: - MessageAnalytics

    func load() {
        queue.sync {
            pending = CustomerScoped<[MessageEvent]>.decode(store.data(forKey: IAMStoreKey.analyticsOutbox),
                                                          customerId: customerId) ?? []
            if !pending.isEmpty {
                iamLog("recovered \(pending.count) undelivered event(s) from a previous launch")
            }
            startTimerLocked()
        }
    }

    func log(_ event: MessageEvent) {
        queue.async {
            self.pending.append(event)

            if self.pending.count > self.ceiling {
                // Oldest first: a stale impression matters less than the one that just
                // happened, and an unbounded outbox on a device with no network is a leak.
                let excess = self.pending.count - self.ceiling
                self.pending.removeFirst(excess)
                iamLog("outbox is at its \(self.ceiling)-event ceiling; dropped \(excess) "
                     + "of the oldest event(s)")
            }

            self.persistLocked()
            self.startTimerLocked()

            if self.pending.count >= self.flushThreshold {
                self.flushLocked()
            }
        }
    }

    func flush() {
        queue.async { self.flushLocked() }
    }

    func dispose() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    // MARK: - Queue-confined internals

    private func startTimerLocked() {
        guard timer == nil, flushInterval > 0 else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        source.setEventHandler { [weak self] in
            self?.flushLocked()
        }
        source.resume()
        timer = source
    }

    private func flushLocked() {
        guard !isSending else { return }
        guard !pending.isEmpty else { return }

        let batch = Array(pending.prefix(batchSize))
        isSending = true

        let body: [String: Any] = [
            "customerId": customerId,
            "events": batch.map { $0.wireDictionary() }
        ]

        transport.post(path: IAMEndpoint.events, body: body) { [weak self] outcome in
            guard let self = self else { return }
            self.perform {
                self.isSending = false
                self.handleLocked(outcome: outcome, batch: batch)
            }
        }
    }

    private func handleLocked(outcome: IAMHTTPOutcome, batch: [MessageEvent]) {
        switch outcome {
        case .success(let data):
            reportRejections(in: data)
            drop(batch)
            // More may be waiting behind this batch.
            flushLocked()

        case .permanentFailure(let status):
            iamLog("DISCARDING \(batch.count) event(s) permanently: the events endpoint "
                 + "returned \(status). These will never be reported.")
            drop(batch)
            flushLocked()

        case .retryableFailure(let status):
            let reported = status.map(String.init) ?? "a transport error"
            iamLog("keeping \(batch.count) event(s) for retry after \(reported)")
        }
    }

    /// Removes the sent slice by identity rather than by index, because the outbox may have
    /// grown or been trimmed by the ceiling while the request was open.
    private func drop(_ batch: [MessageEvent]) {
        let sent = Set(batch.map { $0.eventUid })
        pending = pending.filter { !sent.contains($0.eventUid) }
        persistLocked()
    }

    private func reportRejections(in data: Data) {
        guard let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let rejected = json["rejected"] as? Int, rejected > 0 else {
            return
        }
        iamLog("the events endpoint rejected \(rejected) event(s); they can never succeed")
    }

    private func persistLocked() {
        store.set(CustomerScoped.encoded(pending, customerId: customerId),
                  forKey: IAMStoreKey.analyticsOutbox)
    }
}
