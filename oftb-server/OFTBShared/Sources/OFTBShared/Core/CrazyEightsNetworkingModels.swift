import Foundation

public struct PublicPlayerSnapshot: Codable, Equatable, Hashable {
    public let id: UUID
    public let displayName: String
    public let avatar: AvatarConfig?

    public init(id: UUID, displayName: String, avatar: AvatarConfig?) {
        self.id = id
        self.displayName = displayName
        self.avatar = avatar
    }
}

public struct CrazyEightsRoomSummary: Codable, Equatable, Hashable {
    public let roomCode: String
    public let hostName: String
    public let playerCount: Int
    public let isPublic: Bool

    public init(roomCode: String, hostName: String, playerCount: Int, isPublic: Bool) {
        self.roomCode = roomCode
        self.hostName = hostName
        self.playerCount = playerCount
        self.isPublic = isPublic
    }
}

public enum CrazyEightsClientMessage: Codable {
    case createRoom(roomCode: String, host: PublicPlayerSnapshot, isPublic: Bool)
    case joinRoom(roomCode: String, player: PublicPlayerSnapshot)
    case sendAction(roomCode: String, playerId: UUID, action: CrazyEightsAction)
    case requestRoomList
    case readyUpdate(roomCode: String, playerId: UUID, isReady: Bool)
}

public enum CrazyEightsServerMessage: Codable {
    case roomJoined(roomCode: String, players: [PublicPlayerSnapshot], state: CrazyEightsGameState)
    case stateUpdated(state: CrazyEightsGameState)
    case error(message: String)
    case roomList([CrazyEightsRoomSummary])
    case readySnapshot([UUID])
}
