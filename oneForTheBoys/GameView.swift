import SwiftUI

struct GameView: View {
    @ObservedObject var orch: GameOrchestrator

    @State private var activeModal: ActiveModal? = nil

    // Animation tracking for any player's play/draw
    struct FlyingAnim {
        enum Kind {
            case play(UNOCard)
            case draw
        }
        let kind: Kind
        let playerId: UUID
    }

    @State private var flyingAnim: FlyingAnim? = nil
    @State private var flyingProgress: CGFloat = 0

    // For detecting who played / drew
    @State private var lastHandCounts: [UUID: Int] = [:]
    @State private var lastDiscardId: UUID? = nil

    private var gameOver: Bool { orch.state.winnerId != nil }
    private var myTurn: Bool { orch.state.currentPlayerId == orch.myId }
    private var meIndex: Int? { orch.state.players.firstIndex { $0.id == orch.myId } }
    private var myHandRaw: [UNOCard] { meIndex.map { orch.state.players[$0].hand } ?? [] }

    private var otherPlayers: [Player] {
        orch.state.players.filter { $0.id != orch.myId }
    }

    // Sorted hand: red, blue, yellow, green, wild
    private var myHand: [UNOCard] {
        sortHand(myHandRaw)
    }

    private var discardTopId: UUID? {
        orch.state.discardPile.last?.id
    }

    private var handSignature: String {
        orch.state.players
            .map { "\($0.id.uuidString):\($0.hand.count)" }
            .joined(separator: "|")
    }

    private enum ActiveModal: Identifiable {
        case colorPicker(UNOCard)
        case shotCaller(UNOCard)

        var id: UUID {
            switch self {
            case .colorPicker(let card),
                 .shotCaller(let card):
                return card.id
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Table background
                Color.tableRed
                    .ignoresSafeArea()

                // Opponents arranged around a semi-circle above the table
                ForEach(Array(otherPlayers.enumerated()), id: \.element.id) { index, p in
                    OpponentSeatView(
                        player: p,
                        isCurrentTurn: orch.state.currentPlayerId == p.id
                    )
                    .position(opponentPosition(index: index,
                                               total: otherPlayers.count,
                                               in: geo.size))
                }

                VStack(spacing: 12) {

                    // (Removed old top-left opponent strip – now using semi-circle layout)

                    Spacer()

                    // CENTER: Deck + discard + status
                    VStack(spacing: 12) {
                        HStack(spacing: 40) {
                            DeckView(canDraw: myTurn && !gameOver && orch.state.started) {
                                orch.sendIntentDraw()
                            }

                            if let top = orch.state.topCard {
                                // Center uses the SAME CardView as hand, just scaled down
                                CardView(
                                    card: overriddenTopCard(top),
                                    isPlayable: false
                                )
                                .scaleEffect(0.8)
                            }
                        }

                        if let chosen = orch.state.chosenWildColor {
                            Text("Wild color: \(chosen.display)")
                                .font(.subheadline)
                                .foregroundStyle(.yellow)
                        }

                        // Winner banner + Play Again (host only)
                        if let winnerId = orch.state.winnerId,
                           let winner = orch.state.players.first(where: { $0.id == winnerId }) {
                            VStack(spacing: 8) {
                                Text("🏆 \(winner.name) wins!")
                                    .font(.title3.bold())
                                    .foregroundStyle(.yellow)

                                if orch.state.hostId == orch.myId {
                                    Button("Play Again") {
                                        orch.dealNewRound()
                                        orch.syncAll()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }

                        HStack(spacing: 16) {
                            if myTurn && myHand.count == 2 && !gameOver && orch.state.started {
                                Button("UNO") {
                                    orch.sendUnoCall()
                                }
                                .buttonStyle(.bordered)
                            }

                            Text(
                                gameOver
                                ? "Round over"
                                : (myTurn ? "Your turn" : "Waiting…")
                            )
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))

                            Text("Pending draw: \(orch.state.pendingDraw)")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }

                    Spacer()

                    // BOTTOM: Your hand
                    VStack(spacing: 6) {
                        Text(currentPlayerNameLine)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(myHand) { card in
                                    let playable =
                                        orch.state.canPlay(card)
                                        && myTurn
                                        && flyingAnim == nil
                                        && !gameOver
                                        && orch.state.started

                                    Button(action: { playTapped(card) }) {
                                        CardView(card: card, isPlayable: playable)
                                            .transition(.asymmetric(
                                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)
                                            ))
                                    }
                                    .disabled(!playable)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .background(
                        ZStack {
                            // Subtle base strip behind your hand
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.18))

                            // Turn spotlight: tighter, clear glow when it's YOUR turn
                            if myTurn && !gameOver && orch.state.started {
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                                    .shadow(color: Color.white.opacity(0.9), radius: 12)
                            }
                        }
                    )
                    .scaleEffect(myTurn && !gameOver && orch.state.started ? 1.03 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: myTurn)
                }

                // Flying card overlay (plays + draws)
                if let anim = flyingAnim {
                    flyingView(for: anim)
                        .position(flyingPosition(for: anim, in: geo.size))
                        .opacity(flyingAnim == nil ? 0 : 1)
                        .animation(.easeInOut(duration: 0.25), value: flyingProgress)
                }
            }
            .onAppear {
                lastHandCounts = currentHandCounts()
                lastDiscardId = orch.state.topCard?.id
            }
            // Detect plays: discard top card changed
            .onChange(of: discardTopId) { oldValue, newValue in
                guard let newValue,
                      newValue != lastDiscardId,
                      let playedCard = orch.state.topCard
                else { return }

                let currentCounts = currentHandCounts()
                if let playerId = playerWhoseHandDecreased(old: lastHandCounts, new: currentCounts) {
                    triggerPlayAnimation(card: playedCard, playerId: playerId)
                }
                lastHandCounts = currentCounts
                lastDiscardId = newValue
            }
            // Detect draws: hand counts increased without discard change
            .onChange(of: handSignature) { _, _ in
                let currentCounts = currentHandCounts()

                var increaseCandidates: [UUID] = []
                for (id, newCount) in currentCounts {
                    let old = lastHandCounts[id] ?? 0
                    if newCount > old {
                        increaseCandidates.append(id)
                    }
                }

                // Only treat as draw if discard didn't change at the same time
                if orch.state.discardPile.last?.id == lastDiscardId {
                    for id in increaseCandidates {
                        triggerDrawAnimation(playerId: id)
                    }
                }

                lastHandCounts = currentCounts
            }
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .shotCaller(let card):
                ShotCallerSheet(players: otherPlayers) { color, target in
                    orch.sendIntentPlay(card: card, chosen: color, target: target)
                    activeModal = nil
                }

            case .colorPicker(let card):
                ColorPickerSheet { color in
                    orch.sendIntentPlay(card: card, chosen: color, target: nil)
                    activeModal = nil
                }
            }
        }
    }

