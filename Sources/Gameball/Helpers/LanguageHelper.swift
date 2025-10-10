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
    /// 1. Customer preferred language (set via CustomerAttributes)
    /// 2. Global preferred language (set during SDK init)
    /// 3. Device locale (fallback)
    static func resolveLanguage() -> String {
        // First priority: Customer preferred language
        if let customerLanguage = UserDefaults.standard.string(forKey: UserDefaultsKeys.customerPreferredLanguage.rawValue),
           !customerLanguage.isEmpty,
           customerLanguage.count == 2 {
            return customerLanguage
        }

        // Second priority: Global preferred language
        if let globalLanguage = UserDefaults.standard.string(forKey: UserDefaultsKeys.globalPreferredLanguage.rawValue),
           !globalLanguage.isEmpty,
           globalLanguage.count == 2 {
            return globalLanguage
        }

        // Fallback: Device locale
        return Locale.current.languageCode ?? "en"
    }

    /// Determines if close button direction should be handled differently
    /// Returns true when there's a mismatch between device locale and selected language RTL/LTR
    static func shouldHandleCloseButtonDirection(selectedLanguage: String) -> Bool {
        let deviceLocale = Locale.current.languageCode ?? "en"
        return (isRTL(deviceLocale) && isLTR(selectedLanguage)) ||
               (isRTL(selectedLanguage) && isLTR(deviceLocale))
    }

    /// Check if language code is LTR (Left-to-Right)
    static func isLTR(_ languageCode: String) -> Bool {
        return ltrLanguageCodes.contains(languageCode)
    }

    /// Check if language code is RTL (Right-to-Left)
    static func isRTL(_ languageCode: String) -> Bool {
        return rtlLanguageCodes.contains(languageCode)
    }
}
