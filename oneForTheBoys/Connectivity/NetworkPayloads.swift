import Foundation
import OFTBShared

struct LobbyInfo: Codable, Equatable {
    var id: String
    var gameId: GameID
    var hostProfile: PlayerProfile
    var playerProfiles: [PlayerProfile]
    var readyPlayerIDs: Set<UUID> = []
    var isPrivate: Bool = false
    var passcodeHash: String?
    var activeSettings: Data? // Snapshot of GameSettings
    var isStarting: Bool? // optional for forward compatibility
}

enum NetworkMessage: Codable {
    // Lobby Phase
    case lobbyUpdate(LobbyInfo)
    case joinRequest(profile: PlayerProfile, appVersion: String, passcodeHash: String?)
    case joinAccepted(LobbyInfo)
    case joinRejected(reason: String)
    case kickPlayer(playerId: UUID, reason: String?)
    case leaveLobby(playerId: UUID)
    case playerReady(playerId: UUID, isReady: Bool)

    // Game Phase (generic)
    case gameAction(gameId: GameID, payload: Data)
    case gameState(gameId: GameID, payload: Data)
    case gameStateRequest(gameId: GameID)
    case hostLeft(gameId: GameID, reason: String)

    // Crazy Eights typed messages
    case crazyEightsClient(CrazyEightsClientMessage)
    case crazyEightsServer(CrazyEightsServerMessage)
}

extension NetworkMessage {
    var kindDescription: String {
        switch self {
        case .lobbyUpdate: return "lobbyUpdate"
        case .joinRequest: return "joinRequest"
        case .joinAccepted: return "joinAccepted"
        case .joinRejected: return "joinRejected"
        case .kickPlayer: return "kickPlayer"
        case .leaveLobby: return "leaveLobby"
        case .playerReady: return "playerReady"
        case .gameAction(let gameId, _): return "gameAction(\(gameId.rawValue))"
        case .gameState(let gameId, _): return "gameState(\(gameId.rawValue))"
        case .gameStateRequest(let gameId): return "gameStateRequest(\(gameId.rawValue))"
        case .hostLeft(let gameId, _): return "hostLeft(\(gameId.rawValue))"
        case .crazyEightsClient: return "crazyEightsClient"
        case .crazyEightsServer: return "crazyEightsServer"
        }
    }
}
