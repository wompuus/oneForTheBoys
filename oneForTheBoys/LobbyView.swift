import SwiftUI

// MARK: - Entry screen (name + host/join)

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

// MARK: - Host Lobby (settings + players + Start button)

struct HostLobbyView: View {
    @Binding var config: GameConfig
    let players: [Player]

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
                            Text(p.name)
                        }
                    }
                }

                Section("Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            Stepper("Starting cards: \(config.startingHandCount)",
                                    value: $config.startingHandCount,
                                    in: 1...50)

                            Stepper("Skips per color: \(config.skipPerColor)",
                                    value: $config.skipPerColor,
                                    in: 0...50)

                            Stepper("Reverses per color: \(config.reversePerColor)",
                                    value: $config.reversePerColor,
                                    in: 0...50)

                            Stepper("+2 per color: \(config.draw2PerColor)",
                                    value: $config.draw2PerColor,
                                    in: 0...50)

                            Stepper("Wild count: \(config.wildCount)",
                                    value: $config.wildCount,
                                    in: 0...50)

                            Stepper("Wild+4 count: \(config.wildDraw4Count)",
                                    value: $config.wildDraw4Count,
                                    in: 0...50)
                        }

                        Divider()

                        Toggle("Allow stacking draws", isOn: $config.allowStackDraws)
                        Toggle("Allow mixed stacking (+2 on +4)",
                               isOn: $config.allowMixedDrawStacking)
                            .disabled(!config.allowStackDraws)

//                        Toggle("UNO penalty enabled",
//                               isOn: $config.unoPenaltyEnabled)
//                        Stepper("UNO penalty cards: \(config.unoPenaltyCards)",
//                                value: $config.unoPenaltyCards,
//                                in: 1...20)

                        Toggle("Shot Caller UNO", isOn: $config.shotCallerEnabled)
                        Toggle("THE BOMB", isOn: $config.bombEnabled)
                        Stepper("Bomb draw per opponent: \(config.bombDrawCount)",
                                value: $config.bombDrawCount,
                                in: 1...10)

                        Toggle("Allow join in progress", isOn: $config.allowJoinInProgress)
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

// MARK: - Join Lobby (lobby browser + waiting view)

struct JoinLobbyView: View {
    @ObservedObject var mpc: MPCService
    let players: [Player]
    let onSelectLobby: (FoundLobby) -> Void
    let onLeaveLobby: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Join Lobby")
                .font(.title2.bold())

            // Available game sessions discovered nearby
            GroupBox("Available Games") {
                if mpc.discoveredLobbies.isEmpty {
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
                        ForEach(mpc.discoveredLobbies) { lobby in
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

            // Once connected + HELLO processed, players show up here
            GroupBox("Players in current lobby") {
                if players.isEmpty {
                    Text("Not joined yet, or waiting for host…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(players) { p in
                        Text(p.name)
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
