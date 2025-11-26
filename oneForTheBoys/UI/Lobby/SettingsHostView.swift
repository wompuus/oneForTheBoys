import SwiftUI

struct SettingsHostView: View {
    @Binding var gameSettings: LobbyGameSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let descriptor = GameRegistry.shared.descriptor(for: gameSettings.gameId) {
                descriptor.makeSettingsView(settingsDataBinding)
            } else {
                Text("Unsupported game settings")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var settingsDataBinding: Binding<Data> {
        Binding<Data>(
            get: {
                switch gameSettings.gameId {
                case .crazyEights:
                    return (try? JSONEncoder().encode(gameSettings.crazyEights)) ?? Data()
                }
            },
            set: { newData in
                switch gameSettings.gameId {
                case .crazyEights:
                    if let decoded = try? JSONDecoder().decode(CrazyEightsSettings.self, from: newData) {
                        gameSettings.crazyEights = decoded
                    }
                }
            }
        )
    }
}
