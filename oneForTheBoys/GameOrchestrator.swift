import Foundation
import SwiftUI

@MainActor
final class GameOrchestrator: ObservableObject {
    @Published private(set) var state = GameState()
    @Published var myId = UUID()

    let mpc: MPCService

    /// Host-side guard to prevent multiple overlapping draw resolutions.
    private var drawInProgress = false

    init(mpc: MPCService) {
        self.mpc = mpc
        self.mpc.onEvent = { [weak self] event in
            self?.handle(event)
        }
        self.mpc.onPeerDisconnected = { [weak self] peerID in
            self?.handlePeerDisconnected(displayName: peerID.displayName)
        }
    }

    // MARK: Reset

    func reset() {
        state = GameState()
        myId = UUID()
        drawInProgress = false
    }

    // MARK: Setup (Lobby)

    /// Host creates table + config, but does NOT start the game.
    func configureAsHost(displayName: String, config: GameConfig) {
        state = GameState()
        state.hostId = myId
        state.config = config
        state.players = [
            Player(
                id: myId,
                name: displayName,
                deviceName: mpc.localPeerDisplayName,
                hand: [])]
        state.started = false

        // Let joiners know rules
        mpc.broadcast(.start(config: config))
        syncAll()
    }

    /// Client announces itself to the host.
    func joinAsClient(displayName: String) {
        mpc.broadcast(
            .hello(
                peerId: myId,
                name: displayName,
                deviceName: mpc.localPeerDisplayName))
    }

    /// Host presses “Start Game”.
    func hostStartGame() {
        guard state.hostId == myId else { return }
        dealNewRound()
        syncAll()
    }

    // MARK: Deal Round

    func dealNewRound() {
        state.winnerId = nil    // clear previous round winner, if any
        var deck = DeckBuilder.deck(with: state.config)

        // Empty hands
        for i in state.players.indices {
            state.players[i].hand.removeAll()
        }

        // Start card (non-wild)
        var startCard: UNOCard!
        repeat {
            startCard = deck.removeFirst()
        } while startCard.color == .wild

        state.discardPile = [startCard]
        state.drawPile = deck

        // Deal cards
        for _ in 0..<max(1, state.config.startingHandCount) {
            for i in state.players.indices {
                drawCard(to: i)
            }
        }

        state.turnIndex = 0
        state.clockwise = true
        state.pendingDraw = 0
        state.chosenWildColor = nil
        state.shotCallerTargetId = nil
        state.unoCalled.removeAll()
        state.started = true
        drawInProgress = false

        randomizeBombCard()
    }

    private func drawCard(to index: Int) {
        if state.drawPile.isEmpty {
            reshuffleFromDiscard()
        }
        if let c = state.drawPile.popLast() {
            state.players[index].hand.append(c)
        }
    }

    private func reshuffleFromDiscard() {
        guard state.discardPile.count > 1 else { return }
        let top = state.discardPile.removeLast()
        var pool = state.discardPile
        pool.shuffle()
        state.drawPile = pool
        state.discardPile = [top]
    }

    private func randomizeBombCard() {
        guard state.config.bombEnabled else {
            state.bombCardId = nil
            return
        }

        var pool: [UNOCard] = state.drawPile
        for p in state.players { pool.append(contentsOf: p.hand) }
        pool.append(contentsOf: state.discardPile)

        let candidates = pool.filter { $0.id != state.bombCardId }
        state.bombCardId = candidates.randomElement()?.id
    }

    private func advanceTurn(skips: Int = 0) {
        let count = state.players.count
        guard count > 0 else { return }

        var steps = 1 + skips
        if !state.clockwise { steps = -steps }

        state.turnIndex = (state.turnIndex + steps % count + count) % count
    }

    private func findPlayerIndex(id: UUID) -> Int? {
        state.players.firstIndex { $0.id == id }
    }

    // MARK: EVENT HANDLING

