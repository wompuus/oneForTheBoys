import Foundation

public enum GameID: String, Codable, CaseIterable, Sendable {
    case crazyEights
    case darts
}

public extension GameID {
    var displayName: String {
        switch self {
        case .crazyEights: return "Crazy Eights"
        case .darts: return "Darts"
        }
    }
}

public struct GameCatalogEntry: Sendable {
    public let id: GameID
    public let displayName: String
    public let iconSymbol: String
    public let maxPlayers: Int
    public let difficultyLevel: String

    public init(id: GameID, displayName: String, iconSymbol: String, maxPlayers: Int, difficultyLevel: String) {
        self.id = id
        self.displayName = displayName
        self.iconSymbol = iconSymbol
        self.maxPlayers = maxPlayers
        self.difficultyLevel = difficultyLevel
    }
}

public struct GamePolicy: Sendable {
    public let minPlayers: Int
    public let maxPlayers: Int
    public let isTurnBased: Bool
    public let allowsRejoin: Bool
    public let supportsSpectators: Bool

    public init(minPlayers: Int, maxPlayers: Int, isTurnBased: Bool, allowsRejoin: Bool, supportsSpectators: Bool) {
        self.minPlayers = minPlayers
        self.maxPlayers = maxPlayers
        self.isTurnBased = isTurnBased
        self.allowsRejoin = allowsRejoin
        self.supportsSpectators = supportsSpectators
    }
}

public enum TransportMode: Sendable {
    case p2p
    case hybrid
}
