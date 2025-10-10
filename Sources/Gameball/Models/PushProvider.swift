//
//  PushProvider.swift
//  Gameball
//

import Foundation

/// Push service providers
public enum PushProvider: String, Codable {
    case firebase = "Firebase"
    case huawei = "Huawei"
}
