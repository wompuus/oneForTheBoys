import Foundation
import SwiftUI
import OFTBShared
import CoreGraphics
import simd

enum DartsAction: Codable {
    case updateSettings(DartsSettings)
    case recordThrow(segment: DartBoardSegment, location: GamePoint)
    case dartFlightSpawn(dartId: UUID, playerId: UUID)
    case dartFlightUpdate(dartId: UUID, playerId: UUID, position: [Float], orientation: [Float])
    case dartFlightLanded(dartId: UUID, playerId: UUID, location: GamePoint)
    case startNextCycle
    case leave(playerId: UUID)
}

struct DartsGameModule: GameModule {
    private static let registerOnce: Void = {
        Task { @MainActor in
            GameRegistry.shared.register(DartsGameModule.self)
        }
    }()

    static var id: GameID {
        registerOnce
        return .darts
    }

    static var catalogEntry: GameCatalogEntry {
        GameCatalogEntry(
            id: id,
            displayName: "Darts",
            iconSymbol: "scope",
            maxPlayers: 4,
            difficultyLevel: "Medium"
        )
    }

    static var policy: GamePolicy {
        GamePolicy(
            minPlayers: 1,
            maxPlayers: 4,
            isTurnBased: true,
            allowsRejoin: false,
            supportsSpectators: false
        )
    }

    static var reducer: (DartsGameState, DartsAction, Bool) -> DartsGameState = { state, action, isHost in
        var state = state
        switch action {
        case .updateSettings(let newSettings):
            guard isHost else { break }
            state.config = newSettings
        case .dartFlightSpawn(let dartId, let playerId):
            state.remoteFlights[dartId] = DartFlightSnapshot(dartId: dartId, playerId: playerId, position: [0,0,0], orientation: [0,0,0,1])
        case .dartFlightUpdate(let dartId, let playerId, let position, let orientation):
            state.remoteFlights[dartId] = DartFlightSnapshot(dartId: dartId, playerId: playerId, position: position, orientation: orientation)
        case .dartFlightLanded(let dartId, _, let location):
            state.remoteFlights.removeValue(forKey: dartId)
            // Treat landing as an authoritative throw; compute segment from location and process normally.
            let segment = segmentForLocation(location)
            state = reducer(state, .recordThrow(segment: segment, location: location), isHost)
        case .startNextCycle:
            // Player confirmed next round: clear visible darts and resume play.
            state.turnHistory.removeAll()
            state.lastCycleThrows.removeAll()
            state.remoteFlights.removeAll()
            state.cycleComplete = false
            state.playersCompletedThisCycle = 0
            state.dartsThisTurn = 0
            state.currentThrowIndex = 0
            state.currentPlayerIndex = 0
            state.roundId = UUID()
            state.resultCredited = false
            state.winnerId = nil
            if let pid = state.currentPlayerId {
                state.scoreStartOfTurn = state.scores[pid] ?? state.config.startingScore
            } else {
                state.scoreStartOfTurn = nil
            }
        case .recordThrow(let segment, let location):
            guard isHost,
                  state.winnerId == nil,
                  let pid = state.currentPlayerId else { break }
            // Halt new throws until the next cycle is started.
            if state.cycleComplete { break }
            if state.scoreStartOfTurn == nil {
                state.scoreStartOfTurn = state.scores[pid] ?? state.config.startingScore
            }
            let startingScore = state.scoreStartOfTurn ?? state.config.startingScore
            let currentScore = state.scores[pid] ?? state.config.startingScore
            let throwValue = segment.scoreValue
            var newScore = currentScore - throwValue
            var bust = false
            var bustReason: String?
            var win = false

            // Bust conditions
            if state.config.doubleOutRequired {
                // Double-out: bust on <0 or ==1; must finish on a double.
                if newScore < 0 || newScore == 1 {
                    bust = true
                    bustReason = "BUST"
                } else if newScore == 0 {
                    win = segment.isDoubleOutHit
                    bust = !win
                    if bust { bustReason = "Need Double Out" }
                }
            } else {
                // Standard: bust only on negative; 1 is allowed.
                if newScore < 0 {
                    bust = true
                    bustReason = "BUST"
                } else if newScore == 0 {
                    win = true
                }
            }

            let dart = DartThrow(segment: segment, resultingScore: bust ? startingScore : newScore, location: location)
            state.turnHistory.append(dart)
            state.lastHitText = bust ? (bustReason ?? "BUST") : segment.displayText
            state.lastHitTimestamp = Date()
            state.dartsThisTurn += 1
            state.currentThrowIndex = state.dartsThisTurn

            if bust {
                state.scores[pid] = startingScore
                state.scoreStartOfTurn = nil
                endPlayerTurn(&state)
                break
            }

            state.scores[pid] = newScore

            if win {
                state.winnerId = pid
                state.cycleComplete = true
                state.resultCredited = true
            }

            if win || state.dartsThisTurn >= 3 {
                state.scoreStartOfTurn = nil
                endPlayerTurn(&state)
            }
        case .leave(let pid):
            if isHost {
                guard let idx = state.players.firstIndex(where: { $0.id == pid }) else { break }
                let removingCurrent = idx == state.currentPlayerIndex
                state.players.remove(at: idx)
                state.scores.removeValue(forKey: pid)
                // Drop any in-flight darts for the leaving player.
                state.remoteFlights = state.remoteFlights.filter { $0.value.playerId != pid }
                if removingCurrent {
                    state.dartsThisTurn = 0
                    state.currentThrowIndex = 0
                    state.scoreStartOfTurn = nil
                }
                if state.players.isEmpty {
                    state = DartsGameState()
                    break
                }
                // Adjust turn index after removal.
                if state.currentPlayerIndex >= state.players.count {
                    state.currentPlayerIndex = 0
                } else if removingCurrent {
                    state.currentPlayerIndex = state.currentPlayerIndex % state.players.count
                }
                state.playersCompletedThisCycle = min(state.playersCompletedThisCycle, state.players.count)
                if state.players.count == 1 {
                    state.winnerId = state.players.first?.id
                }
            }
        }
        return state
    }

