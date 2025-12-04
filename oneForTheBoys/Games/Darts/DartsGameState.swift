import Foundation
import CoreGraphics
import OFTBShared

struct DartsGameState: Codable, Equatable {
    var players: [DartsPlayer] = []
    var hostId: UUID?
    var currentPlayerIndex: Int = 0
    var scores: [UUID: Int] = [:]
    var round: Int = 1
    var winnerId: UUID?
    var config: DartsSettings = DartsSettings()
    var turnHistory: [DartThrow] = []
    var lastHitText: String?
    var lastHitTimestamp: Date?
    var scoreStartOfTurn: Int?
    var currentThrowIndex: Int = 0 // kept for compatibility; mirrors dartsThisTurn
    var dartsThisTurn: Int = 0
    var playersCompletedThisCycle: Int = 0
    var cycleNumber: Int = 1
    var lastCycleThrows: [DartThrow] = []
    var cycleComplete: Bool = false
    var remoteFlights: [UUID: DartFlightSnapshot] = [:]
    var roundId: UUID = UUID()
    var resultCredited: Bool = false

    var currentPlayerId: UUID? {
        guard players.indices.contains(currentPlayerIndex) else { return nil }
        return players[currentPlayerIndex].id
    }
}

struct DartsPlayer: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var avatar: AvatarConfig?
}

struct GamePoint: Codable, Equatable {
    let x: CGFloat
    let y: CGFloat
}

struct DartThrow: Codable, Equatable, Identifiable {
    let id = UUID()
    let segment: DartBoardSegment
    let resultingScore: Int
    let location: GamePoint
}

struct DartFlightSnapshot: Codable, Equatable {
    let dartId: UUID
    let playerId: UUID
    let position: [Float] // [x,y,z]
    let orientation: [Float] // quaternion as [ix, iy, iz, r]
}