    func handle(_ event: WireEvent) {
        switch event {

        // ---------------------------------------------------------
        // HELLO (client → host)
        // ---------------------------------------------------------
        case .hello(let peerId, let name, let deviceName):
            guard state.hostId == myId else { return }

            // Block late join unless enabled
            if state.started && !state.config.allowJoinInProgress { return }

            if !state.players.contains(where: { $0.id == peerId }) {
                state.players.append(
                    Player(
                        id: peerId,
                        name: name,
                        deviceName: deviceName,
                        hand: []))

                // Join-in-progress gives them cards instantly
                if state.started, let idx = findPlayerIndex(id: peerId) {
                    for _ in 0..<state.config.startingHandCount {
                        drawCard(to: idx)
                    }
                }
                syncAll()
            }

        // ---------------------------------------------------------
        case .start(let config):
            if state.hostId != myId { state.config = config }

        case .updateConfig(let config):
            if state.hostId != myId { state.config = config }

        // ---------------------------------------------------------
        // DRAW INTENT
        // ---------------------------------------------------------
        case .intentDraw(let pid):
            guard state.hostId == myId else { return }
            guard state.started, state.winnerId == nil else { return }
            guard let currId = state.currentPlayerId,
                  let currIdx = findPlayerIndex(id: currId),
                  currId == pid else { return }

            // Shot Caller special case:
            // If it's the target's turn and there is no pending draw stack,
            // they may only draw if they *do not* have any playable card.
            // As soon as they have at least one playable card, they MUST play it
            // (we simply refuse further draws).
            if let target = state.shotCallerTargetId,
               target == currId,
               state.pendingDraw == 0 {

                // Do they already have a legal move?
                let hand = state.players[currIdx].hand
                let hasPlayable = hand.contains { card in
                    state.canPlay(card)
                }

                // If they have *any* playable card, ignore the draw request.
                // Client will still show it's their turn, but draw does nothing.
                guard !hasPlayable else {
                    return
                }

                // No playable card yet: allow a single-card draw, and keep their turn.
                drawCard(to: currIdx)
                syncAll()
                return
            }

            // Normal / stacked draw path. Use a host-side lock so spamming Draw
            // cannot cause multiple concurrent resolutions or double turn-skips.
            guard !drawInProgress else { return }
            drawInProgress = true

            let drawCount = max(1, state.pendingDraw)
            state.pendingDraw = 0
            let playerIndex = currIdx

            Task { @MainActor in
                for _ in 0..<drawCount {
                    self.drawCard(to: playerIndex)
                    self.syncAll()
                    try? await Task.sleep(nanoseconds: 350_000_000) // ~0.35s per card
                }
                self.advanceTurn()
                self.syncAll()
                self.drawInProgress = false
            }

        // ---------------------------------------------------------
        // PLAY CARD
        // ---------------------------------------------------------
        case .intentPlay(let card, let chosen, let targetId):
            guard state.hostId == myId else { return }
            guard state.started, state.winnerId == nil else { return }
            guard let currId = state.currentPlayerId,
                  let currIdx = findPlayerIndex(id: currId) else { return }

            guard let handIdx = state.players[currIdx].hand.firstIndex(of: card),
                  state.canPlay(card) else { return }

            // Require targetId when Shot Caller is enabled and card is a wild
            if state.config.shotCallerEnabled,
               (card.value == .wild),
               targetId == nil {
                return // reject the play until the client sends targetId
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
                state.chosenWildColor = chosen ?? [.red, .yellow, .green, .blue].randomElement()!
                if state.config.shotCallerEnabled {
                    state.shotCallerTargetId = targetId
                }
            case .wildDraw4:
                state.pendingDraw += 4
                state.chosenWildColor = chosen ?? [.red, .yellow, .green, .blue].randomElement()!
                if state.config.shotCallerEnabled {
                    state.shotCallerTargetId = targetId
                }
            case .number:
                break
            }

            // BOMB RULE
            if state.config.bombEnabled,
               let bomb = state.bombCardId,
               bomb == card.id {

                for i in state.players.indices where i != currIdx {
                    for _ in 0..<max(1, state.config.bombDrawCount) {
                        drawCard(to: i)
                    }
                }

                state.clockwise.toggle()
                skips += 1
                randomizeBombCard()
            }

            // Win
            if state.players[currIdx].hand.isEmpty {
                // Mark winner and freeze the round; host can hit “Play Again” from UI
                state.winnerId = currId
                state.pendingDraw = 0
                state.unoCalled.removeAll()
                state.started = false
                syncAll()
                return
            }

            let prevPlayerId = state.players[currIdx].id
            advanceTurn(skips: skips)

            if state.shotCallerTargetId == prevPlayerId {
                state.shotCallerTargetId = nil
                state.chosenWildColor = nil
            }

            syncAll()

        // ---------------------------------------------------------
        // UNO CALL
        // ---------------------------------------------------------
        case .callUno(let pid):
            guard state.hostId == myId else { return }
            guard state.started, state.winnerId == nil else { return }
            state.unoCalled.insert(pid)

        // ---------------------------------------------------------
        // LEAVE TABLE
        // ---------------------------------------------------------
        case .leave(let pid):
            if state.hostId == myId {
                guard let idx = findPlayerIndex(id: pid) else { return }

                state.players.remove(at: idx)

                if state.players.isEmpty {
                    state = GameState()
                    return
                }

                if idx < state.turnIndex {
                    state.turnIndex -= 1
                }

                if state.turnIndex >= state.players.count {
                    state.turnIndex = 0
                }

                if state.started && state.players.count == 1 {
                    dealNewRound()
                }

                syncAll()

            } else {
                if pid == state.hostId {
                    state = GameState()
                }
            }

        // ---------------------------------------------------------
        // SYNC
        // ---------------------------------------------------------
        case .sync(let s):
            if state.hostId != myId {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    state = s
                }
            }
        }
    }

    // MARK: Outgoing //////////////////////////////////////////////////////////

    func sendIntentDraw() {
        guard state.started, state.winnerId == nil else { return }

        if state.hostId == myId {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                handle(.intentDraw(peerId: myId))
            }
        } else {
            mpc.broadcast(.intentDraw(peerId: myId))
        }
    }

    func sendUnoCall() {
        guard state.started, state.winnerId == nil else { return }

        if state.hostId == myId {
            state.unoCalled.insert(myId)
            syncAll()
        } else {
            mpc.broadcast(.callUno(peerId: myId))
        }
    }

    func sendIntentPlay(card: UNOCard, chosen: UNOColor?, target: UUID?) {
        guard state.started, state.winnerId == nil else { return }

        if state.hostId == myId {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                handle(.intentPlay(card: card, chosenColor: chosen, targetId: target))
            }
        } else {
            mpc.broadcast(.intentPlay(card: card, chosenColor: chosen, targetId: target))
        }
    }

    func updateConfig(_ newConfig: GameConfig) {
        guard state.hostId == myId else { return }
        state.config = newConfig
        mpc.broadcast(.updateConfig(config: newConfig))
    }

    func sendLeave() {
        mpc.broadcast(.leave(peerId: myId))
    }

    func syncAll() {
        mpc.broadcast(.sync(state: state))
    }

    // MARK: - Disconnect handling

    @MainActor
    private func handlePeerDisconnected(displayName: String) {
        guard state.hostId == myId else { return }

        // Find ANY player whose name OR device matches, but prioritize id-lookup
        while let idx = state.players.firstIndex(where: { p in
            (p.deviceName == displayName || displayName.contains(p.name)) && p.id != state.hostId
        }) {
            let removedIndex = idx
            state.players.remove(at: removedIndex)

            if state.players.isEmpty {
                state.turnIndex = 0
                break
            }

            adjustTurnIndexAfterRemoval(removedIndex: removedIndex)

            if state.started && state.players.count == 1 {
                dealNewRound()
                break
            }
        }

        syncAll()
    }

    // Keep turnIndex valid after removing a player at `removedIndex`.
    private func adjustTurnIndexAfterRemoval(removedIndex: Int) {
        guard !state.players.isEmpty else {
            state.turnIndex = 0
            return
        }

        // If the removed player was before the current index, shift left.
        if removedIndex < state.turnIndex {
            state.turnIndex -= 1
        }

        // If the removed player *was* the current index, leave turnIndex as-is;
        // it now points at whoever slid into that slot (the next player).

        // Clamp into valid range.
        if state.turnIndex >= state.players.count {
            state.turnIndex = 0
        }
    }
}
