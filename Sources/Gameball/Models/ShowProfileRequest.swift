//
//  ShowProfileRequest.swift
//  Gameball
//

import Foundation

/// Profile display request
public struct ShowProfileRequest {
    public let customerId: String
    public let openDetail: String?
    public let hideNavigation: Bool?
    public let showCloseButton: Bool?
    public let closeButtonColor: String?
    public let widgetUrlPrefix: String?

    /// Initialize profile display request with validation
    /// - Throws: `GameballError` if validation fails
    /// - Parameters:
    ///   - customerId: Required customer identifier (cannot be empty)
    ///   - openDetail: Optional specific section to open (e.g., "achievements", "leaderboard")
    ///   - hideNavigation: Optional flag to hide navigation in widget
    ///   - showCloseButton: Optional flag to show close button (defaults to true)
    ///   - closeButtonColor: Optional close button color as hex string (e.g., "#FF0000", defaults to "#CECECE")
    ///   - widgetUrlPrefix: Optional custom widget URL (currently unused)
    public init(
        customerId: String,
        openDetail: String? = nil,
        hideNavigation: Bool? = nil,
        showCloseButton: Bool? = nil,
        closeButtonColor: String? = nil,
        widgetUrlPrefix: String? = nil
    ) throws {
        // Validation: Customer ID cannot be empty
        guard !customerId.isEmpty else {
            throw GameballError.emptyCustomerId
        }

        self.customerId = customerId
        self.openDetail = openDetail
        self.hideNavigation = hideNavigation
        self.showCloseButton = showCloseButton
        self.closeButtonColor = closeButtonColor
        self.widgetUrlPrefix = widgetUrlPrefix
    }
}
