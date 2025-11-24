import SwiftUI

enum RootScreen {
    case entry
    case hostLobby
    case joinLobby
    case game
}

@main
struct oneForTheBoysApp: App {
    var body: some Scene {
        WindowGroup {
            RootContentView()
        }
    }
}

struct RootContentView: View {
    @StateObject private var mpcService = MPCService()
    @StateObject private var orchestrator: GameOrchestrator

    @State private var screen: RootScreen = .entry
    @State private var displayName: String = UIDevice.current.name
    @State private var draftConfig: GameConfig = GameConfig()

    init() {
        let service = MPCService()
        _mpcService = StateObject(wrappedValue: service)
        _orchestrator = StateObject(wrappedValue: GameOrchestrator(mpc: service))
    }

    var body: some View {
        NavigationStack {
            content
                .onChange(of: orchestrator.state.started) {_,  started in
                    if started {
                        screen = .game
                    }
                }
                // When lobby membership changes and we're host, update advertised playerCount.
                .onChange(of: orchestrator.state.players.count) {_,  newCount in
                    if mpcService.isHost {
                        mpcService.updateHostedLobbyPlayerCount(newCount)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // If we ever get super out-of-sync, just drop back to entry.
                    if orchestrator.state.players.isEmpty && !mpcService.isHost {
                        screen = .entry
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .entry:
            EntryView(
                displayName: $displayName,
                nearbyCount: mpcService.connectedNames.count,
                onHost: hostTapped,
                onJoin: joinTapped
            )
            .navigationTitle("UNO")

        case .hostLobby:
            HostLobbyView(
                config: $draftConfig,
                players: orchestrator.state.players,
                onStartGame: startGameTapped,
                onLeaveLobby: leaveLobbyTapped
            )
            .navigationTitle("Host Lobby")

        case .joinLobby:
            JoinLobbyView(
                mpc: mpcService,
                players: orchestrator.state.players,
                onSelectLobby: joinSelectedLobby,
                onLeaveLobby: leaveLobbyTapped
            )
            .navigationTitle("Join Lobby")

        case .game:
            GameView(orch: orchestrator)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Leave Table") {
                            leaveTableTapped()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("Peers: \(mpcService.connectedNames.count)")
                    }
                }
        }
    }

    // MARK: - Actions

    private func hostTapped() {
        draftConfig = orchestrator.state.config // keep previous tweaks if any
        mpcService.startHosting(displayName: displayName)
        orchestrator.configureAsHost(displayName: displayName, config: draftConfig)
        screen = .hostLobby
    }

    private func joinTapped() {
        // Start browsing for lobbies and go to the join screen.
        mpcService.join()
        screen = .joinLobby
    }

    /// Called when the user taps a specific lobby in JoinLobbyView.
    private func joinSelectedLobby(_ lobby: FoundLobby) {
        let name = displayName

        // Connect to that specific host peer.
        mpcService.connect(to: lobby)

        // Retry sending HELLO until we're in the players list or attempts exhausted.
        func sendHelloAttempt(_ remaining: Int) {
            guard remaining > 0 else { return }

            if orchestrator.state.players.contains(where: { $0.id == orchestrator.myId }) {
                return
            }

            orchestrator.joinAsClient(displayName: name)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                sendHelloAttempt(remaining - 1)
            }
        }

        // Up to ~10 seconds of retries, same idea as before.
        sendHelloAttempt(10)
    }

    private func startGameTapped() {
        orchestrator.updateConfig(draftConfig)   // push latest config to clients
        orchestrator.hostStartGame()
    }

    private func leaveLobbyTapped() {
        // Let others know we're leaving the lobby BEFORE tearing down MPC.
        orchestrator.sendLeave()
        mpcService.stop()
        orchestrator.reset()
        draftConfig = GameConfig()
        screen = .entry
    }

    private func leaveTableTapped() {
        // Tell everyone we're gone before tearing down the session
        orchestrator.sendLeave()
        mpcService.stop()
        orchestrator.reset()
        draftConfig = GameConfig()
        screen = .entry
    }
}
