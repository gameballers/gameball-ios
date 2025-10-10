//
//  ClientBotStyle.swift
//  gameball_SDK
//
//  Created by Ahmed Abodeif on 2/12/19.
//  Copyright © 2019 Ahmed Abodeif. All rights reserved.
//

import Foundation

struct ClientBotStyle: Codable {
    let botMainColor: String?

    enum CodingKeys: String, CodingKey {
        case botMainColor = "botMainColor"
    }
}
