//
//  Item.swift
//  dockscan
//
//  Created by Giovanni D'Andrea on 17/12/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
