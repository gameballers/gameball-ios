//
//  MessageEvent.swift
//  Gameball
//

import Foundation

/// The three things a message can report. `submit` exists on the wire for email capture,
/// which is out of scope.
enum MessageEventType: String, Codable {
    case impression
    case click
    case dismiss
}

/// One reportable moment in a message's life.
///
/// `Codable` because the outbox persists undelivered events across launches.
struct MessageEvent: Codable {
    /// A lowercased v4 UUID, generated once when the event happens and **never** regenerated
    /// on retry — regenerating would make a retried impression count twice. A non-GUID is a
    /// hard 400 that discards the entire batch rather than one event.
    let eventUid: String
    let dispatchId: String?
    let campaignId: Int
    let variationId: Int?
    let type: MessageEventType
    /// When it happened on the device, never when it was sent. Events can arrive hours late,
    /// and conversion windows and per-day unique-impression counts anchor to this field.
    let occurredAt: Date
    let buttonId: String?
    let url: String?

    init(campaignId: Int,
         variationId: Int?,
         dispatchId: String?,
         type: MessageEventType,
         occurredAt: Date,
         buttonId: String? = nil,
         url: String? = nil,
         eventUid: String = MessageEvent.newEventUid()) {
        self.campaignId = campaignId
        self.variationId = variationId
        self.dispatchId = dispatchId
        self.type = type
        self.occurredAt = occurredAt
        self.buttonId = buttonId
        self.url = url
        self.eventUid = eventUid
    }

    static func newEventUid() -> String {
        return UUID().uuidString.lowercased()
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// The wire form. Optional fields are omitted rather than sent as null, so a click with
    /// no button is not conflated with a click on an unknown one.
    func wireDictionary() -> [String: Any] {
        var json: [String: Any] = [
            "eventUid": eventUid,
            "campaignId": campaignId,
            "type": type.rawValue,
            "occurredAt": MessageEvent.iso8601.string(from: occurredAt)
        ]
        if let variationId = variationId { json["variationId"] = variationId }
        if let dispatchId = dispatchId { json["dispatchId"] = dispatchId }
        if let buttonId = buttonId { json["buttonId"] = buttonId }
        if let url = url { json["url"] = url }
        return json
    }
}
