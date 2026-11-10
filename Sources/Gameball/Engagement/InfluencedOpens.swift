//
//  InfluencedOpens.swift
//  Gameball
//

import Foundation

/// A Gameball push that reached the device and hasn't been tapped. `key` identifies the push.
struct ReceivedPush: Codable, Equatable {
    let key: String
    let clickToken: String?
    let sentAt: Int64?
    let receivedAt: Int64
}

/// Where received pushes are kept between app launches.
protocol ReceivedPushStore {
    func load() -> [ReceivedPush]
    func save(_ pushes: [ReceivedPush])
}

/// Influenced opens: a push arrived, the user didn't tap it, and opened the app within
/// `windowMillis` of receiving it.
///
/// - received → saved
/// - tapped → removed; it's a normal tap and never counts as influenced
/// - app opened by a tap → a normal click; nothing is influenced, even by an older untapped push
/// - app opened otherwise → if the most recent saved push arrived within the window, that push
///   influenced the open
///
/// Every open clears the saved list.
final class InfluencedOpens {

    static let windowMillis: Int64 = 30 * 60 * 1000
    static let maxSaved = 20

    private let store: ReceivedPushStore
    private let now: () -> Int64
    private let windowMillis: Int64
    private let lock = NSLock()

    init(store: ReceivedPushStore,
         now: @escaping () -> Int64 = currentTimeMillis,
         windowMillis: Int64 = InfluencedOpens.windowMillis) {
        self.store = store
        self.now = now
        self.windowMillis = windowMillis
    }

    func onReceived(key: String, clickToken: String?, sentAt: Int64?) {
        lock.lock(); defer { lock.unlock() }
        let pushes = store.load().filter { $0.key != key }
            + [ReceivedPush(key: key, clickToken: clickToken, sentAt: sentAt, receivedAt: now())]
        store.save(Array(pushes.suffix(InfluencedOpens.maxSaved)))
    }

    func onTap(key: String) {
        lock.lock(); defer { lock.unlock() }
        let pushes = store.load()
        if pushes.contains(where: { $0.key == key }) {
            store.save(pushes.filter { $0.key != key })
        }
    }

    /// The push that influenced `open`, or nil for an ordinary open.
    func influencedBy(_ open: AppOpen) -> ReceivedPush? {
        lock.lock(); defer { lock.unlock() }
        let pushes = store.load()
        if pushes.isEmpty { return nil }
        store.save([])
        if open.fromTap { return nil }
        guard let latest = pushes.max(by: { $0.receivedAt < $1.receivedAt }) else { return nil }
        let elapsed = open.openedAt - latest.receivedAt
        return (0...windowMillis).contains(elapsed) ? latest : nil
    }

    /// Another customer's pushes must never credit this customer's opens.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        store.save([])
    }
}
