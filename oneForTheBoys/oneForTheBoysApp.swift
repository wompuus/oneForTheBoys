import SwiftUI
import UIKit
import MultipeerConnectivity
import OFTBShared

extension Notification.Name {
    static let returnToLobbyRequested = Notification.Name("ReturnToLobbyRequested")
    static let backToLobbyScreenRequested = Notification.Name("BackToLobbyScreenRequested")
}

enum AppScreen {
    case lobby
    case game
}

@main
struct oneForTheBoysApp: App {
    // Testing Web Socket
    private let webSocketClient = WebSocketClient()
    var body: some Scene {
        WindowGroup {
            AppRootView()
//                .onAppear {
//                    webSocketClient.connect()
//                }
        }
    }
}

@MainActor
struct AppRootView: View {
    private let connectivity: ConnectivityManager
    private let router: GameTransportRouter
    private let initialDeviceName: String
    @State private var session: AnyGameSession?
    @State private var localProfile: PlayerProfile?
    @State private var currentGame: GameID = GameID.allCases.first ?? .crazyEights
    @State private var screen: AppScreen = .lobby
    @State private var showLeaveConfirm = false
    @State private var hostLeftReason: String?
    @State private var profileLoaded = false
    @State private var peerToPlayerMap: [MCPeerID: UUID] = [:]
    @State private var showProfileEditor = false
    @State private var isNewProfile = false
    @State private var onlineTransport: WebSocketTransport?

