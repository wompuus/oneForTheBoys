import SwiftUI
import Foundation

struct CEOpponent: Identifiable {
    let id: UUID
    let name: String
    let handCount: Int
    let avatar: AvatarConfig?
}

struct CrazyEightsGameView: View {
@ObservedObject var store: GameStore<CrazyEightsGameState, CrazyEightsAction>
let localPlayerId: UUID
    private var state: CrazyEightsGameState { store.state }
    private var myTurn: Bool { state.currentPlayerId == localPlayerId }
    private var gameOver: Bool { state.winnerId != nil }
    private var meIndex: Int? { state.players.firstIndex { $0.id == localPlayerId } }
    private var myHand: [UNOCard] {
        guard let meIndex else { return [] }
        return crazySortHand(state.players[meIndex].hand)
    }
    private var otherPlayers: [CEOpponent] {
        state.players
            .filter { $0.id != localPlayerId }
            .map { CEOpponent(id: $0.id, name: $0.name, handCount: $0.hand.count, avatar: $0.avatar) }
    }
    @State private var activeModal: ActiveModal?
    @State private var bombToShow: CrazyEightsGameState.BombEvent?
    @State private var bombOpacity: Double = 0
    @State private var flights: [CardFlightOverlay.Flight] = []
    @State private var lastHandCounts: [UUID: Int] = [:]
    @State private var lastDiscardId: UUID?
    @State private var drawLoopTask: Task<Void, Never>?
    @State private var isDrawing = false
    @State private var didAutoStartRound = false
    private enum ActiveModal: Identifiable {
        case colorPicker(UNOCard)
        case shotCaller(UNOCard)
        var id: UUID {
            switch self {
            case .colorPicker(let card), .shotCaller(let card):
                return card.id
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.tableRed.ignoresSafeArea()

                ForEach(Array(otherPlayers.enumerated()), id: \.element.id) { index, p in
                    let angle = crazyOpponentAngle(index: index, total: otherPlayers.count)
                    OpponentSeatView(
                        player: CEOpponent(id: p.id, name: p.name, handCount: p.handCount, avatar: p.avatar),
                        isCurrentTurn: state.currentPlayerId == p.id,
                        rotationAngle: angle
                    )
                    .position(crazyOpponentPosition(index: index, total: otherPlayers.count, in: geo.size))
                }

                VStack(spacing: 12) {
                    Spacer()

                    centerStack

                    Spacer()

                    handStack
                }
                .padding(.horizontal, 8)

                if let bomb = bombToShow {
                    BombOverlay(event: bomb, players: state.players, drawCount: max(1, state.config.bombDrawCount))
                        .opacity(bombOpacity)
                        .transition(.scale.combined(with: .opacity))
                }

                CardFlightOverlay(flights: flights)
            }
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .shotCaller(let card):
                ShotCallerSheet(players: otherPlayers.map { Player(id: $0.id, name: $0.name, deviceName: "", hand: []) }) { color, target in
                    store.send(.intentPlay(card: card, chosenColor: color, targetId: target))
                    activeModal = nil
                }
            case .colorPicker(let card):
                ColorPickerSheet { color in
                    store.send(.intentPlay(card: card, chosenColor: color, targetId: nil))
                    activeModal = nil
                }
            }
        }
        .onChange(of: state.bombEvent) { _, newValue in
            guard let newValue else { return }
            bombToShow = newValue
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                bombOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.3)) { bombOpacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    bombToShow = nil
                }
            }
        }
        .onAppear {
            if store.isHost && !state.started && !didAutoStartRound {
                didAutoStartRound = true
                store.send(.startRound)
            }
            lastHandCounts = handCounts(from: state)
            lastDiscardId = state.discardPile.last?.id
        }
        .onChange(of: state.discardPile.last?.id) { _, newValue in
            handleDiscardChange(newTopId: newValue)
        }
        .onChange(of: state.players.map { $0.hand.count }.joinedDescription) { _, _ in
            handleHandCountChange()
        }
    }

    private var centerStack: some View {
        VStack(spacing: 12) {
            HStack(spacing: 40) {
                DeckView(canDraw: myTurn && !gameOver && state.started && !isDrawing) {
                    handleDrawTap()
                }

                if let top = state.topCard {
                    CardView(card: overriddenTopCard(top), isPlayable: false)
                        .scaleEffect(0.8)
                }
            }

            if let chosen = state.chosenWildColor {
                VStack(spacing: 4) {
                    Text("Wild color: \(chosen.display)")
                        .font(.subheadline)
                        .foregroundStyle(.yellow)
                    if state.config.shotCallerEnabled,
                       let target = state.shotCallerTargetId {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Target: \(playerName(id: target))")
                                .font(.caption)
                                .foregroundStyle(.yellow.opacity(0.9))
                        }
                    }
                }
            }

            if let winnerId = state.winnerId,
               let winner = state.players.first(where: { $0.id == winnerId }) {
                VStack(spacing: 8) {
                    Text("🏆 \(winner.name) wins!")
                        .font(.title3.bold())
                        .foregroundStyle(.yellow)

                    if state.hostId == localPlayerId {
                        Button("Play Again") {
                            store.send(.startRound)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            HStack(spacing: 16) {
                if myTurn && myHand.count == 2 && !gameOver && state.started {
                    Button("UNO") {
                        store.send(.callUno(playerId: localPlayerId))
                    }
                    .buttonStyle(.bordered)
                }

                Text(gameOver ? "Round over" : (myTurn ? "Your turn" : "Waiting…"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))

                Text("Pending draw: \(state.pendingDraw)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var handStack: some View {
        VStack(spacing: 6) {
            Text(currentPlayerNameLine)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(myHand) { card in
                        let playable =
                        state.canPlay(card)
                        && myTurn
                        && !gameOver
                        && state.started

                        Button(action: { playTapped(card) }) {
                            CardView(card: card, isPlayable: playable)
                        }
                        .disabled(!playable)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.18))
                .overlay {
                    if myTurn && !gameOver && state.started {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                            .shadow(color: Color.white.opacity(0.9), radius: 12)
                    }
                }
        )
        .scaleEffect(myTurn && !gameOver && state.started ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: myTurn)
    }

    private var currentPlayerNameLine: String {
        guard let meIndex else { return "" }
        let me = state.players[meIndex]
        return "You: \(me.name) • Cards: \(me.hand.count)"
    }

    private func playTapped(_ card: UNOCard) {
        guard myTurn,
              state.canPlay(card),
              !gameOver,
              state.started else { return }

        switch card.value {
        case .wild, .wildDraw4:
            if state.config.shotCallerEnabled && card.value == .wild {
                activeModal = .shotCaller(card)
            } else {
                activeModal = .colorPicker(card)
            }
        default:
            store.send(.intentPlay(card: card, chosenColor: nil, targetId: nil))
        }
    }

    private func overriddenTopCard(_ card: UNOCard) -> UNOCard {
        guard card.color == .wild, let chosen = state.chosenWildColor else {
            return card
        }
        return UNOCard(id: card.id, color: chosen, value: card.value)
    }

    private func handCounts(from state: CrazyEightsGameState) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for p in state.players { map[p.id] = p.hand.count }
        return map
    }

    private func handleDiscardChange(newTopId: UUID?) {
        guard let newTopId, newTopId != lastDiscardId else { return }
        if let playedCard = state.discardPile.last,
           let playerId = playerWhoseHandDecreased() {
            addPlayFlight(card: playedCard, playerId: playerId)
        }
        lastDiscardId = newTopId
        lastHandCounts = handCounts(from: state)
    }

    private func handleHandCountChange() {
        if state.discardPile.last?.id == lastDiscardId {
            let current = handCounts(from: state)
            for (pid, newCount) in current {
                let old = lastHandCounts[pid] ?? 0
                if newCount > old {
                    let delta = newCount - old
                    for i in 0..<delta {
                        let delay = Double(i) * 0.1
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            addDrawFlight(playerId: pid)
                        }
                    }
                }
            }
            lastHandCounts = current
        }
    }

    private func playerWhoseHandDecreased() -> UUID? {
        let current = handCounts(from: state)
        var candidate: (UUID, Int)?
        for (id, newCount) in current {
            let old = lastHandCounts[id] ?? 0
            let delta = newCount - old
            if delta < 0 {
                if let existing = candidate {
                    if delta < existing.1 { candidate = (id, delta) }
                } else {
                    candidate = (id, delta)
                }
            }
        }
        lastHandCounts = current
        return candidate?.0
    }

    private func addPlayFlight(card: UNOCard, playerId: UUID) {
        let size = UIScreen.main.bounds.size
        let start = position(for: playerId, in: size)
        let end = crazyDiscardPosition(in: size)
        let flight = CardFlightOverlay.Flight(kind: .play(card), start: start, end: end, progress: 0)
        flights.append(flight)
        withAnimation(.easeInOut(duration: 0.35)) {
            if let idx = flights.firstIndex(where: { $0.id == flight.id }) {
                flights[idx].progress = 1
            }
        }
        animateFlightRemoval(id: flight.id)
    }

    private func addDrawFlight(playerId: UUID) {
        let size = UIScreen.main.bounds.size
        let start = crazyDeckPosition(in: size)
        let end = position(for: playerId, in: size)
        let flight = CardFlightOverlay.Flight(kind: .draw, start: start, end: end, progress: 0)
        flights.append(flight)
        withAnimation(.easeInOut(duration: 0.35)) {
            if let idx = flights.firstIndex(where: { $0.id == flight.id }) {
                flights[idx].progress = 1
            }
        }
        animateFlightRemoval(id: flight.id)
    }

    private func position(for playerId: UUID, in size: CGSize) -> CGPoint {
        if playerId == localPlayerId {
            return CGPoint(x: size.width / 2, y: size.height * 0.82)
        }
        let opponents = otherPlayers
        if let idx = opponents.firstIndex(where: { $0.id == playerId }) {
            return crazyOpponentPosition(index: idx, total: opponents.count, in: size)
        }
        return CGPoint(x: size.width / 2, y: size.height * 0.2)
    }

    private func animateFlightRemoval(id: UUID) {
        withAnimation(.easeInOut(duration: 0.35)) { }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            flights.removeAll { $0.id == id }
        }
    }

    private func playerName(id: UUID) -> String {
        state.players.first(where: { $0.id == id })?.name ?? "Player"
    }

    private func handleDrawTap() {
        drawLoopTask?.cancel()
        guard !isDrawing else { return }
        isDrawing = true
        drawLoopTask = Task { [weak store] in
            while !Task.isCancelled {
                await MainActor.run {
                    store?.send(.intentDraw(playerId: localPlayerId))
                }
                try? await Task.sleep(nanoseconds: 240_000_000)
                let s = await MainActor.run { store?.state }
                guard let s else { break }
                if s.pendingDraw == 0 || s.currentPlayerId != localPlayerId || s.winnerId != nil || !s.started {
                    break
                }
            }
            await MainActor.run {
                isDrawing = false
            }
        }
    }
}

private extension Array where Element == Int {
    var joinedDescription: String { map(String.init).joined(separator: "|") }
}
