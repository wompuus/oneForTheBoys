import Foundation
import SwiftUI

enum CrazyEightsAction: Codable {
    case startRound
    case updateSettings(CrazyEightsSettings)
    case intentDraw(playerId: UUID)
    case intentPlay(card: UNOCard, chosenColor: UNOColor?, targetId: UUID?)
    case callUno(playerId: UUID)
    case swapHand(targetId: UUID)
    case blindPlayRandom(playerId: UUID)
    case leave(playerId: UUID)
}

struct CrazyEightsGameModule: GameModule {
    private static let registerOnce: Void = {
        Task { @MainActor in
            GameRegistry.shared.register(CrazyEightsGameModule.self)
        }
    }()

    static var id: GameID {
        registerOnce
        return .crazyEights
    }

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
            if state.blindedPlayerId == currId, state.blindedTurnsRemaining > 0 {
                break
            }
            if state.pendingSwapPlayerId == currId {
                break
            }

            if let target = state.shotCallerTargetId,
               target == currId,
               state.pendingDraw == 0 {
                let hand = state.players[currIdx].hand
                let hasPlayable = hand.contains { card in state.canPlay(card) }
                guard !hasPlayable else { break }
                ceDrawCard(state: &state, to: currIdx)
                break
            }

            let pendingBefore = state.pendingDraw
            if state.pendingDraw > 0 { state.pendingDraw = max(0, state.pendingDraw - 1) }
            ceDrawCard(state: &state, to: currIdx)
            if pendingBefore == 0 {
                let prev = state.players[currIdx].id
                ceAdvanceTurn(state: &state, skips: 0)
                ceAdvanceBlindTimer(state: &state, finishedPlayerId: prev)
            } else if state.pendingDraw == 0 {
                let prev = state.players[currIdx].id
                ceAdvanceTurn(state: &state, skips: 0)
                ceAdvanceBlindTimer(state: &state, finishedPlayerId: prev)
            }
        case .intentPlay(let card, let chosen, let targetId):
            guard isHost, state.started, state.winnerId == nil else { break }
            guard let currId = state.currentPlayerId,
                  let currIdx = state.players.firstIndex(where: { $0.id == currId }),
                  let handIdx = state.players[currIdx].hand.firstIndex(of: card) else { break }
            let isBlinded = state.blindedPlayerId == currId && state.blindedTurnsRemaining > 0
            let playable = state.canPlay(card)
            if !playable && !isBlinded { break }
            if state.pendingSwapPlayerId == currId {
                break
            }

            var chosenColor = chosen
            var resolvedTarget = targetId

            if state.config.shotCallerEnabled,
               card.value == .wild,
               resolvedTarget == nil,
               !isBlinded {
                break
            }
            if case .fog = card.value,
               (resolvedTarget == nil || !state.config.fogEnabled || resolvedTarget == currId) {
                if isBlinded {
                    resolvedTarget = state.players.filter { $0.id != currId }.randomElement()?.id
                } else {
                    break
                }
            }
            if isBlinded {
                if chosenColor == nil {
                    chosenColor = UNOColor.allCases.filter { $0 != .wild }.randomElement() ?? .red
                }
                if state.config.shotCallerEnabled,
                   card.value == .wild,
                   resolvedTarget == nil {
                    resolvedTarget = state.players.filter { $0.id != currId }.randomElement()?.id
                }
            }

            if case .fog = card.value,
               resolvedTarget == nil {
                if isBlinded {
                    ceDrawCard(state: &state, to: currIdx)
                    let prevId = state.players[currIdx].id
                    ceAdvanceTurn(state: &state, skips: 0)
                    ceAdvanceBlindTimer(state: &state, finishedPlayerId: prevId)
                }
                break
            }

            // If still no target for required cases, bail.
            if state.config.shotCallerEnabled,
               card.value == .wild,
               resolvedTarget == nil {
                break
            }
            if case .fog = card.value,
               (resolvedTarget == nil || resolvedTarget == currId) {
                break
            }

            state.pendingSwapPlayerId = nil

            if isBlinded && !playable {
                if state.pendingDraw > 0 {
                    let drawCount = state.pendingDraw
                    state.pendingDraw = 0
                    for _ in 0..<drawCount {
                        ceDrawCard(state: &state, to: currIdx)
                    }
                } else {
                    ceDrawCard(state: &state, to: currIdx)
                }
                let prevId = state.players[currIdx].id
                ceAdvanceTurn(state: &state, skips: 0)
                ceAdvanceBlindTimer(state: &state, finishedPlayerId: prevId)
                break
            }

