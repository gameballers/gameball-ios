//
//  PushEngagement.swift
//  Gameball
//

import Foundation

/// What a customer did with a Gameball push. The numbers are the backend's own: never renumber.
enum PushEngagementType: Int {
    /// Tapped the notification or one of its action buttons.
    case clicked = 1
    /// Swiped it away, or tapped a "Later" / "No thanks" button. The iOS SDK doesn't detect this yet.
    case dismissed = 2
    /// Didn't tap, but opened the app on their own soon after receiving it.
    case influencedOpen = 3
}

/// One engagement with a push, as the push-engagement endpoint takes it.
struct PushEngagement {
    let clickToken: String
    let type: PushEngagementType
    /// When it happened, in milliseconds since 1970.
    let occurredAt: Int64
    /// New for every event, so the backend can drop a repeat of the same one.
    let eventUid: String

    init(clickToken: String, type: PushEngagementType, occurredAt: Int64, eventUid: String = UUID().uuidString) {
        self.clickToken = clickToken
        self.type = type
        self.occurredAt = occurredAt
        self.eventUid = eventUid
    }

    /// The JSON body. `engagementType` is a number; `occurredAt` is UTC ISO-8601 with milliseconds.
    var body: [String: Any] {
        return [
            "clickToken": clickToken,
            "engagementType": type.rawValue,
            "eventUid": eventUid,
            "occurredAt": PushEngagement.isoTimestamp(occurredAt)
        ]
    }

    /// e.g. "2026-11-09T18:00:00.000Z". Whole seconds go through the formatter and the milliseconds
    /// are added as an integer, so floating point can never turn .807 into .806.
    static func isoTimestamp(_ millis: Int64) -> String {
        let seconds = millis >= 0 ? millis / 1000 : (millis - 999) / 1000
        let ms = String(millis - seconds * 1000)
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        return secondsFormatter.string(from: date) + "." + String(repeating: "0", count: 3 - ms.count) + ms + "Z"
    }

    private static let secondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
