import SwiftUI
import OFTBShared

struct ProfileEditorView: View {
    @State private var workingProfile: PlayerProfile
    let onSave: (PlayerProfile) -> Void
    let onCancel: () -> Void

    private let baseSymbols = ["person.fill", "person.circle.fill", "figure.wave"]
    private let backgroundColors = ["#222222", "#0F172A", "#1E293B", "#334155", "#475569", "#64748B"]

    init(profile: PlayerProfile, onSave: @escaping (PlayerProfile) -> Void, onCancel: @escaping () -> Void) {
        _workingProfile = State(initialValue: profile)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $workingProfile.username)
                        .textInputAutocapitalization(.words)
                }

                Section("Avatar") {
                    HStack {
                        Spacer()
                        AvatarView(config: workingProfile.avatar, size: 72)
                        Spacer()
                    }

                    Picker("Base Symbol", selection: $workingProfile.avatar.baseSymbol) {
                        ForEach(baseSymbols, id: \.self) { symbol in
                            Label(symbol, systemImage: symbol).tag(symbol)
                        }
                    }

                    Picker("Background", selection: $workingProfile.avatar.backgroundColorHex) {
                        ForEach(backgroundColors, id: \.self) { hex in
                            HStack {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 18, height: 18)
                                Text(hex)
                            }
                            .tag(hex)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Spacer()
                                Text("Overall")
                                    .font(.headline)
                                Spacer()
                            }
                            HStack {
                                statPill(title: "Games", value: "\(workingProfile.globalStats.totalGamesPlayed)")
                                Spacer()
                                statPill(title: "Wins", value: "\(workingProfile.globalStats.totalWins)")
                                Spacer()
                                let winPct = winPercentage(total: workingProfile.globalStats.totalGamesPlayed, wins: workingProfile.globalStats.totalWins)
                                statPill(title: "Win %", value: winPct)
                            }
                        }

                        Divider().padding(.vertical, 4)
                        ForEach(GameID.allCases, id: \.self) { key in
                            let stats = workingProfile.statsByGameId[key] ?? GameStats(gamesPlayed: 0, wins: 0, streakCurrent: 0, streakBest: 0)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Spacer()
                                    Text(key.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                }
                                HStack(spacing: 8) {
                                    Spacer()
                                    statPill(title: "Games", value: "\(stats.gamesPlayed)")
                                    statPill(title: "Wins", value: "\(stats.wins)")
                                    statPill(title: "Best Streak", value: "\(stats.streakBest)")
                                    let winPct = winPercentage(total: stats.gamesPlayed, wins: stats.wins)
                                    statPill(title: "Win %", value: winPct)
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 4)
                            Divider().padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Stats")
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(workingProfile) }
                        .disabled(workingProfile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

extension ProfileEditorView {
    @ViewBuilder
    private func statPill(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func winPercentage(total: Int, wins: Int) -> String {
        guard total > 0 else { return "0%" }
        let pct = Double(wins) / Double(total) * 100.0
        return String(format: "%.0f%%", pct)
    }
}
