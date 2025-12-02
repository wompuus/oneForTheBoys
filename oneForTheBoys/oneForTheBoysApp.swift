import SwiftUI
import UIKit
import MultipeerConnectivity

extension Notification.Name {
    static let returnToLobbyRequested = Notification.Name("ReturnToLobbyRequested")
}

enum AppScreen {
    case lobby
    case game
}

@main
struct oneForTheBoysApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
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
            await MainActor.run {
                session = nil
                screen = .lobby
            }
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

}