    static func initialState(players: [PlayerProfile], settings: DartsSettings) -> DartsGameState {
        var state = DartsGameState()
        state.hostId = players.first?.id
        state.players = players.map { DartsPlayer(id: $0.id, name: $0.username, avatar: $0.avatar) }
        state.config = settings
        state.scores = Dictionary(uniqueKeysWithValues: players.map { ($0.id, settings.startingScore) })
        if let pid = state.currentPlayerId {
            state.scoreStartOfTurn = state.scores[pid]
        }
        return state
    }

    static func isGameOver(state: DartsGameState) -> Bool {
        state.winnerId != nil
    }

    @MainActor
    static func makeView(store: GameStore<DartsGameState, DartsAction>) -> AnyView {
        AnyView(DartsGameView(store: store))
    }

    @MainActor
    static func makeResultsView(state: DartsGameState, players: [PlayerProfile], localPlayerId: UUID) -> AnyView {
        AnyView(DartsResultsView(state: state, players: players, localPlayerId: localPlayerId))
    }

    @MainActor
    static func makeSettingsView(binding: Binding<DartsSettings>) -> AnyView {
        AnyView(DartsSettingsView(settings: binding))
    }

    static func leaveAction(for playerId: UUID) -> DartsAction? {
        .leave(playerId: playerId)
    }

    @MainActor
    static func makeRulesView() -> AnyView {
        AnyView(Text("Standard 301/501 style play."))
    }

    static func defaultSettings() -> DartsSettings {
        DartsSettings()
    }

    /// Ends the current player's turn and advances to the next player.
    /// When all players have taken a turn (3 darts each), a cycle is complete.
    private static func endPlayerTurn(_ state: inout DartsGameState) {
        guard !state.players.isEmpty else {
            state.currentPlayerIndex = 0
            state.dartsThisTurn = 0
            state.currentThrowIndex = 0
            return
        }

        state.playersCompletedThisCycle += 1

        // If a full cycle finished, capture the throws for summary and rotate back to player 0.
        if state.playersCompletedThisCycle >= state.players.count {
            state.cycleComplete = true
            state.lastCycleThrows = state.turnHistory
            state.playersCompletedThisCycle = 0
            state.cycleNumber += 1
            state.currentPlayerIndex = 0
        } else {
            state.currentPlayerIndex = (state.currentPlayerIndex + 1) % state.players.count
        }

        state.round += 1
        state.dartsThisTurn = 0
        state.currentThrowIndex = 0
        if let pid = state.currentPlayerId {
            state.scoreStartOfTurn = state.scores[pid] ?? state.config.startingScore
        } else {
            state.scoreStartOfTurn = nil
        }
    }
}

/// Map board-relative location (normalized radius) to a DartBoardSegment for non-local landings.
private func segmentForLocation(_ location: GamePoint) -> DartBoardSegment {
    let point = CGPoint(x: location.x, y: location.y)
    return calculateSegment(at: point, boardRadius: 1.0)
}
