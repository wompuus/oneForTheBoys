import Foundation

struct GlobalStats: Codable, Hashable {
    var totalGamesPlayed: Int
    var totalWins: Int
}

struct GameStats: Codable, Hashable {
    var gamesPlayed: Int
    var wins: Int
    var streakCurrent: Int
    var streakBest: Int
}

struct AvatarConfig: Codable, Hashable {
    var version: Int = 1 // Schema version for migration
    var baseSymbol: String
    var skinColorHex: String
    var hairSymbol: String?
    var hairColorHex: String
    var accessorySymbol: String?
    var backgroundColorHex: String
}

struct PlayerProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var username: String
    var avatar: AvatarConfig
    var globalStats: GlobalStats
    var statsByGameId: [GameID: GameStats]
    var ownedProductIDs: Set<String>
}