            state.players[currIdx].hand.remove(at: handIdx)
            state.discardPile.append(card)

            var skips = 0
            var requiresSwap = false
            switch card.value {
            case .reverse:
                state.clockwise.toggle()
                if state.players.count == 2 { skips = 1 }
            case .skip:
                skips = 1
            case .draw2:
                state.pendingDraw += 2
            case .wild:
                state.chosenWildColor = chosenColor ?? .red
                if state.config.shotCallerEnabled, let target = resolvedTarget {
                    addShotCallerDemand(targetId: target, color: state.chosenWildColor ?? .red, state: &state)
                }
            case .wildDraw4:
                state.pendingDraw += 4
                state.chosenWildColor = chosenColor ?? .red
                if state.config.shotCallerEnabled, let target = resolvedTarget {
                    addShotCallerDemand(targetId: target, color: state.chosenWildColor ?? .red, state: &state)
                }
            case .number(let n):
                if state.config.allowSevenZeroRule {
                    if n == 0 {
                        ceRotateHands(state: &state)
                    } else if n == 7, state.players.count > 1 {
                        if isBlinded {
                            if let target = state.players.filter({ $0.id != currId }).randomElement(),
                               let targetIdx = state.players.firstIndex(where: { $0.id == target.id }) {
                                let currHand = state.players[currIdx].hand
                                let targetHand = state.players[targetIdx].hand
                                state.players[currIdx].hand = targetHand
                                state.players[targetIdx].hand = currHand
                                if state.players[currIdx].hand.isEmpty {
                                    state.winnerId = currId
                                    state.resultCredited = true
                                    state.pendingDraw = 0
                                    state.unoCalled.removeAll()
                                    state.started = false
                                    break
                                }
                                if state.players[targetIdx].hand.isEmpty {
                                    state.winnerId = state.players[targetIdx].id
                                    state.resultCredited = true
                                    state.pendingDraw = 0
                                    state.unoCalled.removeAll()
                                    state.started = false
                                    break
                                }
                            }
                        } else {
                            requiresSwap = true
                            state.pendingSwapPlayerId = currId
                        }
                    }
                }
            case .fog:
                if state.config.fogEnabled, let targetId = resolvedTarget {
                    if state.blindedPlayerId == targetId {
                        state.blindedTurnsRemaining += max(1, state.config.fogBlindTurns)
                    } else {
                        state.blindedPlayerId = targetId
                        state.blindedTurnsRemaining = max(1, state.config.fogBlindTurns)
                    }
                    let randomColor = UNOColor.allCases.filter { $0 != .wild }.randomElement() ?? .red
                    state.chosenWildColor = randomColor
                }
            }

            if ceIsBombCard(card, state: state) {
                for i in state.players.indices where i != currIdx {
                    for _ in 0..<max(1, state.config.bombDrawCount) {
                        ceDrawCard(state: &state, to: i)
                    }
                }
                let victims = state.players.enumerated().compactMap { idx, p in
                    idx == currIdx ? nil : p.id
                }
                state.bombEvent = CrazyEightsGameState.BombEvent(
                    triggerId: state.players[currIdx].id,
                    victimIds: victims,
                    cardId: card.id
                )
                state.clockwise.toggle()
                skips += 1
                ceRandomizeBombCard(state: &state)
            }

            if !requiresSwap, state.players[currIdx].hand.isEmpty {
                state.winnerId = currId
                state.resultCredited = true
                state.pendingDraw = 0
                state.unoCalled.removeAll()
                state.started = false
                break
            }

            let prevPlayerId = state.players[currIdx].id
            if !requiresSwap {
                ceAdvanceTurn(state: &state, skips: skips)
                ceAdvanceBlindTimer(state: &state, finishedPlayerId: prevPlayerId)

                consumeShotCallerDemand(for: prevPlayerId, state: &state)
            }
        case .callUno(let pid):
            guard isHost, state.started, state.winnerId == nil else { break }
            state.unoCalled.insert(pid)
        case .blindPlayRandom(let pid):
            guard isHost,
                  state.started,
                  state.winnerId == nil,
                  state.blindedPlayerId == pid,
                  state.blindedTurnsRemaining > 0 else { break }
            guard let currId = state.currentPlayerId,
                  currId == pid,
                  let currIdx = state.players.firstIndex(where: { $0.id == currId }) else { break }

            let hand = state.players[currIdx].hand
            guard !hand.isEmpty else {
                ceDrawCard(state: &state, to: currIdx)
                let prev = state.players[currIdx].id
                ceAdvanceTurn(state: &state, skips: 0)
                ceAdvanceBlindTimer(state: &state, finishedPlayerId: prev)
                break
            }

