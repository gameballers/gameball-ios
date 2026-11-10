//
//  GameballPush.swift
//  Gameball
//

import Foundation

/// A push Gameball's backend sent, read the same way wherever it shows up: a tap the app reports
/// or an arrival the Notification Service Extension reports. Anything without `isGB = "true"`
/// is not one of ours and never becomes a GameballPush.
struct GameballPush {

    static let isGBKey = "isGB"
    static let clickTokenKey = "gbClickToken"
    /// FCM's message id, present on every message FCM delivers to iOS.
    static let messageIdKey = "gcm.message_id"
    /// FCM's send time in seconds. Only messages sent with FCM analytics carry it.
    static let sentTimeKey = "google.c.a.ts"

    /// The token the backend issued for this push; nil when it carries none.
    let clickToken: String?
    /// The same push seen twice gives the same key.
    let key: String?
    /// When the push was sent, in milliseconds, when the payload says so.
    let sentAt: Int64?

    init?(payload: [AnyHashable: Any]) {
        guard let isGB = payload[GameballPush.isGBKey] as? String,
              isGB.caseInsensitiveCompare("true") == .orderedSame else { return nil }
        let token = (payload[GameballPush.clickTokenKey] as? String).flatMap {
            $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0
        }
        clickToken = token
        key = token ?? GameballPush.string(payload[GameballPush.messageIdKey])
        sentAt = GameballPush.string(payload[GameballPush.sentTimeKey])
            .flatMap { Double($0) }
            .map { Int64(($0 * 1000).rounded()) }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}
