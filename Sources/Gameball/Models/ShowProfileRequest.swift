//
//  ShowProfileRequest.swift
//  Gameball
//

import Foundation

/// Profile display request
public struct ShowProfileRequest {
    public let customerId: String?
    public let openDetail: String?
    public let hideNavigation: Bool?
    public let showCloseButton: Bool?
    public let closeButtonColor: String?
    public let widgetUrlPrefix: String?
    public let mobile: String?
    public let email: String?

    /// Initialize profile display request
    /// - Parameters:
    ///   - customerId: Optional customer identifier. When not provided, opens the guest view
    ///   - openDetail: Optional specific section to open (e.g., "achievements", "leaderboard")
    ///   - hideNavigation: Optional flag to hide navigation in widget
    ///   - showCloseButton: Optional flag to show close button (defaults to true)
    ///   - closeButtonColor: Optional close button color as hex string (e.g., "#FF0000", defaults to "#CECECE")
    ///   - widgetUrlPrefix: Optional custom widget URL (currently unused)
    ///   - mobile: Optional customer mobile number
    ///   - email: Optional customer email address
    public init(
        customerId: String? = nil,
        openDetail: String? = nil,
        hideNavigation: Bool? = nil,
        showCloseButton: Bool? = nil,
        closeButtonColor: String? = nil,
        widgetUrlPrefix: String? = nil,
        mobile: String? = nil,
        email: String? = nil
    ) {
        self.customerId = customerId
        self.openDetail = openDetail
        self.hideNavigation = hideNavigation
        self.showCloseButton = showCloseButton
        self.closeButtonColor = closeButtonColor
        self.widgetUrlPrefix = widgetUrlPrefix
        self.mobile = mobile
        self.email = email
    }
}
