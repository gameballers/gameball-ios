//
//  CustomerAttributes.swift
//  Gameball
//

import Foundation

/// Customer profile attributes
public struct CustomerAttributes {
    public let displayName: String?
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let gender: String?
    public let mobile: String?
    public let dateOfBirth: String?
    public let joinDate: String?
    public let preferredLanguage: String?
    internal let channel: String
    public let customAttributes: [String: String]?
    public let additionalAttributes: [String: String]?

    /// Initialize customer attributes with optional parameters
    /// Channel is always set to "mobile" internally and cannot be changed
    public init(
        displayName: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        gender: String? = nil,
        mobile: String? = nil,
        dateOfBirth: String? = nil,
        joinDate: String? = nil,
        preferredLanguage: String? = nil,
        customAttributes: [String: String]? = nil,
        additionalAttributes: [String: String]? = nil
    ) {
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.gender = gender
        self.mobile = mobile
        self.dateOfBirth = dateOfBirth
        self.joinDate = joinDate
        self.preferredLanguage = preferredLanguage
        self.channel = "mobile"
        self.customAttributes = customAttributes
        self.additionalAttributes = additionalAttributes
    }
}

// MARK: - Codable Conformance
extension CustomerAttributes: Codable {
    private enum CodingKeys: String, CodingKey {
        case displayName, firstName, lastName, email, gender, mobile
        case dateOfBirth, joinDate, preferredLanguage, channel
        case customAttributes = "custom"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(mobile, forKey: .mobile)
        try container.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
        try container.encodeIfPresent(joinDate, forKey: .joinDate)
        try container.encodeIfPresent(preferredLanguage, forKey: .preferredLanguage)
        try container.encode(channel, forKey: .channel)
        try container.encodeIfPresent(customAttributes, forKey: .customAttributes)
        // additionalAttributes is intentionally not encoded here - handled by AttributesHelper
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        mobile = try container.decodeIfPresent(String.self, forKey: .mobile)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        joinDate = try container.decodeIfPresent(String.self, forKey: .joinDate)
        preferredLanguage = try container.decodeIfPresent(String.self, forKey: .preferredLanguage)
        channel = try container.decode(String.self, forKey: .channel)
        customAttributes = try container.decodeIfPresent([String: String].self, forKey: .customAttributes)
        // additionalAttributes is not decoded from API responses
        additionalAttributes = nil
    }
}
