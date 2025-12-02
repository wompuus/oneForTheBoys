import SwiftUI

enum LobbyScreen {
    case entry
    case hostSelect
    case host
    case join
}

struct UnifiedLobbyView: View {
    private let connectivity: ConnectivityManager
    @StateObject private var model: LobbyViewModel
    var onStartGame: (@MainActor ([PlayerProfile], LobbyGameSettings, UUID, Bool, [String: UUID]) -> Void)?
    var onEditProfile: () -> Void

    init(connectivity: ConnectivityManager, localProfile: PlayerProfile, onStartGame: (@MainActor ([PlayerProfile], LobbyGameSettings, UUID, Bool, [String: UUID]) -> Void)? = nil, onEditProfile: @escaping () -> Void = {}) {
        self.connectivity = connectivity
        _model = StateObject(wrappedValue: LobbyViewModel(connectivity: connectivity, localProfile: localProfile, onStartGame: onStartGame))
        self.onStartGame = onStartGame
        self.onEditProfile = onEditProfile
    }

    var body: some View {
        NavigationStack {
            switch model.screen {
            case .entry:
                EntryView(
                    displayName: model.displayName,
                    nearbyCount: model.discoveredLobbies.count,
                    onHost: { model.hostTapped() },
                    onJoin: { model.joinTapped() }
                )
                .navigationTitle("One For The Boys")

            case .hostSelect:
                HostGameSelectView(
                    descriptors: GameRegistry.shared.allDescriptors,
                    onSelect: { model.selectGameToHost($0) },
                    onCancel: { model.cancelHostSelection() }
                )
                .navigationTitle("Select Game")

            case .host:
                HostLobbyView(
                    gameSettings: $model.gameSettings,
                    descriptors: GameRegistry.shared.allDescriptors,
                    players: model.players,
                    readyPlayerIDs: model.readyPlayerIDs,
                    localPlayerId: model.localProfile.id,
                    onToggleReady: { ready in model.setReady(ready) },
                    onStartGame: { model.startGameTapped() },
                    onLeaveLobby: { model.leaveLobbyTapped() }
                )
                .navigationTitle("Host Lobby")

            case .join:
                JoinLobbyView(
                    gameId: model.gameSettings.gameId,
                    lobbies: model.discoveredLobbies,
                    players: model.players,
                    readyPlayerIDs: model.readyPlayerIDs,
                    connectingLobby: model.connectingLobby,
                    connectAlert: model.connectAlert,
                    isReady: model.isReady,
                    onSelectLobby: { lobby in model.selectLobby(lobby) },
                    onToggleReady: { ready in model.setReady(ready) },
                    onLeaveLobby: { model.leaveLobbyTapped() }
                )
                .navigationTitle("Join Lobby")
            }
        }
        .task { await model.beginListening() }
        .onChange(of: model.displayName) { _, _ in
            model.persistDisplayName()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onEditProfile) {
                    Image(systemName: "person.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    PermissionsDashboardView(connectivity: connectivity)
                } label: {
                    Image(systemName: "shield.checkered")
                }
            }
        }
    }
}

// MARK: - Entry screen

struct EntryView: View {
    let displayName: String
    let nearbyCount: Int
    let onHost: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            Text("One For The Boys")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                Text(displayName)
                    .font(.title3.bold())
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

// MARK: - Host Game Selection

struct HostGameSelectView: View {
    let descriptors: [GameRegistry.AnyModuleDescriptor]
    let onSelect: (GameRegistry.AnyModuleDescriptor) -> Void
    let onCancel: () -> Void

