import Foundation
import OFTBShared

actor StatsTracker {
    static let shared = StatsTracker()

    private var creditedRounds: Set<UUID> = []
    private let profileStore = ProfileStore.shared

    func creditCrazyEights(state: CrazyEightsGameState, localPlayerId: UUID?) async {
        guard let localId = localPlayerId else { return }
        guard let winner = state.winnerId else { return }
        guard state.resultCredited else { return }
        guard creditedRounds.contains(state.roundId) == false else { return }

        creditedRounds.insert(state.roundId)

        var (profile, _) = await profileStore.loadProfile(defaultName: "Player")
        var stats = profile.statsByGameId[.crazyEights] ?? GameStats(gamesPlayed: 0, wins: 0, streakCurrent: 0, streakBest: 0)
        stats.gamesPlayed += 1
        profile.globalStats.totalGamesPlayed += 1

        if winner == localId {
            stats.wins += 1
            profile.globalStats.totalWins += 1
            stats.streakCurrent += 1
            stats.streakBest = max(stats.streakBest, stats.streakCurrent)
        } else {
            stats.streakCurrent = 0
        }

        profile.statsByGameId[.crazyEights] = stats
        await profileStore.save(profile)
    }

    func creditDarts(state: DartsGameState, localPlayerId: UUID?) async {
        guard let localId = localPlayerId else { return }
        guard let winner = state.winnerId else { return }
        guard state.resultCredited else { return }
        guard creditedRounds.contains(state.roundId) == false else { return }

        creditedRounds.insert(state.roundId)

        var (profile, _) = await profileStore.loadProfile(defaultName: "Player")
        var stats = profile.statsByGameId[.darts] ?? GameStats(gamesPlayed: 0, wins: 0, streakCurrent: 0, streakBest: 0)
        stats.gamesPlayed += 1
        profile.globalStats.totalGamesPlayed += 1

        if winner == localId {
            stats.wins += 1
            profile.globalStats.totalWins += 1
            stats.streakCurrent += 1
            stats.streakBest = max(stats.streakBest, stats.streakCurrent)
        } else {
            stats.streakCurrent = 0
        }

        profile.statsByGameId[.darts] = stats
        await profileStore.save(profile)
    }
}