    // MARK: - Flying visuals

    @ViewBuilder
    private func flyingView(for anim: FlyingAnim) -> some View {
        switch anim.kind {
        case .play(let card):
            CardView(card: overriddenTopCard(card), isPlayable: false)
                .frame(width: 90, height: 130)
        case .draw:
            BackCardView()
                .frame(width: 70, height: 100)
        }
    }

    private func flyingPosition(for anim: FlyingAnim, in size: CGSize) -> CGPoint {
        let t = flyingProgress.clamped(to: 0...1)

        let start: CGPoint
        let end: CGPoint

        switch anim.kind {
        case .play:
            start = playerPosition(playerId: anim.playerId, in: size)
            end = centerPosition(in: size)
        case .draw:
            start = deckPosition(in: size)
            end = playerPosition(playerId: anim.playerId, in: size)
        }

        let x = start.x + (end.x - start.x) * t
        let y = start.y + (end.y - start.y) * t
        return CGPoint(x: x, y: y)
    }

    private func triggerPlayAnimation(card: UNOCard, playerId: UUID) {
        flyingAnim = FlyingAnim(kind: .play(card), playerId: playerId)
        flyingProgress = 0

        withAnimation(.easeInOut(duration: 0.25)) {
            flyingProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            flyingAnim = nil
            flyingProgress = 0
        }
    }

    private func triggerDrawAnimation(playerId: UUID) {
        flyingAnim = FlyingAnim(kind: .draw, playerId: playerId)
        flyingProgress = 0

        withAnimation(.easeInOut(duration: 0.25)) {
            flyingProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            flyingAnim = nil
            flyingProgress = 0
        }
    }

    // MARK: - Layout helpers