    var body: some View {
        List {
            Section("Choose a game to host") {
                ForEach(descriptors, id: \.id) { desc in
                    Button {
                        onSelect(desc)
                    } label: {
                        HStack {
                            Image(systemName: desc.catalogEntry.iconSymbol)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(desc.catalogEntry.displayName)
                                    .font(.headline)
                                Text("Up to \(desc.catalogEntry.maxPlayers) players · \(desc.catalogEntry.difficultyLevel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Button("Back", role: .cancel, action: onCancel)
            }
        }
    }
}

// MARK: - Host Lobby

struct HostLobbyView: View {
    @Binding var gameSettings: LobbyGameSettings
    var descriptors: [GameRegistry.AnyModuleDescriptor]
    let players: [PlayerProfile]
    let readyPlayerIDs: Set<UUID>
    let localPlayerId: UUID
    let onToggleReady: (Bool) -> Void
    let onStartGame: () -> Void
    let onLeaveLobby: () -> Void
    @State private var settingsExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Host Lobby")
                    .font(.title2.bold())
                if let descriptor = selectedDescriptor {
                    Text("\(descriptor.catalogEntry.displayName) · \(settingsSummary)")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Text("Players in lobby: \(players.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            List {
                Section("Game") {
                    if let descriptor = selectedDescriptor {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(descriptor.catalogEntry.displayName)
                                .font(.headline)
                            Text("Up to \(descriptor.catalogEntry.maxPlayers) players · \(descriptor.catalogEntry.difficultyLevel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Unsupported game")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Players") {
                    if players.isEmpty {
                        Text("Waiting for players…")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(players) { p in
                            HStack {
                                AvatarView(config: p.avatar, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.username)
                                        .font(.subheadline)
                                    let stats = p.statsByGameId[gameSettings.gameId]
                                    let games = stats?.gamesPlayed ?? 0
                                    let wins = stats?.wins ?? 0
                                    Text("Games \(games) · Wins \(wins)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if readyPlayerIDs.contains(p.id) {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                } else {
                                    Image(systemName: "clock.badge.questionmark").foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("I'm ready", isOn: Binding(
                        get: { readyPlayerIDs.contains(localPlayerId) },
                        set: { onToggleReady($0) }
                    ))
                }

                Section {
                    DisclosureGroup(isExpanded: $settingsExpanded) {
                        SettingsHostView(gameSettings: $gameSettings)
                    } label: {
                        Text("Settings")
                    }
                }
            }
            .padding()

            VStack(spacing: 8) {
                Button("Start Game", action: onStartGame)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!canStart)
                    .opacity(canStart ? 1.0 : 0.5)

                Button("Leave Lobby", role: .destructive, action: onLeaveLobby)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    private var canStart: Bool {
        readyPlayerIDs.count == players.count
    }

    private var selectedDescriptor: GameRegistry.AnyModuleDescriptor? {
        descriptors.first(where: { $0.id == gameSettings.gameId })
    }

    private var settingsSummary: String {
        gameSettings.summaryDescription
    }
}

// MARK: - Join Lobby

struct JoinLobbyView: View {
    let gameId: GameID
    let lobbies: [ConnectivityManager.FoundLobby]
    let players: [PlayerProfile]
    let readyPlayerIDs: Set<UUID>
    let connectingLobby: ConnectivityManager.FoundLobby?
    let connectAlert: String?
    let isReady: Bool
    let onSelectLobby: (ConnectivityManager.FoundLobby) -> Void
    let onToggleReady: (Bool) -> Void
    let onLeaveLobby: () -> Void

    @State private var dotCount = 1
    @State private var showAlert = false
    @State private var isConnected = false

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Text("Join Lobby")
                    .font(.title2.bold())

                if !isConnected {
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
                }

                GroupBox("Players in current lobby") {
                    if players.isEmpty {
                        Text("Not joined yet, or waiting for host…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(players) { p in
                            HStack {
                                AvatarView(config: p.avatar, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.username)
                                        .font(.subheadline)
                                    let stats = p.statsByGameId[gameId]
                                    let games = stats?.gamesPlayed ?? 0
                                    let wins = stats?.wins ?? 0
                                    Text("Games \(games) · Wins \(wins)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if readyPlayerIDs.contains(p.id) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "clock.badge.questionmark")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                if isConnected {
                    Toggle("I'm ready", isOn: Binding(
                        get: { isReady },
                        set: { onToggleReady($0) }
                    ))
                    .toggleStyle(.switch)
                    .padding(.horizontal)
                }

                Spacer()

                Button("Leave Lobby", role: .destructive, action: onLeaveLobby)
                    .buttonStyle(.bordered)
                    .padding(.bottom)
            }

            if let connectingLobby {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Connecting to \(connectingLobby.hostName)'s game" + String(repeating: ".", count: dotCount))
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.7))
                )
                .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in
                    dotCount = dotCount % 3 + 1
                }
            }
        }
        .onChange(of: connectAlert) { _, newValue in
            showAlert = newValue != nil
        }
        .alert(connectAlert ?? "", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: players) { _, newValue in
            isConnected = !newValue.isEmpty
        }
    }
}

// MARK: - ViewModel

@MainActor
final class LobbyViewModel: ObservableObject {
    private let connectivity: ConnectivityManager
    private let profileStore: ProfileStore
    private var pollTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    @Published private(set) var localProfile: PlayerProfile
    private let onStartGameCallback: (@MainActor ([PlayerProfile], LobbyGameSettings, UUID, Bool, [String: UUID]) -> Void)?
    private var hostProfile: PlayerProfile?
    private var isHosting = false
    private var peerToPlayer: [String: UUID] = [:]

    @Published var screen: LobbyScreen = .entry
    @Published var displayName: String
    @Published var discoveredLobbies: [ConnectivityManager.FoundLobby] = []
    @Published var players: [PlayerProfile] = []
    @Published var gameSettings: LobbyGameSettings = LobbyGameSettings()
    @Published var connectingLobby: ConnectivityManager.FoundLobby?
    @Published var connectAlert: String?
    @Published var readyPlayerIDs: Set<UUID> = []

    init(connectivity: ConnectivityManager, localProfile: PlayerProfile, onStartGame: (@MainActor ([PlayerProfile], LobbyGameSettings, UUID, Bool, [String: UUID]) -> Void)?) {
        self.connectivity = connectivity
        self.profileStore = ProfileStore.shared
        self.localProfile = localProfile
        self.onStartGameCallback = onStartGame
        self.displayName = localProfile.username
    }

    func beginListening() async {
        await configureMessageHandler()
        await configureConnectionHandler()
    }

    func hostTapped() {
        screen = .hostSelect
    }

    func joinTapped() {
        isHosting = false
        screen = .join
        players = []
        readyPlayerIDs = []
        Task { await connectivity.startBrowsing() }
        startLobbyPolling()
    }

    func selectLobby(_ lobby: ConnectivityManager.FoundLobby) {
        connectAlert = nil
        connectingLobby = lobby
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled, self.connectingLobby != nil else { return }
            await MainActor.run {
                self.connectingLobby = nil
                self.connectAlert = "Cannot connect - timed out."
            }
        }
        Task { await connectivity.connect(to: lobby) }
    }

    func leaveLobbyTapped() {
        pollTask?.cancel()
        pollTask = nil
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        if !isHosting {
            Task {
                await connectivity.sendNetworkMessage(.leaveLobby(playerId: localProfile.id))
                try? await Task.sleep(nanoseconds: 200_000_000)
                await connectivity.stop()
            }
        } else {
            Task { await connectivity.stop() }
        }
        players.removeAll()
        readyPlayerIDs.removeAll()
        discoveredLobbies.removeAll()
        screen = .entry
        connectingLobby = nil
    }

    func cancelHostSelection() {
        screen = .entry
    }

    func selectGameToHost(_ descriptor: GameRegistry.AnyModuleDescriptor) {
        startHosting(with: descriptor.id)
    }

    private func startHosting(with gameId: GameID) {
        isHosting = true
        localProfile.username = displayName
        hostProfile = localProfile
        players = [localProfile]
        gameSettings = LobbyGameSettings(gameId: gameId)
        readyPlayerIDs = []
        screen = .host
        Task { await connectivity.startHosting(playerCount: players.count, hostName: displayName) }
        startLobbyPolling()
    }

    func persistDisplayName() {
        localProfile.username = displayName
        Task { await profileStore.save(localProfile) }
    }

    func replaceLocalProfile(_ profile: PlayerProfile) {
        localProfile = profile
        displayName = profile.username
        if let idx = players.firstIndex(where: { $0.id == profile.id }) {
            players[idx] = profile
        }
        if hostProfile?.id == profile.id {
            hostProfile = profile
        }
        if isHosting {
            Task {
                let info = await makeLobbyInfo()
                await connectivity.sendNetworkMessage(.lobbyUpdate(info))
            }
        }
    }

    func startGameTapped() {
        guard isHosting else { return }
        // Allow solo starts; just require everyone marked ready.
        guard readyPlayerIDs.count == players.count, players.count >= 1 else { return }
        Task {
            let info = await makeLobbyInfo(isStarting: true)
            await connectivity.sendNetworkMessage(.lobbyUpdate(info))
        }
        onStartGameCallback?(players, gameSettings, hostProfile?.id ?? localProfile.id, isHosting, peerToPlayer)
    }

    var isReady: Bool {
        readyPlayerIDs.contains(localProfile.id)
    }

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
        await connectivity.setOnMessageHandler { [weak self] message, peer in
            guard let self else { return }
            Task { @MainActor in
                switch message {
                case .joinRequest(let profile, _, _):
                    guard self.isHosting else { break }
                    self.peerToPlayer[peer.displayName] = profile.id
                    if !self.players.contains(where: { $0.id == profile.id }) {
                        self.players.append(profile)
                        await self.connectivity.updateHostedLobbyPlayerCount(self.players.count)
                    }
                    self.readyPlayerIDs.remove(profile.id)
                    Task {
                        let info = await self.makeLobbyInfo()
                        await self.connectivity.sendNetworkMessage(.joinAccepted(info))
                        await self.connectivity.sendNetworkMessage(.lobbyUpdate(info))
                    }
                case .joinAccepted(let lobby):
                    self.players = lobby.playerProfiles
                    self.connectingLobby = nil
                    self.connectTimeoutTask?.cancel()
                    self.readyPlayerIDs = lobby.readyPlayerIDs
                    self.hostProfile = lobby.hostProfile
                    if let data = lobby.activeSettings,
                       let decoded = try? JSONDecoder().decode(LobbyGameSettings.self, from: data) {
                        self.gameSettings = decoded
                    }
                    self.gameSettings.gameId = lobby.gameId
                    if !self.isHosting {
                        self.pollTask?.cancel()
                        self.discoveredLobbies.removeAll()
                    }
                    if lobby.isStarting == true {
                        self.onStartGameCallback?(lobby.playerProfiles, self.gameSettings, lobby.hostProfile.id, self.isHosting, self.peerToPlayer)
                    }
                case .joinRejected:
                    self.players.removeAll()
                    self.connectingLobby = nil
                    self.connectAlert = "Cannot connect - rejected."
                case .lobbyUpdate(let lobby):
                    self.players = lobby.playerProfiles
                    self.readyPlayerIDs = lobby.readyPlayerIDs
                    self.hostProfile = lobby.hostProfile
                    if let data = lobby.activeSettings,
                       let decoded = try? JSONDecoder().decode(LobbyGameSettings.self, from: data) {
                        self.gameSettings = decoded
                    }
                    self.gameSettings.gameId = lobby.gameId
                    self.connectingLobby = nil
                    self.connectTimeoutTask?.cancel()
                    if !self.isHosting {
                        self.pollTask?.cancel()
                        self.discoveredLobbies.removeAll()
                    }
                    if lobby.isStarting == true {
                        self.onStartGameCallback?(lobby.playerProfiles, self.gameSettings, lobby.hostProfile.id, self.isHosting, self.peerToPlayer)
                    }
                case .leaveLobby(let pid):
                    guard self.isHosting else { break }
                    if let idx = self.players.firstIndex(where: { $0.id == pid }) {
                        self.players.remove(at: idx)
                        self.readyPlayerIDs.remove(pid)
                        self.peerToPlayer = self.peerToPlayer.filter { $0.value != pid }
                        Task {
                            let info = await self.makeLobbyInfo()
                            await self.connectivity.sendNetworkMessage(.lobbyUpdate(info))
                            await self.connectivity.updateHostedLobbyPlayerCount(self.players.count)
                        }
                    }
                case .playerReady(let pid, let isReady):
                    guard self.isHosting else { break }
                    if isReady {
                        self.readyPlayerIDs.insert(pid)
                    } else {
                        self.readyPlayerIDs.remove(pid)
                    }
                    Task {
                        let info = await self.makeLobbyInfo()
                        await self.connectivity.sendNetworkMessage(.lobbyUpdate(info))
                    }
                default:
                    break
                }
            }
        }
    }

    private func configureConnectionHandler() async {
        await connectivity.setOnPeerConnectedHandler { [weak self] _ in
            guard let self, !self.isHosting else { return }
            let join = NetworkMessage.joinRequest(
                profile: self.localProfile,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0",
                passcodeHash: nil
            )
            Task { await self.connectivity.sendNetworkMessage(join) }
        }

        await connectivity.setOnPeerDisconnectedHandler { [weak self] peer in
            guard let self, self.isHosting else { return }
            if let pid = self.peerToPlayer[peer.displayName],
               let idx = self.players.firstIndex(where: { $0.id == pid }) {
                Task { @MainActor in
                    self.players.remove(at: idx)
                    self.readyPlayerIDs.remove(pid)
                    self.peerToPlayer.removeValue(forKey: peer.displayName)
                    Task {
                        let info = await self.makeLobbyInfo()
                        await self.connectivity.sendNetworkMessage(.lobbyUpdate(info))
                        await self.connectivity.updateHostedLobbyPlayerCount(self.players.count)
                    }
                }
            }
        }
    }

    private func makeLobbyInfo(isStarting: Bool = false) async -> LobbyInfo {
        let encodedSettings = try? JSONEncoder().encode(gameSettings)
        return LobbyInfo(
            id: await connectivity.currentLobbyId ?? "----",
            gameId: gameSettings.gameId,
            hostProfile: hostProfile ?? localProfile,
            playerProfiles: players,
            readyPlayerIDs: readyPlayerIDs,
            isPrivate: false,
            passcodeHash: nil,
            activeSettings: encodedSettings,
            isStarting: isStarting
        )
    }

    func setReady(_ ready: Bool) {
        if ready {
            readyPlayerIDs.insert(localProfile.id)
        } else {
            readyPlayerIDs.remove(localProfile.id)
        }

        if isHosting {
            Task {
                let info = await makeLobbyInfo()
                await connectivity.sendNetworkMessage(.lobbyUpdate(info))
            }
        } else {
            Task {
                await connectivity.sendNetworkMessage(.playerReady(playerId: localProfile.id, isReady: ready))
            }
        }
    }
}