            let randomIndex = Int.random(in: 0..<hand.count)
            let candidate = hand[randomIndex]
            if state.canPlay(candidate) {
                state.players[currIdx].hand.remove(at: randomIndex)
                state.discardPile.append(candidate)

                var skips = 0
                var targetIdxForSwap: Int?
                let requiresSwap = false

                switch candidate.value {
                case .reverse:
                    state.clockwise.toggle()
                    if state.players.count == 2 { skips = 1 }
                case .skip:
                    skips = 1
                case .draw2:
                    state.pendingDraw += 2
                case .wild:
                    state.chosenWildColor = UNOColor.allCases.filter { $0 != .wild }.randomElement() ?? .red
                    if state.config.shotCallerEnabled {
                        let others = state.players.filter { $0.id != currId }
                        state.shotCallerTargetId = others.randomElement()?.id
                    }
                case .wildDraw4:
                    state.pendingDraw += 4
                    state.chosenWildColor = UNOColor.allCases.filter { $0 != .wild }.randomElement() ?? .red
                    if state.config.shotCallerEnabled {
                        let others = state.players.filter { $0.id != currId }
                        state.shotCallerTargetId = others.randomElement()?.id
                    }
                case .number(let n):
                    if state.config.allowSevenZeroRule {
                        if n == 0 {
                            ceRotateHands(state: &state)
                        } else if n == 7, state.players.count > 1 {
                            if let target = state.players.filter({ $0.id != currId }).randomElement(),
                               let targetIdx = state.players.firstIndex(where: { $0.id == target.id }) {
                                let currHand = state.players[currIdx].hand
                                let targetHand = state.players[targetIdx].hand
                                state.players[currIdx].hand = targetHand
                                state.players[targetIdx].hand = currHand
                                targetIdxForSwap = targetIdx
                            }
                        }
                    }
                case .fog:
                    if state.config.fogEnabled {
                        let target = state.players.filter { $0.id != currId }.randomElement()
                        if let tid = target?.id {
                            if state.blindedPlayerId == tid {
                                state.blindedTurnsRemaining += max(1, state.config.fogBlindTurns)
                            } else {
                                state.blindedPlayerId = tid
                                state.blindedTurnsRemaining = max(1, state.config.fogBlindTurns)
                            }
                        }
                        let randomColor = UNOColor.allCases.filter { $0 != .wild }.randomElement() ?? .red
                        state.chosenWildColor = randomColor
                    }
                }

                if ceIsBombCard(candidate, state: state) {
                    for i in state.players.indices where i != currIdx {
                        for _ in 0..<max(1, state.config.bombDrawCount) {
                            ceDrawCard(state: &state, to: i)
                        }
                    }
                    let victims = state.players.enumerated().compactMap { idx, p in
                        idx == currIdx ? nil : p.id
                    }
                    state.bombEvent = CrazyEightsGameState.BombEvent(
                        triggerId: state.players[currIdx].id,
                        victimIds: victims,
                        cardId: candidate.id
                    )
                    state.clockwise.toggle()
                    skips += 1
                    ceRandomizeBombCard(state: &state)
                }

                if !requiresSwap, state.players[currIdx].hand.isEmpty {
                    state.winnerId = currId
                    state.resultCredited = true
                    state.pendingDraw = 0
                    state.unoCalled.removeAll()
                    state.started = false
                    break
                }
                if let tIdx = targetIdxForSwap,
                   state.players.indices.contains(tIdx),
                   state.players[tIdx].hand.isEmpty {
                    state.winnerId = state.players[tIdx].id
                    state.resultCredited = true
                    state.pendingDraw = 0
                    state.unoCalled.removeAll()
                    state.started = false
                    break
                }

                let prevPlayerId = state.players[currIdx].id
                if !requiresSwap {
                    ceAdvanceTurn(state: &state, skips: skips)
                    ceAdvanceBlindTimer(state: &state, finishedPlayerId: prevPlayerId)

                    consumeShotCallerDemand(for: prevPlayerId, state: &state)
                }
            } else {
                ceDrawCard(state: &state, to: currIdx)
                let prevPlayerId = state.players[currIdx].id
                ceAdvanceTurn(state: &state, skips: 0)
                ceAdvanceBlindTimer(state: &state, finishedPlayerId: prevPlayerId)
            }
        case .swapHand(let targetId):
            guard isHost,
                  state.started,
                  state.winnerId == nil,
                  state.config.allowSevenZeroRule else { break }
            guard let currId = state.currentPlayerId,
                  let currIdx = state.players.firstIndex(where: { $0.id == currId }),
                  let targetIdx = state.players.firstIndex(where: { $0.id == targetId }),
                  currIdx != targetIdx else { break }
            guard state.pendingSwapPlayerId == currId else { break }
            guard let top = state.discardPile.last,
                  case .number(7) = top.value else { break }

