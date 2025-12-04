import Foundation

public struct CrazyEightsSettings: Codable, Hashable, Sendable {
    public var settingsVersion: Int = 1

    public var startingHandCount: Int = 7

    // Draw stacking
    public var allowStackDraws: Bool = true
    public var allowMixedDrawStacking: Bool = false

    // Draw & play
    public var playAfterDrawIfPlayable: Bool = false

    // Fog of War
    public var fogEnabled: Bool = false
    public var fogCardCount: Int = 4
    public var fogBlindTurns: Int = 1

    // Card distribution (0–50 per type)
    public var skipPerColor: Int = 10
    public var reversePerColor: Int = 10
    public var draw2PerColor: Int = 10
    public var wildCount: Int = 12
    public var wildDraw4Count: Int = 12

    // Shot Caller UNO: Wild chooses color + target player
    public var shotCallerEnabled: Bool = false

    // THE BOMB: hidden card that detonates
    public var bombEnabled: Bool = false
    public var bombDrawCount: Int = 15
    public var debugAllNumbersAreBombs: Bool = false

    // House rules
    public var allowSevenZeroRule: Bool = false

    // Can players join in progress?
    public var allowJoinInProgress: Bool = false

    public init() {}
}
