import SwiftUI

enum LobbyScreen {
    case entry
    case host
    case join
}

struct UnifiedLobbyView: View {
    @StateObject private var model: LobbyViewModel
    var onStartGame: (() -> Void)?

    init(connectivity: ConnectivityManager, localProfile: PlayerProfile, onStartGame: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: LobbyViewModel(connectivity: connectivity, localProfile: localProfile))
        self.onStartGame = onStartGame
    }

    var body: some View {
        NavigationStack {
            switch model.screen {
            case .entry:
                EntryView(
                    displayName: $model.displayName,
                    nearbyCount: model.discoveredLobbies.count,
                    onHost: { model.hostTapped() },
                    onJoin: { model.joinTapped() }
                )
                .navigationTitle("One For The Boys")

            case .host:
                HostLobbyView(
                    settings: $model.settings,
                    players: model.players,
                    onStartGame: {
                        onStartGame?()
                        model.startGameTapped()
                    },
                    onLeaveLobby: { model.leaveLobbyTapped() }
                )
                .navigationTitle("Host Lobby")

            case .join:
                JoinLobbyView(
                    lobbies: model.discoveredLobbies,
                    players: model.players,
                    onSelectLobby: { lobby in model.selectLobby(lobby) },
                    onLeaveLobby: { model.leaveLobbyTapped() }
                )
                .navigationTitle("Join Lobby")
            }
        }
        .task { await model.beginListening() }
    }
}

// MARK: - Entry screen

struct EntryView: View {
    @Binding var displayName: String
    let nearbyCount: Int
    let onHost: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            Text("One For The Boys")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                TextField("Your name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                Text("Nearby peers: \(nearbyCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            VStack(spacing: 12) {
                Button("Host Game", action: onHost)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                Button("Join Game", action: onJoin)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.vertical)
    }
}

// MARK: - Host Lobby

struct HostLobbyView: View {
    @Binding var settings: CrazyEightsSettings
    let players: [PlayerProfile]
    let onStartGame: () -> Void
    let onLeaveLobby: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Host Lobby")
                    .font(.title2.bold())
                Text("Players in lobby: \(players.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            List {
                Section("Players") {
                    if players.isEmpty {
                        Text("Waiting for players…")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(players) { p in
                            Text(p.username)
                        }
                    }
                }

                Section("Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            Stepper("Starting cards: \(settings.startingHandCount)", value: $settings.startingHandCount, in: 1...50)
                            Stepper("Skips per color: \(settings.skipPerColor)", value: $settings.skipPerColor, in: 0...50)
                            Stepper("Reverses per color: \(settings.reversePerColor)", value: $settings.reversePerColor, in: 0...50)
                            Stepper("+2 per color: \(settings.draw2PerColor)", value: $settings.draw2PerColor, in: 0...50)
                            Stepper("Wild count: \(settings.wildCount)", value: $settings.wildCount, in: 0...50)
                            Stepper("Wild+4 count: \(settings.wildDraw4Count)", value: $settings.wildDraw4Count, in: 0...50)
                        }

                        Divider()

                        Toggle("Allow stacking draws", isOn: $settings.allowStackDraws)
                        Toggle("Allow mixed stacking (+2 on +4)", isOn: $settings.allowMixedDrawStacking)
                            .disabled(!settings.allowStackDraws)

                        Toggle("Shot Caller UNO", isOn: $settings.shotCallerEnabled)
                        Toggle("THE BOMB", isOn: $settings.bombEnabled)
                        Stepper("Bomb draw per opponent: \(settings.bombDrawCount)", value: $settings.bombDrawCount, in: 1...10)

                        Toggle("Allow join in progress", isOn: $settings.allowJoinInProgress)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()

            VStack(spacing: 8) {
                Button("Start Game", action: onStartGame)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                Button("Leave Lobby", role: .destructive, action: onLeaveLobby)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
}

// MARK: - Join Lobby

struct JoinLobbyView: View {
    let lobbies: [ConnectivityManager.FoundLobby]
    let players: [PlayerProfile]
    let onSelectLobby: (ConnectivityManager.FoundLobby) -> Void
    let onLeaveLobby: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Join Lobby")
                .font(.title2.bold())

            GroupBox("Available Games") {
                if lobbies.isEmpty {
                    VStack(spacing: 4) {
                        Text("Searching for nearby games…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(lobbies) { lobby in
                            Button {
                                onSelectLobby(lobby)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lobby.hostName)
                                            .font(.body.bold())
                                        Text("Lobby ID: \(lobby.lobbyId)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("Players: \(lobby.playerCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.horizontal)

            GroupBox("Players in current lobby") {
                if players.isEmpty {
                    Text("Not joined yet, or waiting for host…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(players) { p in
                        Text(p.username)
                    }
                }
            }
            .padding(.horizontal)

            Spacer()

            Button("Leave Lobby", role: .destructive, action: onLeaveLobby)
                .buttonStyle(.bordered)
                .padding(.bottom)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class LobbyViewModel: ObservableObject {
    private let connectivity: ConnectivityManager
    private var pollTask: Task<Void, Never>?
    private(set) var localProfile: PlayerProfile

    @Published var screen: LobbyScreen = .entry
    @Published var displayName: String
    @Published var discoveredLobbies: [ConnectivityManager.FoundLobby] = []
    @Published var players: [PlayerProfile] = []
    @Published var settings: CrazyEightsSettings = CrazyEightsSettings()

    init(connectivity: ConnectivityManager, localProfile: PlayerProfile) {
        self.connectivity = connectivity
        self.localProfile = localProfile
        self.displayName = localProfile.username
    }

    func beginListening() async {
        await configureMessageHandler()
    }

    func hostTapped() {
        localProfile.username = displayName
        players = [localProfile]
        screen = .host
        Task { await connectivity.startHosting(playerCount: players.count) }
        startLobbyPolling()
    }

    func joinTapped() {
        screen = .join
        players = []
        Task { await connectivity.startBrowsing() }
        startLobbyPolling()
    }

    func selectLobby(_ lobby: ConnectivityManager.FoundLobby) {
        Task { await connectivity.connect(to: lobby) }
    }

    func leaveLobbyTapped() {
        pollTask?.cancel()
        pollTask = nil
        Task { await connectivity.stop() }
        players.removeAll()
        discoveredLobbies.removeAll()
        screen = .entry
    }

    func startGameTapped() {}

    private func startLobbyPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let lobbies = await connectivity.discoveredLobbies
                await MainActor.run { self.discoveredLobbies = lobbies }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func configureMessageHandler() async {
        await connectivity.onMessage = { [weak self] message, _ in
            guard let self else { return }
            Task { @MainActor in
                switch message {
                case .joinRequest(let profile, _, _):
                    if !self.players.contains(where: { $0.id == profile.id }) {
                        self.players.append(profile)
                    }
                case .joinAccepted(let lobby):
                    self.players = lobby.playerProfiles
                case .joinRejected:
                    self.players.removeAll()
                default:
                    break
                }
            }
        }
    }
}
