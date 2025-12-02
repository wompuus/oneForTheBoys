import SwiftUI
import Foundation

struct CEOpponent: Identifiable {
    let id: UUID
    let name: String
    let handCount: Int
    let avatar: AvatarConfig?
    let seatSlot: Int
}

struct CrazyEightsGameView: View {
@ObservedObject var store: GameStore<CrazyEightsGameState, CrazyEightsAction>
let localPlayerId: UUID
    private var state: CrazyEightsGameState { store.state }
    private var myTurn: Bool { state.currentPlayerId == localPlayerId }
    private var gameOver: Bool { state.winnerId != nil }
    private var meIndex: Int? { state.players.firstIndex { $0.id == localPlayerId } }
    private var seatingOrder: [CrazyEightsPlayer] {
        guard let hostId = state.hostId,
              let hostIdx = state.players.firstIndex(where: { $0.id == hostId }) else {
            return state.players
        }
        let tail = state.players[hostIdx...]
        let head = state.players[..<hostIdx]
        return Array(tail + head)
    }
    private var seatIndexById: [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (idx, player) in seatingOrder.enumerated() {
            map[player.id] = idx
        }
        return map
    }
    private var myHand: [UNOCard] {
        let hand = rawMyHand()
        if isBlindedLocal {
            return applyBlindOrder(hand)
        }
        return crazySortHand(hand)
    }
    private var otherPlayers: [CEOpponent] {
        seatingOrder.compactMap { player in
            guard player.id != localPlayerId else { return nil }
            guard let seatIndex = seatIndexById[player.id] else { return nil }
            let seatSlot = seatIndex
            return CEOpponent(
                id: player.id,
                name: player.name,
                handCount: player.hand.count,
                avatar: player.avatar,
                seatSlot: seatSlot
            )
        }
    }
    @State private var activeModal: ActiveModal?
    @State private var bombToShow: CrazyEightsGameState.BombEvent?
    @State private var bombOpacity: Double = 0
    @State private var bombHideTask: Task<Void, Never>?
    @State private var bombDrawTask: Task<Void, Never>?
    @State private var bombResolving: Bool = false
    @State private var flights: [CardFlightOverlay.Flight] = []
    @State private var lastHandCounts: [UUID: Int] = [:]
    @State private var lastDiscardId: UUID?
    @State private var drawLoopTask: Task<Void, Never>?
    @State private var isDrawing = false
    @State private var didAutoStartRound = false
    @State private var blindOrder: [UUID: Int] = [:]
    private enum ActiveModal: Identifiable {
        case colorPicker(UNOCard)
        case shotCaller(UNOCard)
        case swapTarget(UNOCard)
        case fogTarget(UNOCard)
        var id: UUID {
            switch self {
            case .colorPicker(let card), .shotCaller(let card):
                return card.id
            case .swapTarget(let card):
                return card.id
            case .fogTarget(let card):
                return card.id
            }
        }
    }

    private var awaitingSwap: Bool {
        guard state.config.allowSevenZeroRule,
              state.players.count > 1,
              let pending = state.pendingSwapPlayerId else { return false }
        return state.currentPlayerId == pending && pending == localPlayerId
    }

    private var isBlindedLocal: Bool {
        state.blindedPlayerId == localPlayerId && state.blindedTurnsRemaining > 0
    }

