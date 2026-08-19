//
//  VariableSource.swift
//  Gameball
//

import Foundation

/// Fetches the personalisation values a message's tokens need.
///
/// Never throws and never blocks a display: every failure — 404, 422, 503, a timeout, no network
/// — resolves to whatever values are already held, which may be none. The caller's correct
/// response to all of them is identical, so there is nothing worth distinguishing.
///
/// The endpoint is not deployed as of 2026-08-18 and answers 404 with an empty body. This is
/// built to do nothing gracefully until it is.
final class VariableSource {

    private let transport: IAMTransport
    private let store: IAMStore
    private let customerId: String
    private let timeout: TimeInterval
    private let cacheTTL: TimeInterval
    private let now: () -> Date

    private let queue = DispatchQueue(label: "co.gameball.inappmessaging.variables")
    private var held: [String: String] = [:]
    private var fetchedAt: Date?
    private var persistableTokens: Set<String> = []
    /// Bumped by `clear`. A fetch captures it and refuses to write if it changed while the
    /// request was open.
    private var generation = 0

    init(transport: IAMTransport,
         store: IAMStore,
         customerId: String,
         timeout: TimeInterval = 2,
         cacheTTL: TimeInterval = 60,
         now: @escaping () -> Date = Date.init) {
        self.transport = transport
        self.store = store
        self.customerId = customerId
        self.timeout = timeout
        self.cacheTTL = cacheTTL
        self.now = now
        loadPersisted()
    }

    /// Always calls back, exactly once.
    func values(neededTokens: Set<String>, completion: @escaping ([String: String]) -> Void) {
        // No tokens means no reason to ask. This is what keeps personalisation entirely inert
        // for the campaigns that do not use it.
        guard !neededTokens.isEmpty else {
            completion([:])
            return
        }

        queue.async {
            if let fetchedAt = self.fetchedAt,
               self.now().timeIntervalSince(fetchedAt) < self.cacheTTL {
                let cached = self.held
                completion(cached)
                return
            }
            self.fetch(completion: completion)
        }
    }

    /// Called on every event and purchase, never on session start: a balance can change between
    /// two events within one session, but nothing can have changed before the session began.
    func forgetCachedValues() {
        queue.async { self.fetchedAt = nil }
    }

    /// Narrows what is written to disk to the tokens the held campaigns actually use.
    ///
    /// The response can contain anything the backend chose to send, including an email address
    /// or a phone number. Persisting a value no campaign references would be storing PII for no
    /// reason at all.
    func setPersistableTokens(_ tokens: Set<String>) {
        queue.async {
            self.persistableTokens = tokens
            self.persist()
        }
    }

    func clear() {
        queue.async {
            self.generation += 1
            self.held = [:]
            self.fetchedAt = nil
            self.store.set(nil, forKey: IAMStoreKey.variables)
        }
    }

    // MARK: - Internals

    /// Must be called on `queue`.
    private func fetch(completion: @escaping ([String: String]) -> Void) {
        let startedGeneration = generation
        var hasCompleted = false

        // Bounded independently of the transport: a display must never wait on personalisation.
        queue.asyncAfter(deadline: .now() + timeout) {
            guard !hasCompleted else { return }
            hasCompleted = true
            iamLog("variables did not answer within \(self.timeout)s; using what is held")
            completion(self.held)
        }

        transport.post(path: IAMEndpoint.variables,
                       body: ["customerId": customerId]) { [weak self] outcome in
            guard let self = self else {
                if !hasCompleted { hasCompleted = true; completion([:]) }
                return
            }
            self.queue.async {
                guard !hasCompleted else { return }
                hasCompleted = true

                guard case .success(let data) = outcome else {
                    // Every failure is the same answer.
                    completion(self.held)
                    return
                }

                let parsed = VariableSource.parse(data)

                // Re-checked *here*, after the request came back. A check performed before it
                // was sent always passes, because the clear had not been issued yet.
                guard startedGeneration == self.generation else {
                    iamLog("discarding variables fetched for a customer who has since changed")
                    completion([:])
                    return
                }

                self.held = parsed
                self.fetchedAt = self.now()
                self.persist()
                completion(parsed)
            }
        }
    }

    private static func parse(_ data: Data) -> [String: String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data, options: []))
                as? [String: Any],
              let variables = root["variables"] as? [String: Any] else {
            return [:]
        }

        var values: [String: String] = [:]
        for (key, value) in variables {
            if let string = value as? String {
                values[key] = string
            } else if let number = value as? NSNumber {
                // Defensive: the contract is pre-formatted strings, but a raw number is better
                // rendered than dropped.
                values[key] = number.stringValue
            }
        }
        return values
    }

    /// Must be called on `queue`.
    private func persist() {
        let persistable = held.filter { persistableTokens.contains($0.key) }
        guard !persistable.isEmpty else {
            store.set(nil, forKey: IAMStoreKey.variables)
            return
        }
        store.set(CustomerScoped.encoded(persistable, customerId: customerId),
                  forKey: IAMStoreKey.variables)
    }

    private func loadPersisted() {
        held = CustomerScoped<[String: String]>.decode(store.data(forKey: IAMStoreKey.variables),
                                                     customerId: customerId) ?? [:]
    }
}
