import Foundation
import OFTBShared

enum LobbyConnectionMode: String, Codable, CaseIterable, Equatable {
    case localP2P
    case onlineServer
}

/// Container for lobby-selected game settings. Supports Crazy Eights today, extend with more games later.
struct LobbyGameSettings: Codable, Hashable {
    var gameId: GameID = GameID.allCases.first ?? .crazyEights
    var crazyEights: CrazyEightsSettings = CrazyEightsSettings()
    var darts: DartsSettings = DartsSettings()
    var connectionMode: LobbyConnectionMode = .localP2P
    var onlineRoomCode: String?

    var activeSettingsData: Data? {
        switch gameId {
        case .crazyEights:
            return try? JSONEncoder().encode(crazyEights)
        case .darts:
            return try? JSONEncoder().encode(darts)
        }
    }

    init(gameId: GameID = .crazyEights) {
        self.gameId = gameId
        self.crazyEights = CrazyEightsSettings()
        self.darts = DartsSettings()
        self.connectionMode = .localP2P
        self.onlineRoomCode = nil
    }

    var summaryDescription: String {
        switch gameId {
        case .crazyEights:
            var parts: [String] = ["Hand \(crazyEights.startingHandCount)"]
            parts.append(crazyEights.allowStackDraws ? "Stack draws" : "No stack draws")
            parts.append(crazyEights.shotCallerEnabled ? "Shot Caller on" : "Shot Caller off")
            parts.append(crazyEights.bombEnabled ? "Bomb \(crazyEights.bombDrawCount)x" : "No bomb")
            if crazyEights.allowSevenZeroRule { parts.append("7-0 rule") }
            if crazyEights.fogEnabled { parts.append("Fog \(crazyEights.fogCardCount)x") }
            return parts.joined(separator: " · ")
        case .darts:
            return "\(darts.startingScore)"
        }
    }
}
