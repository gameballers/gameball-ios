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
    public let sessionToken: String?

    /// The widget host to load, when it is not the production one.
    ///
    /// Applies to everything the SDK opens in a web view — the profile widget and any campaign a
    /// message opens. Set once here rather than per call: a host pointed at a non-production
    /// environment is pointed there for everything, and the two cannot silently disagree.
    ///
    /// `ShowProfileRequest.widgetUrlPrefix` still overrides this for one presentation.
    public let widgetUrlPrefix: String?

    /// Initialize Gameball SDK configuration
    /// - Parameters:
    ///   - apiKey: Your Gameball API key
    ///   - lang: Language code (e.g., "en", "ar")
    ///   - platform: Platform identifier (optional)
    ///   - shop: Shop identifier (optional)
    ///   - apiPrefix: Custom API base URL (optional)
    ///   - sessionToken: Session token for enhanced security (optional)
    public init(apiKey: String, lang: String, platform: String? = nil,
                shop: String? = nil, apiPrefix: String? = nil,
                sessionToken: String? = nil,
                widgetUrlPrefix: String? = nil) {
        self.apiKey = apiKey
        self.lang = lang
        self.platform = platform
        self.shop = shop
        self.apiPrefix = apiPrefix
        self.sessionToken = sessionToken
        self.widgetUrlPrefix = widgetUrlPrefix
    }
}
