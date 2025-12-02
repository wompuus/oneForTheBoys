import Foundation

func ceDealNewRound(state: CrazyEightsGameState) -> CrazyEightsGameState {
    var state = state
    state.winnerId = nil
    state.resultCredited = false
    state.roundId = UUID()
    state.turnIndex = 0
    state.clockwise = true
    state.pendingDraw = 0
    state.chosenWildColor = nil
    state.shotCallerTargetId = nil
    state.shotCallerDemands.removeAll()
    state.bombEvent = nil
    state.blindedPlayerId = nil
    state.blindedTurnsRemaining = 0
    state.pendingSwapPlayerId = nil
    state.unoCalled.removeAll()
    state.started = true

    var deck = DeckBuilder.deck(with: state.config)
    for idx in state.players.indices { state.players[idx].hand.removeAll() }

    var startCard: UNOCard?
    repeat {
        startCard = deck.isEmpty ? nil : deck.removeFirst()
    } while startCard?.color == .wild

    if let startCard {
        state.discardPile = [startCard]
    } else {
        state.discardPile = []
    }
    state.drawPile = deck

    for _ in 0..<max(1, state.config.startingHandCount) {
        for i in state.players.indices {
            ceDrawCard(state: &state, to: i)
        }
    }

    ceRandomizeBombCard(state: &state)
    return state
}

func ceDrawCard(state: inout CrazyEightsGameState, to index: Int) {
    if state.drawPile.isEmpty {
        ceReshuffleFromDiscard(state: &state)
    }
    if let c = state.drawPile.popLast() {
        state.players[index].hand.append(c)
    }
}

func ceReshuffleFromDiscard(state: inout CrazyEightsGameState) {
    guard state.discardPile.count > 1 else { return }
    let top = state.discardPile.removeLast()
    var pool = state.discardPile
    pool.shuffle()
    state.drawPile = pool
    state.discardPile = [top]
}

func ceRandomizeBombCard(state: inout CrazyEightsGameState) {
    guard state.config.bombEnabled else {
        state.bombCardId = nil
        return
    }
    var pool: [UNOCard] = state.drawPile
    for p in state.players { pool.append(contentsOf: p.hand) }
    pool.append(contentsOf: state.discardPile)
    state.bombCardId = pool.randomElement()?.id
}

func ceIsBombCard(_ card: UNOCard, state: CrazyEightsGameState) -> Bool {
    guard state.config.bombEnabled else { return false }
    let isNumberCard: Bool
    if case .number = card.value {
        isNumberCard = true
    } else {
        isNumberCard = false
    }

    if state.config.debugAllNumbersAreBombs && isNumberCard {
        return true
    }

    guard let bomb = state.bombCardId else { return false }
    return bomb == card.id
}

func ceRotateHands(state: inout CrazyEightsGameState) {
    guard state.players.count > 1 else { return }
    let hands = state.players.map { $0.hand }
    for idx in state.players.indices {
        let from = (idx + 1) % state.players.count
        state.players[idx].hand = hands[from]
    }
}

func ceAdvanceBlindTimer(state: inout CrazyEightsGameState, finishedPlayerId: UUID?) {
    guard let pid = state.blindedPlayerId,
          pid == finishedPlayerId else { return }
    state.blindedTurnsRemaining = max(0, state.blindedTurnsRemaining - 1)
    if state.blindedTurnsRemaining == 0 {
        state.blindedPlayerId = nil
    }
}

func ceAdvanceTurn(state: inout CrazyEightsGameState, skips: Int) {
    let count = state.players.count
    guard count > 0 else { return }
    var steps = 1 + skips
    if !state.clockwise { steps = -steps }
    state.turnIndex = (state.turnIndex + steps % count + count) % count
}

func ceAdjustTurnIndexAfterRemoval(state: inout CrazyEightsGameState, removedIndex: Int) {
    guard !state.players.isEmpty else {
        state.turnIndex = 0
        return
    }
    if removedIndex < state.turnIndex {
        state.turnIndex -= 1
    }
    if state.turnIndex >= state.players.count {
        state.turnIndex = 0
    }
}
