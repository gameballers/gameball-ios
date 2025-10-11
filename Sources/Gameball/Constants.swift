//
//  Constants.swift
//  gameball_SDK
//
//  Created by Martin Sorsok on 2/3/19.
//  Copyright © 2019 Martin Sorsok. All rights reserved.
//

import Foundation

class APIEndPoints {
    static let base_URL = "https://api.gameball.co"
    static let widget_URL = "https://m.gameball.app"

    static let getBotStyle = "/api/v1.0/Bots/BotSettings"
    static let sendEvent = "/api/v4.0/integrations/events"
    static let initializeCustomer = "/api/v4.0/integrations/customers"
}

enum SDKInfo {
    static let version = "3.0.0"
    static let platform = "iOS"

    static var userAgent: String {
        return "GB\\\(platform)\(version)"
    }
}

enum UserDefaultsKeys: String {
    case customerId = "gameballSDKCustomerID"
    case APIKey = "gameballSDKAPIKey"
    case LanguageKey = "languageKey"
    case globalPreferredLanguage = "gameballSDKGlobalPreferredLanguage"
    case customerPreferredLanguage = "gameballSDKCustomerPreferredLanguage"
}
