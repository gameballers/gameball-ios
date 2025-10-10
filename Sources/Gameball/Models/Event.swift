//
//  Event.swift
//  Gameball
//

import Foundation

/// Event model for sending customer events
public struct Event: Codable {
    let events: [String: [String: Any]]
    let customerId: String
    let mobile: String?
    let email: String?

    /// Initialize event with validation
    /// - Throws: `GameballError` if validation fails
    /// - Parameters:
    ///   - events: Dictionary of event names and their parameters (cannot be empty)
    ///   - customerId: Required customer identifier (cannot be empty)
    ///   - mobile: Optional customer mobile number
    ///   - email: Optional customer email
    public init(
        events: [String: [String: Any]],
        customerId: String,
        mobile: String? = nil,
        email: String? = nil
    ) throws {
        // Validation 1: Customer ID cannot be empty
        guard !customerId.isEmpty else {
            throw GameballError.emptyCustomerId
        }

        // Validation 2: Events dictionary cannot be empty
        guard !events.isEmpty else {
            throw GameballError.emptyEvents
        }

        self.events = events
        self.customerId = customerId
        self.mobile = mobile
        self.email = email
    }
}

// MARK: - Codable Conformance
extension Event {
    enum CodingKeys: String, CodingKey {
        case events
        case customerId
        case mobile
        case email
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let customerId = try container.decode(String.self, forKey: .customerId)
        let eventsDict = try container.decode([String: [String: Any]].self, forKey: .events)
        let mobile = try container.decodeIfPresent(String.self, forKey: .mobile)
        let email = try container.decodeIfPresent(String.self, forKey: .email)

        try self.init(
            events: eventsDict,
            customerId: customerId,
            mobile: mobile,
            email: email
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encode(customerId, forKey: .customerId)
        try container.encodeIfPresent(mobile, forKey: .mobile)
        try container.encodeIfPresent(email, forKey: .email)
    }
}

// Helper for encoding [String: Any]
extension KeyedEncodingContainer {
    mutating func encode(_ value: [String: [String: Any]], forKey key: Key) throws {
        var nestedContainer = self.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
        for (eventKey, eventValue) in value {
            try nestedContainer.encode(AnyCodableDict(eventValue), forKey: AnyCodingKey(stringValue: eventKey))
        }
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: [String: [String: Any]].Type, forKey key: Key) throws -> [String: [String: Any]] {
        let nestedContainer = try self.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
        var result: [String: [String: Any]] = [:]
        for eventKey in nestedContainer.allKeys {
            let dict = try nestedContainer.decode(AnyCodableDict.self, forKey: eventKey)
            result[eventKey.stringValue] = dict.value
        }
        return result
    }
}

// Helper for dynamic keys
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

// Helper for encoding/decoding [String: Any]
struct AnyCodableDict: Codable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var result: [String: Any] = [:]

        for key in container.allKeys {
            if let stringVal = try? container.decode(String.self, forKey: key) {
                result[key.stringValue] = stringVal
            } else if let intVal = try? container.decode(Int.self, forKey: key) {
                result[key.stringValue] = intVal
            } else if let doubleVal = try? container.decode(Double.self, forKey: key) {
                result[key.stringValue] = doubleVal
            } else if let boolVal = try? container.decode(Bool.self, forKey: key) {
                result[key.stringValue] = boolVal
            }
        }
        self.value = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)

        for (key, val) in value {
            let codingKey = AnyCodingKey(stringValue: key)
            if let stringVal = val as? String {
                try container.encode(stringVal, forKey: codingKey)
            } else if let intVal = val as? Int {
                try container.encode(intVal, forKey: codingKey)
            } else if let doubleVal = val as? Double {
                try container.encode(doubleVal, forKey: codingKey)
            } else if let boolVal = val as? Bool {
                try container.encode(boolVal, forKey: codingKey)
            }
        }
    }
}
