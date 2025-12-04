import Foundation

public struct GlobalStats: Codable, Hashable, Sendable {
    public var totalGamesPlayed: Int
    public var totalWins: Int

    public init(totalGamesPlayed: Int, totalWins: Int) {
        self.totalGamesPlayed = totalGamesPlayed
        self.totalWins = totalWins
    }
}

public struct GameStats: Codable, Hashable, Sendable {
    public var gamesPlayed: Int
    public var wins: Int
    public var streakCurrent: Int
    public var streakBest: Int

    public init(gamesPlayed: Int, wins: Int, streakCurrent: Int, streakBest: Int) {
        self.gamesPlayed = gamesPlayed
        self.wins = wins
        self.streakCurrent = streakCurrent
        self.streakBest = streakBest
    }
}

public struct AvatarConfig: Codable, Hashable, Sendable {
    public var version: Int = 1 // Schema version for migration
    public var baseSymbol: String
    public var skinColorHex: String
    public var hairSymbol: String?
    public var hairColorHex: String
    public var accessorySymbol: String?
    public var backgroundColorHex: String

    public init(version: Int = 1,
                baseSymbol: String,
                skinColorHex: String,
                hairSymbol: String? = nil,
                hairColorHex: String,
                accessorySymbol: String? = nil,
                backgroundColorHex: String) {
        self.version = version
        self.baseSymbol = baseSymbol
        self.skinColorHex = skinColorHex
        self.hairSymbol = hairSymbol
        self.hairColorHex = hairColorHex
        self.accessorySymbol = accessorySymbol
        self.backgroundColorHex = backgroundColorHex
    }
}

public struct PlayerProfile: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var username: String
    public var avatar: AvatarConfig
    public var globalStats: GlobalStats
    public var statsByGameId: [GameID: GameStats]
    public var ownedProductIDs: Set<String>

    public init(id: UUID,
                username: String,
                avatar: AvatarConfig,
                globalStats: GlobalStats,
                statsByGameId: [GameID: GameStats],
                ownedProductIDs: Set<String>) {
        self.id = id
        self.username = username
        self.avatar = avatar
        self.globalStats = globalStats
        self.statsByGameId = statsByGameId
        self.ownedProductIDs = ownedProductIDs
    }
}
