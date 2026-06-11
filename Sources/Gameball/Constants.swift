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

    static let api_v4_0 = "/api/v4.0/integrations"
    static let api_v4_1 = "/api/v4.1/integrations"

    static let getBotStyle = "/api/v1.0/Bots/BotSettings"
    static let sendEvent = "/events"
    static let initializeCustomer = "/customers"
    static let mobileLogs = "/api/v4.0/integrations/mobile/logs"
}

enum SDKInfo {
    static let version = "3.2.0"
    static let platform = "iOS"

    static var userAgent: String {
        return "GB/ios/\(version)"
    }
}

enum UserDefaultsKeys: String {
    case customerId = "gameballSDKCustomerID"
    case APIKey = "gameballSDKAPIKey"
    case LanguageKey = "languageKey"
    case globalPreferredLanguage = "gameballSDKGlobalPreferredLanguage"
    case customerPreferredLanguage = "gameballSDKCustomerPreferredLanguage"
    case installId = "gameballSDKInstallId"
}