    init() {
        GameRegistry.bootstrap()
        let initialName = UIDevice.current.name
        initialDeviceName = initialName
        let connectivity = ConnectivityManager(displayName: initialName)
        self.connectivity = connectivity
        self.router = GameTransportRouter(connectivity: connectivity)
        _localProfile = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            if let profile = localProfile, profileLoaded {
                switch screen {
                case .lobby:
                    UnifiedLobbyView(
                        connectivity: connectivity,
                        localProfile: profile,
                        onStartGame: { players, lobbySettings, hostId, isHost, peerMap in
                            currentGame = lobbySettings.gameId
                            // Convert peerMap keyed by displayName into MCPeerID map for disconnect handling.
                            peerToPlayerMap = Dictionary(uniqueKeysWithValues: peerMap.compactMap { (name, pid) in
                                (MCPeerID(displayName: name), pid)
                            })
                            print("[App] start game id=\(lobbySettings.gameId) isHost=\(isHost) players=\(players.count)")
                            Task { @MainActor in
                                if lobbySettings.connectionMode == .onlineServer,
                                   lobbySettings.gameId == .crazyEights {
                                    let roomCode = lobbySettings.onlineRoomCode ?? generateRoomCode()
                                    let snapshot = PublicPlayerSnapshot(
                                        id: profile.id,
                                        displayName: profile.username,
                                        avatar: profile.avatar
                                    )
                                    guard let url = URL(string: "wss://oftb-server.fly.dev/crazy-eights") else {
                                        print("[App] invalid server URL")
                                        return
                                    }
                                    let transport = WebSocketTransport(roomCode: roomCode, playerSnapshot: snapshot, serverURL: url, isHost: isHost)
                                    let placeholderState = CrazyEightsGameState()
                                    let store = GameStore(
                                        initialState: placeholderState,
                                        transport: transport,
                                        reducer: CrazyEightsGameModule.reducer,
                                        isHost: isHost,
                                        allowsOptimisticUI: false
                                    )
                                    store.setLocalPlayerId(profile.id)
                                    var didReceiveInitialState = false
                                    transport.onStateReceived = { state in
                                        Task { @MainActor in
                                            store.updateState(state)
                                            if state.started {
                                                if !didReceiveInitialState {
                                                    didReceiveInitialState = true
                                                    self.session = AnyGameSession(
                                                        gameId: .crazyEights,
                                                        gameView: CrazyEightsGameModule.makeView(store: store),
                                                        resultsView: { _, localId in
                                                            CrazyEightsGameModule.makeResultsView(state: store.state, players: players, localPlayerId: localId)
                                                        },
                                                        registerWithRouter: { _ in },
                                                        encodeSettings: { try? JSONEncoder().encode(lobbySettings.crazyEights) },
                                                        encodeState: { try? JSONEncoder().encode(store.state) },
                                                        onLeave: { pid in
                                                            if let action = CrazyEightsGameModule.leaveAction(for: pid) {
                                                                Task { await transport.send(action) }
                                                            }
                                                            transport.disconnect()
                                                        },
                                                        isHost: isHost
                                                    )
                                                }
                                                screen = .game
                                            }
                                        }
                                    }
                                    transport.onError = { message in
                                        print("[WebSocketTransport] \(message)")
                                        if !didReceiveInitialState {
                                            Task { @MainActor in
                                                hostLeftReason = "Lobby doesn't exist"
                                                await backToLobbyWithoutLeavingLobby()
                                            }
                                        }
                                    }
                                    transport.connect()
                                    onlineTransport = transport
                                } else {
                                    await connectivity.setLocalPlayerId(profile.id)
                                    await connectivity.setActiveGame(lobbySettings.gameId)
                                    guard let newSession = GameRegistry.shared.makeSession(
                                        for: lobbySettings.gameId,
                                        players: players,
                                        settingsData: lobbySettings.activeSettingsData,
                                        transport: connectivity,
                                        isHost: isHost,
                                        localPlayerId: profile.id
                                    ) else { return }

                                    newSession.registerWithRouter(router) // register before activation
                                    await router.activate()
                                    print("[App] session registered and router active")
                                    session = newSession
                                    screen = .game
                                    router.onHostLeft = { reason in
                                        hostLeftReason = reason
                                        forceLeaveToLobby()
                                    }

                                    if isHost {
                                        setupHostDisconnectHandler(session: newSession)
                                        if let payload = newSession.encodeState() {
                                            await connectivity.sendNetworkMessage(.gameState(gameId: newSession.gameId, payload: payload))
                                        }
                                    } else {
                                        try? await Task.sleep(nanoseconds: 200_000_000)
                                        await connectivity.sendNetworkMessage(.gameStateRequest(gameId: newSession.gameId))
                                    }
                                }
                            }
                        },
                        onEditProfile: { showProfileEditor = true }
                    )
                    .id(profile.id.uuidString + profile.username)

                case .game:
                    session?.gameView
                        .navigationBarBackButtonHidden(true)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Leave Lobby") {
                                    showLeaveConfirm = true
                                }
                            }
                        }
                        .confirmationDialog("Leave game?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
                            Button("Leave", role: .destructive) {
                                Task { await gracefulLeaveGame() }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will return you to the lobby.")
                        }
                }
            } else {
                ProgressView("Loading profile…")
            }
        }
        .alert(hostLeftReason ?? "", isPresented: Binding(get: { hostLeftReason != nil }, set: { newValue in
            if !newValue { hostLeftReason = nil }
        })) {
            Button("OK", role: .cancel) { hostLeftReason = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileStoreUpdated)) { _ in
            Task {
                let (loaded, _) = await ProfileStore.shared.loadProfile(defaultName: initialDeviceName)
                await MainActor.run {
                    localProfile = loaded
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .returnToLobbyRequested)) { _ in
            Task { await gracefulLeaveGame() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .backToLobbyScreenRequested)) { _ in
            Task { await backToLobbyWithoutLeavingLobby() }
        }
        .sheet(isPresented: Binding(get: { showProfileEditor || (isNewProfile && profileLoaded) }, set: { newValue in
            if !newValue {
                showProfileEditor = false
                isNewProfile = false
            }
        })) {
            if let profile = localProfile {
                ProfileEditorView(profile: profile) { updated in
                    Task {
                        await ProfileStore.shared.save(updated)
                        await MainActor.run {
                            localProfile = updated
                            showProfileEditor = false
                            isNewProfile = false
                        }
                    }
                } onCancel: {
                    showProfileEditor = false
                    if isNewProfile { isNewProfile = false }
                }
            } else {
                ProgressView("Loading profile…")
            }
        }
        .task {
            guard !profileLoaded else { return }
            let (loaded, isNew) = await ProfileStore.shared.loadProfile(defaultName: initialDeviceName)
            await MainActor.run {
                localProfile = loaded
                profileLoaded = true
                isNewProfile = isNew
            }
        }
    }

    private func gracefulLeaveGame() async {
        guard let session, let profile = localProfile else { return }
        session.onLeave(profile.id)
        print("[App] leaving game \(session.gameId) isHost=\(session.isHost)")
        if session.isHost {
            await connectivity.sendNetworkMessage(.hostLeft(gameId: session.gameId, reason: "The host has left the game"))
        }
        onlineTransport?.disconnect()
        onlineTransport = nil
        // allow leave/hostLeft message to flush
        try? await Task.sleep(nanoseconds: 500_000_000)
        await connectivity.stop()
        await MainActor.run {
            self.session = nil
            self.screen = .lobby
        }
    }

    private func forceLeaveToLobby() {
        Task {
            await connectivity.stop()
            onlineTransport?.disconnect()
            onlineTransport = nil
            await MainActor.run {
                session = nil
                screen = .lobby
            }
        }
    }

    private func backToLobbyWithoutLeavingLobby() async {
        onlineTransport?.disconnect()
        onlineTransport = nil
        await connectivity.setActiveGame(nil)
        await MainActor.run {
            session = nil
            screen = .lobby
        }
    }

    private func setupHostDisconnectHandler(session: AnyGameSession) {
        Task {
            await connectivity.addOnPeerDisconnectedHandler { peerID in
                Task { @MainActor in
                    guard session.isHost else { return }
                    if let playerId = peerToPlayerMap[peerID] {
                        session.onLeave(playerId)
                    }
                }
            }
        }
    }

    private func generateRoomCode(length: Int = 4) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

}