            let currHand = state.players[currIdx].hand
            let targetHand = state.players[targetIdx].hand
            state.players[currIdx].hand = targetHand
            state.players[targetIdx].hand = currHand
            state.pendingSwapPlayerId = nil

            if state.players[currIdx].hand.isEmpty {
                state.winnerId = currId
                state.resultCredited = true
                state.pendingDraw = 0
                state.unoCalled.removeAll()
                state.started = false
                break
            }
            if state.players[targetIdx].hand.isEmpty {
                state.winnerId = state.players[targetIdx].id
                state.resultCredited = true
                state.pendingDraw = 0
                state.unoCalled.removeAll()
                state.started = false
                break
            }

            let prevPlayerId = state.players[currIdx].id
            ceAdvanceTurn(state: &state, skips: 0)
            ceAdvanceBlindTimer(state: &state, finishedPlayerId: prevPlayerId)
            consumeShotCallerDemand(for: prevPlayerId, state: &state)
        case .leave(let pid):
            if isHost {
                guard let idx = state.players.firstIndex(where: { $0.id == pid }) else { break }
                state.players.remove(at: idx)
                if state.blindedPlayerId == pid {
                    state.blindedPlayerId = nil
                    state.blindedTurnsRemaining = 0
                }
                if state.pendingSwapPlayerId == pid {
                    state.pendingSwapPlayerId = nil
                }
                state.shotCallerDemands.removeValue(forKey: pid)
                if state.shotCallerTargetId == pid {
                    state.shotCallerTargetId = state.shotCallerDemands.keys.first
                }
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

    private static func addShotCallerDemand(targetId: UUID, color: UNOColor, state: inout CrazyEightsGameState) {
        var demands = state.shotCallerDemands[targetId] ?? []
        demands.append(color)
        state.shotCallerDemands[targetId] = demands
        if state.shotCallerTargetId == nil {
            state.shotCallerTargetId = targetId
        } else if let current = state.shotCallerTargetId,
                  state.shotCallerDemands[current] == nil {
            state.shotCallerTargetId = state.shotCallerDemands.keys.first
        }
    }

    private static func consumeShotCallerDemand(for playerId: UUID, state: inout CrazyEightsGameState) {
        guard var demands = state.shotCallerDemands[playerId], !demands.isEmpty else { return }
        demands.removeFirst()
        if demands.isEmpty {
            state.shotCallerDemands.removeValue(forKey: playerId)
        } else {
            state.shotCallerDemands[playerId] = demands
        }
        if let current = state.shotCallerTargetId, current == playerId {
            state.shotCallerTargetId = state.shotCallerDemands.keys.first
        } else if state.shotCallerTargetId == nil {
            state.shotCallerTargetId = state.shotCallerDemands.keys.first
        }
    }

    static func initialState(players: [PlayerProfile], settings: CrazyEightsSettings) -> CrazyEightsGameState {
        var state = CrazyEightsGameState()
        state.hostId = players.first?.id
        state.players = players.map { profile in
            CrazyEightsPlayer(id: profile.id, name: profile.username, deviceName: "", hand: [], avatar: profile.avatar)
        }
        state.config = settings
        return state
    }

    static func isGameOver(state: CrazyEightsGameState) -> Bool {
        state.winnerId != nil
    }

    @MainActor
    static func makeView(store: GameStore<CrazyEightsGameState, CrazyEightsAction>) -> AnyView {
        let localId = store.localPlayerId ?? store.state.hostId ?? store.state.players.first?.id ?? UUID()
        return AnyView(CrazyEightsGameView(store: store, localPlayerId: localId))
    }

    @MainActor
    static func makeResultsView(state: CrazyEightsGameState, players: [PlayerProfile], localPlayerId: UUID) -> AnyView {
        AnyView(EmptyView())
    }

    @MainActor
    static func makeSettingsView(binding: Binding<CrazyEightsSettings>) -> AnyView {
        AnyView(CrazyEightsSettingsView(settings: binding))
    }

    @MainActor
    static func makeRulesView() -> AnyView {
        AnyView(EmptyView())
    }

    static func defaultSettings() -> CrazyEightsSettings {
        CrazyEightsSettings()
    }

    static func leaveAction(for playerId: UUID) -> CrazyEightsAction? {
        .leave(playerId: playerId)
    }
}
