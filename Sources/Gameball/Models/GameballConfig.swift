//
//  GameballConfig.swift
//  Gameball
//

import Foundation

/// SDK Configuration
public struct GameballConfig {
    public let apiKey: String
    public let lang: String
    public let platform: String?
    public let shop: String?
    public let apiPrefix: String?

    /// Initialize Gameball SDK configuration
    /// - Parameters:
    ///   - apiKey: Your Gameball API key
    ///   - lang: Language code (e.g., "en", "ar")
    ///   - platform: Platform identifier (optional)
    ///   - shop: Shop identifier (optional)
    ///   - apiPrefix: Custom API base URL (optional)
    public init(apiKey: String, lang: String, platform: String? = nil,
                shop: String? = nil, apiPrefix: String? = nil) {
        self.apiKey = apiKey
        self.lang = lang
        self.platform = platform
        self.shop = shop
        self.apiPrefix = apiPrefix
    }
}
