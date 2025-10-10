//
//  InitializeCustomerResponse.swift
//  Gameball
//

import Foundation

/// Customer initialization response
public struct InitializeCustomerResponse: Codable {
    public let gameballId: String?

    enum CodingKeys: String, CodingKey {
            case gameballId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let intValue = try? container.decode(Int.self, forKey: .gameballId) {
                gameballId = String(intValue)
            } else {
                gameballId = try? container.decode(String.self, forKey: .gameballId)
            }
        }
    
    public init(gameballId: String?) {
        self.gameballId = gameballId
    }
}