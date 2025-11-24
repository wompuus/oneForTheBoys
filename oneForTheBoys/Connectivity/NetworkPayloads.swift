import Foundation

struct LobbyInfo: Codable, Equatable {
    var id: String
    var gameId: GameID
    var hostProfile: PlayerProfile
    var playerProfiles: [PlayerProfile]
    var readyPlayerIDs: Set<UUID> = []
    var isPrivate: Bool = false
    var passcodeHash: String?
    var activeSettings: Data? // Snapshot of GameSettings
}

enum NetworkMessage: Codable {
    // Lobby Phase
    case lobbyUpdate(LobbyInfo)
    case joinRequest(profile: PlayerProfile, appVersion: String, passcodeHash: String?)
    case joinAccepted(LobbyInfo)
    case joinRejected(reason: String)
    case kickPlayer(playerId: UUID, reason: String?)

    // Game Phase
    case gameAction(gameId: GameID, payload: Data)
    case gameState(gameId: GameID, payload: Data)
}
