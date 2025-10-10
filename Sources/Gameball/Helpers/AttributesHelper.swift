//
//  AttributesHelper.swift
//  Gameball
//

import Foundation

/// Helper for mapping CustomerAttributes to request parameters
class AttributesHelper {

    /// Maps CustomerAttributes to a dictionary for API requests
    /// - Standard attributes are encoded via Codable
    /// - customAttributes are nested under "custom" key
    /// - additionalAttributes are merged at root level
    static func mapToRequestParams(_ attributes: CustomerAttributes) -> [String: Any] {
        var params: [String: Any] = [:]

        // Encode standard attributes using Codable
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(attributes),
           let jsonObject = try? JSONSerialization.jsonObject(with: data),
           let standardAttributes = jsonObject as? [String: Any] {
            params = standardAttributes
        }

        // Merge additionalAttributes at root level
        if let additionalAttributes = attributes.additionalAttributes {
            for (key, value) in additionalAttributes {
                params[key] = value
            }
        }

        return params
    }
}
