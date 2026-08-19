//
//  IAMStore.swift
//  Gameball
//

import Foundation

/// The keys the module persists under.
///
/// All share a prefix so `removeAll` can clear exactly what the module owns, even if the
/// suite is ever shared with something else.
enum IAMStoreKey {
    static let prefix = "gameball_iam_"

    static let displayHistory  = "gameball_iam_display_history"
    static let campaignCache   = "gameball_iam_campaign_cache"
    static let analyticsOutbox = "gameball_iam_analytics_outbox"
    static let variables       = "gameball_iam_variables"
}

/// Byte-level key-value storage.
///
/// A protocol rather than `UserDefaults` directly, so every suite in the test target can
/// inject `InMemoryIAMStore` and the real suite is never written to by a test.
protocol IAMStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    /// Clears everything the module owns.
    func removeAll()
}

/// The shipping store: a `UserDefaults` suite of the module's own.
///
/// A dedicated suite keeps campaign payloads and cap history out of the host app's
/// preferences plist. There is no read timeout here — the port specification requires one
/// because Flutter's `shared_preferences` crosses a platform channel that can wedge, while
/// `UserDefaults` is in-process and synchronous.
final class UserDefaultsIAMStore: IAMStore {
    private let defaults: UserDefaults

    init(suiteName: String = "co.gameball.inappmessaging") {
        if let suite = UserDefaults(suiteName: suiteName) {
            self.defaults = suite
        } else {
            // Losing persistence entirely would mean re-showing once-ever messages, so
            // falling back is the lesser evil — but it is loud, because it also means the
            // module's keys are now in the host's plist.
            iamLog("could not open the UserDefaults suite '\(suiteName)'; falling back to "
                 + "UserDefaults.standard")
            self.defaults = .standard
        }
    }

    func data(forKey key: String) -> Data? {
        return defaults.data(forKey: key)
    }

    func set(_ data: Data?, forKey key: String) {
        if let data = data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func removeAll() {
        // Only the module's own keys. `removePersistentDomain` would also discard anything
        // else sharing the suite, and the fallback path above can make that the host's.
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(IAMStoreKey.prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Test double. Holds bytes in memory and forgets them when it dies.
final class InMemoryIAMStore: IAMStore {
    private var storage: [String: Data] = [:]

    init() {}

    func data(forKey key: String) -> Data? {
        return storage[key]
    }

    func set(_ data: Data?, forKey key: String) {
        if let data = data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func removeAll() {
        storage.removeAll()
    }
}

/// Wraps a stored value with the customer it belongs to, so a mismatch is discarded at
/// read rather than served to the wrong person.
///
/// One slot stamped with its owner, deliberately not one key per customer: the latter
/// would retain every previous customer's data indefinitely, including the PII the
/// variables store holds.
struct CustomerScoped<T: Codable>: Codable {
    let customerId: String
    let value: T

    /// Returns `nil` rather than throwing — a value that cannot be encoded is a value we
    /// simply do not persist, and the module never throws into the host.
    static func encoded(_ value: T, customerId: String) -> Data? {
        do {
            return try JSONEncoder().encode(CustomerScoped(customerId: customerId, value: value))
        } catch {
            iamLog("could not encode stored value: \(error.localizedDescription)")
            return nil
        }
    }

    /// Decodes only when the stored value belongs to `customerId`. Corrupt bytes, a stamp
    /// for someone else, and nothing stored at all are all the same answer: `nil`.
    static func decode(_ data: Data?, customerId: String) -> T? {
        guard let data = data else { return nil }
        guard let stored = try? JSONDecoder().decode(CustomerScoped<T>.self, from: data) else {
            iamLog("discarding unreadable stored value")
            return nil
        }
        guard stored.customerId == customerId else {
            iamLog("discarding stored value belonging to a different customer")
            return nil
        }
        return stored.value
    }
}
