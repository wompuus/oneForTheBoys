import SwiftUI

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
    private var otherPlayers: [Player] {
        state.players
            .filter { $0.id != localPlayerId }
            .map { Player(id: $0.id, name: $0.name, deviceName: $0.deviceName, hand: $0.hand) }
    }
    @State private var activeModal: ActiveModal?
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
                    OpponentSeatView(
                        player: p,
                        isCurrentTurn: state.currentPlayerId == p.id
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
            }
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .shotCaller(let card):
                ShotCallerSheet(players: otherPlayers) { color, target in
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
    }

    private var centerStack: some View {
        VStack(spacing: 12) {
            HStack(spacing: 40) {
                DeckView(canDraw: myTurn && !gameOver && state.started) {
                    store.send(.intentDraw(playerId: localPlayerId))
                }

                if let top = state.topCard {
                    CardView(card: overriddenTopCard(top), isPlayable: false)
                        .scaleEffect(0.8)
                }
            }

            if let chosen = state.chosenWildColor {
                Text("Wild color: \(chosen.display)")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
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
            if state.config.shotCallerEnabled {
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

}