    private var myHandIdsKey: String {
        rawMyHand().map { $0.id.uuidString }.joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.tableRed.ignoresSafeArea()

                ForEach(otherPlayers, id: \.id) { p in
                    let totalSlots = max(seatingOrder.count, 2)
                    OpponentSeatView(
                        player: CEOpponent(id: p.id, name: p.name, handCount: p.handCount, avatar: p.avatar, seatSlot: p.seatSlot),
                        isCurrentTurn: state.currentPlayerId == p.id,
                        rotationAngle: crazySeatAngle(slot: p.seatSlot, total: totalSlots)
                    )
                    .position(crazySeatPosition(
                        slot: p.seatSlot,
                        total: totalSlots,
                        in: geo.size
                    ))
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
            case .swapTarget(let card):
                SwapHandSheet(
                    title: "Choose a player to swap hands with",
                    buttonTitle: "Swap",
                    players: otherPlayers.map { Player(id: $0.id, name: $0.name, deviceName: "", hand: []) }
                ) { target in
                    store.send(.intentPlay(card: card, chosenColor: nil, targetId: nil))
                    store.send(.swapHand(targetId: target))
                    activeModal = nil
                }
            case .fogTarget(let card):
                SwapHandSheet(
                    title: "Choose a player to blind",
                    buttonTitle: "Apply fog",
                    players: otherPlayers.map { Player(id: $0.id, name: $0.name, deviceName: "", hand: []) }
                ) { target in
                    store.send(.intentPlay(card: card, chosenColor: nil, targetId: target))
                    activeModal = nil
                }
            }
        }
        .onChange(of: state.bombEvent) { _, newValue in
            guard let newValue else { return }
            handleBombEvent(newValue)
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
        .onDisappear {
            bombHideTask?.cancel()
            bombDrawTask?.cancel()
            drawLoopTask?.cancel()
            bombResolving = false
        }
        .onChange(of: isBlindedLocal) { _, newValue in
            if newValue {
                updateBlindOrder(for: rawMyHand().map { $0.id })
            } else {
                blindOrder.removeAll()
            }
        }
        .onChange(of: myHandIdsKey) { _, _ in
            if isBlindedLocal {
                updateBlindOrder(for: rawMyHand().map { $0.id })
            }
        }
    }

    private var centerStack: some View {
        VStack(spacing: 12) {
            HStack(spacing: 40) {
                DeckView(canDraw: myTurn && !gameOver && state.started && !isDrawing && !bombResolving && !awaitingSwap) {
                    handleDrawTap()
                }

                if let top = state.topCard {
                    CardView(card: overriddenTopCard(top), isPlayable: false)
                        .scaleEffect(0.8)
                }
            }

            if !state.shotCallerDemands.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shot Caller")
                        .font(.subheadline)
                        .foregroundStyle(.yellow)
                    ForEach(state.shotCallerDemands.keys.sorted(by: { playerName(id: $0) < playerName(id: $1) }), id: \.self) { pid in
                        let demands = state.shotCallerDemands[pid] ?? []
                        HStack(spacing: 6) {
                            Text(playerName(id: pid))
                                .font(.caption)
                                .foregroundStyle(.yellow.opacity(0.9))
                            Text(demands.map { $0.display }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.yellow.opacity(0.8))
                        }
                    }
                }
            }

