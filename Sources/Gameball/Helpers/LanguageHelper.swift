//
//  LanguageHelper.swift
//  Gameball
//

import Foundation

/// Helper for resolving language preference with priority order
class LanguageHelper {

    private static let ltrLanguageCodes = [
        "en", "fr", "es", "de", "pt", "pl", "it", "hu", "zh-tw", "nl", "sv", "no", "dk", "ja"
    ]

    private static let rtlLanguageCodes = ["ar"]

    /// Resolves the language to use based on priority:
    /// 1. Explicit per-call override (e.g., passed to showProfile)
    /// 2. Customer preferred language (set via CustomerAttributes)
    /// 3. Global preferred language (set during SDK init)
    /// 4. Device locale (fallback)
    /// The first one set wins; an unsupported code resolves to "en".
    /// - Parameter override: Optional per-call language code.
    static func resolveLanguage(override: String? = nil) -> String {
        // Highest priority: explicit per-call override
        if let override = override, !override.isEmpty {
            return normalizeLanguage(override)
        }

        // First priority: Customer preferred language
        if let customerLanguage = UserDefaults.standard.string(forKey: UserDefaultsKeys.customerPreferredLanguage.rawValue),
           !customerLanguage.isEmpty {
            return normalizeLanguage(customerLanguage)
        }

        // Second priority: Global preferred language
        if let globalLanguage = UserDefaults.standard.string(forKey: UserDefaultsKeys.globalPreferredLanguage.rawValue),
           !globalLanguage.isEmpty {
            return normalizeLanguage(globalLanguage)
        }

        // Fallback: Device locale
        return normalizeLanguage(Locale.current.languageCode ?? "en")
    }

    /// Returns `languageCode` trimmed and lowercased if it's supported, otherwise "en".
    static func normalizeLanguage(_ languageCode: String) -> String {
        let code = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ltrLanguageCodes.contains(code) || rtlLanguageCodes.contains(code) ? code : "en"
    }

    /// Check if language code is RTL (Right-to-Left)
    static func isRTL(_ languageCode: String) -> Bool {
        return rtlLanguageCodes.contains(languageCode)
    }
}
