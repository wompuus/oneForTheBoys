//
//  Untitled.swift
//  oneForTheBoys
//
//  Created by Wyatt Nail on 11/18/25.
//

import Foundation

struct GameConfig: Codable, Equatable {
    
    
    // Basic flow
    var startingHandCount: Int = 7

    // Draw stacking
    var allowStackDraws: Bool = true
    var allowMixedDrawStacking: Bool = false   // +2 on +4 and +4 on +2

    // Draw & play (hook, not auto-used yet)
    var playAfterDrawIfPlayable: Bool = false

    // UNO penalty
//    var unoPenaltyEnabled: Bool = false
//    var unoPenaltyCards: Int = 10              // cards drawn if you fail to call UNO

    // Card distribution (0–50 per type)
    var skipPerColor: Int = 10
    var reversePerColor: Int = 10
    var draw2PerColor: Int = 10
    var wildCount: Int = 12
    var wildDraw4Count: Int = 12

    // Shot Caller UNO: Wild chooses color + target player
    var shotCallerEnabled: Bool = false

    // THE BOMB: hidden card that detonates
    var bombEnabled: Bool = false
    var bombDrawCount: Int = 15                // cards each opponent draws
    
    // Can players join in progress?
    var allowJoinInProgress: Bool = false
}