            if state.blindedTurnsRemaining > 0, let foggedId = state.blindedPlayerId {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fog of War")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    HStack(spacing: 6) {
                        Text(playerName(id: foggedId))
                            .font(.caption)
                            .foregroundStyle(.orange.opacity(0.9))
                        Text("Turns remaining: \(state.blindedTurnsRemaining)")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.8))
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
                if myTurn && myHand.count == 2 && !gameOver && state.started && !bombResolving && !awaitingSwap && !isBlindedLocal {
                    Button("DRAW") {
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
                        && !bombResolving
                        && !awaitingSwap
                        && !isBlindedLocal

                        let canTap =
                        myTurn
                        && !gameOver
                        && state.started
                        && !bombResolving
                        && !awaitingSwap

                        Button(action: { playTapped(card) }) {
                            if isBlindedLocal {
                                BackCardView()
                                    .frame(width: 70, height: 100)
                            } else {
                                CardView(card: card, isPlayable: playable)
                            }
                        }
                        .disabled(!canTap || (!isBlindedLocal && !playable))
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
                    if myTurn && !gameOver && state.started && !bombResolving && !awaitingSwap && !isBlindedLocal {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                            .shadow(color: Color.white.opacity(0.9), radius: 12)
                    }
                }
        )
        .scaleEffect(myTurn && !gameOver && state.started && !bombResolving && !awaitingSwap && !isBlindedLocal ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: myTurn)
    }

    private var currentPlayerNameLine: String {
        guard let meIndex else { return "" }
        let me = state.players[meIndex]
        return "You: \(me.name) • Cards: \(me.hand.count)"
    }

    private func playTapped(_ card: UNOCard) {
        guard myTurn,
              !gameOver,
              state.started,
              !bombResolving,
              !awaitingSwap else { return }

        let blinded = isBlindedLocal
        if !blinded && !state.canPlay(card) { return }

        switch card.value {
        case .wild, .wildDraw4:
            if state.config.shotCallerEnabled && card.value == .wild && !blinded {
                activeModal = .shotCaller(card)
            } else if !blinded {
                activeModal = .colorPicker(card)
            } else {
                store.send(.intentPlay(card: card, chosenColor: nil, targetId: nil))
            }
        case .fog:
            if state.config.fogEnabled && !otherPlayers.isEmpty && !blinded {
                activeModal = .fogTarget(card)
            } else {
                store.send(.intentPlay(card: card, chosenColor: nil, targetId: nil))
            }
        case .number(let n) where n == 7 && state.config.allowSevenZeroRule && !otherPlayers.isEmpty:
            if isBlindedLocal {
                store.send(.intentPlay(card: card, chosenColor: nil, targetId: nil))
            } else {
                activeModal = .swapTarget(card)
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

    private func handleBombEvent(_ event: CrazyEightsGameState.BombEvent) {
        bombHideTask?.cancel()
        bombDrawTask?.cancel()
        drawLoopTask?.cancel()
        bombResolving = true
        bombToShow = event
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            bombOpacity = 1.0
        }
        scheduleBombDrawFlights(for: event)
        bombHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { bombOpacity = 0 }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            bombToShow = nil
            bombResolving = false
        }
    }

    private func scheduleBombDrawFlights(for event: CrazyEightsGameState.BombEvent) {
        let victims = event.victimIds
        let drawCount = max(1, state.config.bombDrawCount)
        guard !victims.isEmpty else { return }

        // Bomb draws happen on the same state change as the discard, so fire the draw flights directly.
        bombDrawTask = Task { @MainActor in
            for _ in 0..<drawCount {
                if Task.isCancelled { return }
                for victimId in victims {
                    addDrawFlight(playerId: victimId)
                }
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
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
        if
            let seatIndex = seatIndexById[playerId]
        {
            return crazySeatPosition(
                slot: seatIndex,
                total: max(seatingOrder.count, 2),
                in: size
            )
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

    private func rawMyHand() -> [UNOCard] {
        guard let meIndex else { return [] }
        return state.players[meIndex].hand
    }

    private func applyBlindOrder(_ hand: [UNOCard]) -> [UNOCard] {
        hand.sorted { lhs, rhs in
            let l = blindOrder[lhs.id] ?? 0
            let r = blindOrder[rhs.id] ?? 0
            return l < r
        }
    }

    private func updateBlindOrder(for handIds: [UUID]) {
        var map = blindOrder
        for id in handIds where map[id] == nil {
            map[id] = Int.random(in: 0...Int.max)
        }
        for key in Array(map.keys) where !handIds.contains(key) {
            map.removeValue(forKey: key)
        }
        blindOrder = map
    }

    private func handleDrawTap() {
        drawLoopTask?.cancel()
        guard !isDrawing, !bombResolving, !awaitingSwap else { return }
        isDrawing = true
        drawLoopTask = Task { [weak store] in
            while !Task.isCancelled {
                await MainActor.run {
                    store?.send(.intentDraw(playerId: localPlayerId))
                }
                try? await Task.sleep(nanoseconds: 240_000_000)
                let s = await MainActor.run { store?.state }
                guard let s else { break }
                let isBombing = await MainActor.run { bombResolving }
                if isBombing || s.pendingDraw == 0 || s.currentPlayerId != localPlayerId || s.winnerId != nil || !s.started {
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