    private func playerPosition(playerId: UUID, in size: CGSize) -> CGPoint {
        if playerId == orch.myId {
            // Bottom center for you
            return CGPoint(x: size.width / 2, y: size.height * 0.82)
        } else {
            let others = orch.state.players.filter { $0.id != orch.myId }
            guard let idx = others.firstIndex(where: { $0.id == playerId }) else {
                return CGPoint(x: size.width / 2, y: size.height * 0.2)
            }
            return opponentPosition(index: idx, total: others.count, in: size)
        }
    }

    private func opponentPosition(index: Int, total: Int, in size: CGSize) -> CGPoint {
        // Center of the "table" region
        let cx = size.width / 2
        let cy = size.height * 0.22
        let radius = min(size.width, size.height) * 0.28

        // Semi-circle from ~150° (left/top) to ~30° (right/top)
        let startAngle = CGFloat.pi * 5.0 / 6.0   // 150°
        let endAngle   = CGFloat.pi * 1.0 / 6.0   // 30°

        let t: CGFloat
        if total <= 1 {
            t = 0.5
        } else {
            t = CGFloat(index) / CGFloat(max(total - 1, 1))
        }

        let angle = startAngle + (endAngle - startAngle) * t

        let x = cx + cos(angle) * radius
        let y = cy - sin(angle) * radius  // minus because screen y grows downward

        return CGPoint(x: x, y: y)
    }

    private func deckPosition(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.35, y: size.height * 0.45)
    }

    private func centerPosition(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.65, y: size.height * 0.45)
    }

    // MARK: - Gameplay helpers

    private var currentPlayerNameLine: String {
        guard let meIndex else { return "" }
        let me = orch.state.players[meIndex]
        return "You: \(me.name) • Cards: \(me.hand.count)"
    }

    private func playTapped(_ card: UNOCard) {
        guard myTurn,
              orch.state.canPlay(card),
              flyingAnim == nil,
              !gameOver,
              orch.state.started else { return }

        switch card.value {
        case .wild:
            if orch.state.config.shotCallerEnabled {
                activeModal = .shotCaller(card)
            } else {
                activeModal = .colorPicker(card)
            }

        case .wildDraw4:
            // If Shot Caller should also apply to +4, flip this to .shotCaller(card)
            if orch.state.config.shotCallerEnabled {
                activeModal = .shotCaller(card)
            } else {
                activeModal = .colorPicker(card)
            }

        default:
            orch.sendIntentPlay(card: card, chosen: nil, target: nil)
        }
    }

    /// For wilds at center, visually reflect the chosen color by faking a colored card.
    private func overriddenTopCard(_ card: UNOCard) -> UNOCard {
        guard card.color == .wild, let chosen = orch.state.chosenWildColor else {
            return card
        }
        return UNOCard(id: card.id, color: chosen, value: card.value)
    }

    private func currentHandCounts() -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for p in orch.state.players {
            map[p.id] = p.hand.count
        }
        return map
    }

    private func playerWhoseHandDecreased(old: [UUID: Int], new: [UUID: Int]) -> UUID? {
        var candidate: (UUID, Int)? = nil
        for (id, newCount) in new {
            let oldCount = old[id] ?? 0
            let delta = newCount - oldCount
            if delta < 0 {
                if let existing = candidate {
                    if delta < existing.1 {
                        candidate = (id, delta)
                    }
                } else {
                    candidate = (id, delta)
                }
            }
        }
        return candidate?.0
    }

    /// Sort by color: red, blue, yellow, green, wild; then by value.
    private func sortHand(_ hand: [UNOCard]) -> [UNOCard] {
        hand.sorted { lhs, rhs in
            let colorRank: (UNOColor) -> Int = { color in
                switch color {
                case .red: return 0
                case .blue: return 1
                case .yellow: return 2
                case .green: return 3
                case .wild: return 4
                }
            }

            let valueRank: (UNOValue) -> Int = { value in
                switch value {
                case .number(let n): return n
                case .skip:          return 20
                case .reverse:       return 21
                case .draw2:         return 22
                case .wild:          return 30
                case .wildDraw4:     return 31
                }
            }

            let lc = colorRank(lhs.color)
            let rc = colorRank(rhs.color)
            if lc != rc { return lc < rc }

            let lv = valueRank(lhs.value)
            let rv = valueRank(rhs.value)
            if lv != rv { return lv < rv }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

// Helper clamp
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
