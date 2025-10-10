//
//  InitializeCustomerRequest.swift
//  Gameball
//

import Foundation

/// Customer initialization request with built-in validation
public struct InitializeCustomerRequest {
    public let customerId: String
    public let deviceToken: String?
    public let pushProvider: PushProvider?
    internal let osType: String
    public let customerAttributes: CustomerAttributes?
    public let referralCode: String?
    public let email: String?
    public let mobile: String?
    public let isGuest: Bool

    /// Initialize customer request with validation
    /// - Throws: `GameballError` if validation fails
    /// - Parameters:
    ///   - customerId: Required unique customer identifier (cannot be empty)
    ///   - deviceToken: Optional push notification token
    ///   - pushProvider: Optional push provider (required if deviceToken is provided)
    ///   - customerAttributes: Optional customer profile attributes
    ///   - referralCode: Optional referral code
    ///   - email: Optional customer email
    ///   - mobile: Optional customer mobile number
    ///   - isGuest: Whether customer is a guest (defaults to false)
    public init(
        customerId: String,
        deviceToken: String? = nil,
        pushProvider: PushProvider? = nil,
        customerAttributes: CustomerAttributes? = nil,
        referralCode: String? = nil,
        email: String? = nil,
        mobile: String? = nil,
        isGuest: Bool = false
    ) throws {
        // Validation 1: Customer ID cannot be empty
        guard !customerId.isEmpty else {
            throw GameballError.emptyCustomerId
        }

        // Validation 2: Push provider and device token dependency
        if let provider = pushProvider, deviceToken?.isEmpty ?? true {
            throw GameballError.missingDeviceToken
        }

        if pushProvider == nil, let token = deviceToken, !token.isEmpty {
            throw GameballError.missingPushProvider
        }

        // All validations passed, assign values
        self.customerId = customerId
        self.deviceToken = deviceToken
        self.pushProvider = pushProvider
        self.osType = "iOS"
        self.customerAttributes = customerAttributes ?? CustomerAttributes()
        self.referralCode = referralCode
        self.email = email
        self.mobile = mobile
        self.isGuest = isGuest
    }
}

// MARK: - Codable Conformance
extension InitializeCustomerRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case customerId
        case deviceToken
        case pushProvider = "pushServiceProvider"
        case osType
        case customerAttributes
        case referralCode = "referrerCode"
        case email
        case mobile
        case isGuest = "guest"
    }
}
