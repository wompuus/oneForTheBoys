import Foundation

/// Container for lobby-selected game settings. Supports Crazy Eights today, extend with more games later.
struct LobbyGameSettings: Codable, Hashable {
    var gameId: GameID = GameID.allCases.first ?? .crazyEights
    var crazyEights: CrazyEightsSettings = CrazyEightsSettings()

    var activeSettingsData: Data? {
        switch gameId {
        case .crazyEights:
            return try? JSONEncoder().encode(crazyEights)
        }
    }

    init(gameId: GameID = .crazyEights) {
        self.gameId = gameId
        self.crazyEights = CrazyEightsSettings()
    }

    var summaryDescription: String {
        switch gameId {
        case .crazyEights:
            var parts: [String] = ["Hand \(crazyEights.startingHandCount)"]
            parts.append(crazyEights.allowStackDraws ? "Stack draws" : "No stack draws")
            parts.append(crazyEights.shotCallerEnabled ? "Shot Caller on" : "Shot Caller off")
            parts.append(crazyEights.bombEnabled ? "Bomb \(crazyEights.bombDrawCount)x" : "No bomb")
            return parts.joined(separator: " · ")
        }
    }
}
