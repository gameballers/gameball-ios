//
//  GameballError.swift
//  Gameball
//

import Foundation

/// Gameball SDK errors
public enum GameballError: LocalizedError {
    case notInitialized
    case invalidConfiguration(String)
    case networkError(Error)
    case apiError(Int, String)
    case invalidRequest(String)
    case unknown

    // Validation errors
    case emptyCustomerId
    case missingDeviceToken
    case missingPushProvider
    case emptyEvents
    case invalidCustomerId

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "SDK must be initialized before use"
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .invalidRequest(let details):
            return "Invalid request: \(details)"
        case .unknown:
            return "An unknown error occurred"
        case .emptyCustomerId:
            return "Customer ID cannot be empty"
        case .missingDeviceToken:
            return "Device token is required when push provider is set"
        case .missingPushProvider:
            return "Push provider is required when device token is set"
        case .emptyEvents:
            return "Events dictionary cannot be empty"
        case .invalidCustomerId:
            return "Invalid or missing customer ID"
        }
    }

    public var failureReason: String? {
        switch self {
        case .notInitialized:
            return "SDK initialization was not called or failed"
        case .invalidConfiguration:
            return "Configuration parameters are invalid"
        case .networkError:
            return "Network connectivity or server issue"
        case .apiError(let code, _):
            return "Server returned error code \(code)"
        case .invalidRequest:
            return "Request parameters are invalid"
        case .unknown:
            return "Unexpected error condition"
        case .emptyCustomerId:
            return "Customer ID is required and cannot be empty"
        case .missingDeviceToken:
            return "Push provider was specified but device token is missing or empty"
        case .missingPushProvider:
            return "Device token was provided but push provider is missing"
        case .emptyEvents:
            return "At least one event must be provided"
        case .invalidCustomerId:
            return "Customer ID is required for this operation"
        }
    }
}
