import Foundation
import SwiftUI

enum CrazyEightsAction: Codable {
    case startRound
    case updateSettings(CrazyEightsSettings)
    case intentDraw(playerId: UUID)
    case intentPlay(card: UNOCard, chosenColor: UNOColor?, targetId: UUID?)
    case callUno(playerId: UUID)
    case leave(playerId: UUID)
}

struct CrazyEightsGameModule: GameModule {
    static var id: GameID { .crazyEights }

    static var catalogEntry: GameCatalogEntry {
        GameCatalogEntry(
            id: id,
            displayName: "Crazy Eights",
            iconSymbol: "circle.grid.3x3.fill",
            maxPlayers: 8,
            difficultyLevel: "Easy"
        )
    }

    static var policy: GamePolicy {
        GamePolicy(
            minPlayers: 2,
            maxPlayers: 8,
            isTurnBased: true,
            allowsRejoin: false,
            supportsSpectators: false
        )
    }

    static var reducer: (CrazyEightsGameState, CrazyEightsAction, Bool) -> CrazyEightsGameState = { state, action, isHost in
        var state = state
        switch action {
        case .startRound:
            guard isHost else { break }
            state = ceDealNewRound(state: state)
        case .updateSettings(let newSettings):
            guard isHost else { break }
            state.config = newSettings
        case .intentDraw(let pid):
            guard isHost, state.started, state.winnerId == nil else { break }
            guard let currId = state.currentPlayerId,
                  let currIdx = state.players.firstIndex(where: { $0.id == currId }),
                  currId == pid else { break }

            if let target = state.shotCallerTargetId,
               target == currId,
               state.pendingDraw == 0 {
                let hand = state.players[currIdx].hand
                let hasPlayable = hand.contains { card in state.canPlay(card) }
                guard !hasPlayable else { break }
                ceDrawCard(state: &state, to: currIdx)
                break
            }

            let drawCount = max(1, state.pendingDraw)
            state.pendingDraw = 0
            for _ in 0..<drawCount { ceDrawCard(state: &state, to: currIdx) }
            ceAdvanceTurn(state: &state, skips: 0)
        case .intentPlay(let card, let chosen, let targetId):
            guard isHost, state.started, state.winnerId == nil else { break }
            guard let currId = state.currentPlayerId,
                  let currIdx = state.players.firstIndex(where: { $0.id == currId }),
                  let handIdx = state.players[currIdx].hand.firstIndex(of: card),
                  state.canPlay(card) else { break }

            if state.config.shotCallerEnabled,
               card.value == .wild,
               targetId == nil {
                break
            }

            state.players[currIdx].hand.remove(at: handIdx)
            state.discardPile.append(card)

            var skips = 0
            switch card.value {
            case .reverse:
                state.clockwise.toggle()
                if state.players.count == 2 { skips = 1 }
            case .skip:
                skips = 1
            case .draw2:
                state.pendingDraw += 2
            case .wild:
                state.chosenWildColor = chosen ?? .red
                if state.config.shotCallerEnabled { state.shotCallerTargetId = targetId }
            case .wildDraw4:
                state.pendingDraw += 4
                state.chosenWildColor = chosen ?? .red
                if state.config.shotCallerEnabled { state.shotCallerTargetId = targetId }
            case .number:
                break
            }

            if state.config.bombEnabled,
               let bomb = state.bombCardId,
               bomb == card.id {
                for i in state.players.indices where i != currIdx {
                    for _ in 0..<max(1, state.config.bombDrawCount) {
                        ceDrawCard(state: &state, to: i)
                    }
                }
                state.clockwise.toggle()
                skips += 1
                ceRandomizeBombCard(state: &state)
            }

            if state.players[currIdx].hand.isEmpty {
                state.winnerId = currId
                state.pendingDraw = 0
                state.unoCalled.removeAll()
                state.started = false
                break
            }

            let prevPlayerId = state.players[currIdx].id
            ceAdvanceTurn(state: &state, skips: skips)

            if state.shotCallerTargetId == prevPlayerId {
                state.shotCallerTargetId = nil
                state.chosenWildColor = nil
            }
        case .callUno(let pid):
            guard isHost, state.started, state.winnerId == nil else { break }
            state.unoCalled.insert(pid)
        case .leave(let pid):
            if isHost {
                guard let idx = state.players.firstIndex(where: { $0.id == pid }) else { break }
                state.players.remove(at: idx)
                if state.players.isEmpty {
                    state = CrazyEightsGameState()
                    break
                }
                ceAdjustTurnIndexAfterRemoval(state: &state, removedIndex: idx)
                if state.started && state.players.count == 1 {
                    state = ceDealNewRound(state: state)
                }
            } else if pid == state.hostId {
                state = CrazyEightsGameState()
            }
        }
        return state
    }

    static func initialState(players: [PlayerProfile], settings: CrazyEightsSettings) -> CrazyEightsGameState {
        var state = CrazyEightsGameState()
        state.hostId = players.first?.id
        state.players = players.map { profile in
            CrazyEightsPlayer(id: profile.id, name: profile.username, deviceName: "", hand: [])
        }
        state.config = settings
        return state
    }

    static func isGameOver(state: CrazyEightsGameState) -> Bool {
        state.winnerId != nil
    }

    @MainActor
    static func makeView(store: GameStore<CrazyEightsGameState, CrazyEightsAction>) -> AnyView {
        let localId = store.state.hostId ?? store.state.players.first?.id ?? UUID()
        return AnyView(CrazyEightsGameView(store: store, localPlayerId: localId))
    }

    @MainActor
    static func makeResultsView(state: CrazyEightsGameState, players: [PlayerProfile], localPlayerId: UUID) -> AnyView {
        AnyView(EmptyView())
    }

    @MainActor
    static func makeSettingsView(binding: Binding<CrazyEightsSettings>) -> AnyView {
        AnyView(EmptyView())
    }

    @MainActor
    static func makeRulesView() -> AnyView {
        AnyView(EmptyView())
    }

    static func defaultSettings() -> CrazyEightsSettings {
        CrazyEightsSettings()
    }
}
