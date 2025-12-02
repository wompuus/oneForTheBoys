import SwiftUI
import CoreGraphics

struct DartsGameView: View {
    @ObservedObject var store: GameStore<DartsGameState, DartsAction>
    @StateObject private var realityController = DartsRealityController()
    @State private var lastDragTime: Date?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Board / AR layer fills screen; overlay UI sits on top.
                DartsRealityView(
                    controller: realityController,
                    turnHistory: store.state.turnHistory,
                    remoteFlights: store.state.remoteFlights,
                    onHit: { _ in
                        // Scoring is handled when the flight actually lands via onFlightLanded.
                    },
                    onFlightSpawn: { dartId in
                        if let pid = store.state.currentPlayerId {
                            store.send(.dartFlightSpawn(dartId: dartId, playerId: pid))
                        }
                    },
                    onFlightUpdate: { dartId, position, orientation in
                        if let pid = store.state.currentPlayerId {
                            store.send(.dartFlightUpdate(dartId: dartId, playerId: pid, position: position, orientation: orientation))
                        }
                    },
                    onFlightLanded: { dartId, hit in
                        if let pid = store.state.currentPlayerId {
                            store.send(.dartFlightLanded(dartId: dartId, playerId: pid, location: GamePoint(x: hit.x, y: hit.y)))
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)

                // Keep score at the top; remove turn indicator.
                VStack {
                    Spacer().frame(height: geo.size.height * 0.13)
                    scoreStrip
                        .padding(.horizontal, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 0)
                .ignoresSafeArea(edges: .top)

                // Gesture layer at bottom.
                VStack {
                    Spacer()
                    dartThrowZone(fullSize: geo.size)
                        .frame(height: geo.size.height * 0.3)
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: [.leading, .trailing, .bottom])

                // Next round prompt when a full cycle is complete.
                if store.isHost, store.state.cycleComplete, !isGameOver {
                    VStack {
                        Spacer()
                        Button(action: {
                            store.send(.startNextCycle)
                        }) {
                            Text("Start Next Round")
                                .font(.headline.bold())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.blue.opacity(0.9)))
                                .foregroundColor(.white)
                        }
                        .padding(.bottom, 40)
                    }
                    .ignoresSafeArea(.all)
                }

                if let toast = store.state.lastHitText,
                   let ts = store.state.lastHitTimestamp {
                    HitToastView(text: toast, timestamp: ts)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }

                if let winnerId = store.state.winnerId,
                   let winner = store.state.players.first(where: { $0.id == winnerId }) {
                    WinBannerView(
                        name: winner.name,
                        isHost: store.isHost,
                        onExit: {
                            guard store.isHost else { return }
                            NotificationCenter.default.post(name: .returnToLobbyRequested, object: nil)
                        }
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .ignoresSafeArea()
                }
            }
        }
    }

    private func dartThrowZone(fullSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isMyTurn && !isGameOver, realityController.isThrowInFlight == false, realityController.isCameraAnimatingBack == false, !(store.isHost && store.state.cycleComplete) else { return }
                            lastDragTime = Date()
                            realityController.ensureReadyDart()
                            realityController.updateHeldDart(translation: CGPoint(x: value.translation.width, y: value.translation.height))
                        }
                    .onEnded { value in
                        guard isMyTurn && !isGameOver, realityController.isThrowInFlight == false, realityController.isCameraAnimatingBack == false, !(store.isHost && store.state.cycleComplete) else { return }
                        // require an upward flick of at least 50 pts
                        guard value.translation.height < -50 else {
                            realityController.spawnReadyDart()
                            return
                        }
                        let duration = max(0.05, Date().timeIntervalSince(lastDragTime ?? Date()))
                        let vx = value.translation.width / duration
                        let vy = value.translation.height / duration
                        realityController.throwDart(flick: CGPoint(x: vx, y: vy))
                    }
            )
    }

    private var isMyTurn: Bool {
        store.state.currentPlayerId == store.localPlayerId
    }

    private var isGameOver: Bool {
        store.state.winnerId != nil
    }

    private var turnIndicator: some View {
        let currentName: String = {
            guard store.state.players.indices.contains(store.state.currentPlayerIndex) else { return "..." }
            return store.state.players[store.state.currentPlayerIndex].name
        }()
        let text = isMyTurn ? "YOUR TURN" : "\(currentName)'s Turn"
        return Text(text)
            .font(.headline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(isMyTurn ? Color.green.opacity(0.8) : Color.gray.opacity(0.8)))
    }

    private var scoreStrip: some View {
        let players = store.state.players
        return HStack(spacing: 12) {
            ForEach(players) { player in
                let isActive = store.state.currentPlayerId == player.id
                let score = store.state.scores[player.id] ?? store.state.config.startingScore
                VStack(spacing: 6) {
                    AvatarView(config: player.avatar ?? AvatarConfig(
                        version: 1,
                        baseSymbol: "person.fill",
                        skinColorHex: "E3C0A8",
                        hairSymbol: nil,
                        hairColorHex: "4A2E2E",
                        accessorySymbol: nil,
                        backgroundColorHex: "1C1C1E"
                    ), size: 32)
                    Text(player.name)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.white)
                    Text("\(score)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isActive ? Color.green.opacity(0.85) : Color.gray.opacity(0.65))
                        )
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.3))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        )
        .frame(maxWidth: .infinity)
    }
}

private struct HitToastView: View {
    let text: String
    let timestamp: Date
    @State private var now: Date = Date()

    private var opacity: Double {
        let age = now.timeIntervalSince(timestamp)
        if age < 0 { return 0 }
        if age <= 0.2 { return age / 0.2 }
        if age >= 1.2 { return max(0, 1.4 - age) / 0.2 }
        return 1.0
    }

    private var offset: CGFloat {
        let age = now.timeIntervalSince(timestamp)
        if age < 0 { return 20 }
        if age <= 0.4 { return 20 - CGFloat(age / 0.4) * 20 }
        return 0
    }

    var body: some View {
        Text(text)
            .font(.system(size: 36, weight: .heavy, design: .rounded))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
            )
            .foregroundStyle(.white)
            .opacity(opacity)
            .offset(y: offset)
            .onAppear {
                // Simple timer to drive fade
                withAnimation(.easeOut(duration: 1.2)) { now = Date() }
            }
            .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                now = Date()
            }
    }
}

private struct WinBannerView: View {
    let name: String
    let isHost: Bool
    let onExit: () -> Void
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)
            VStack(spacing: 16) {
                Text("\(name) Wins!")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                Text("Game Over")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                if isHost {
                    Button(action: onExit) {
                        Text("Return to Lobby")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.blue.opacity(0.9))
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
            )
            .scaleEffect(animate ? 1.0 : 0.8)
            .opacity(animate ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    animate = true
                }
            }
        }
    }
}
