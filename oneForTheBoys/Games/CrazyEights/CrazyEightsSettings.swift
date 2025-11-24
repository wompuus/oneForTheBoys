import Foundation

struct CrazyEightsSettings: Codable, Hashable {
    var settingsVersion: Int = 1

    var startingHandCount: Int = 7

    // Draw stacking
    var allowStackDraws: Bool = true
    var allowMixedDrawStacking: Bool = false

    // Draw & play
    var playAfterDrawIfPlayable: Bool = false

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
    var bombDrawCount: Int = 15

    // Can players join in progress?
    var allowJoinInProgress: Bool = false
}
