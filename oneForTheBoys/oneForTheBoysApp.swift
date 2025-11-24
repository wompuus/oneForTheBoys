import SwiftUI
import UIKit

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

struct AppRootView: View {
    private let connectivity: ConnectivityManager
    @StateObject private var store: GameStore<CrazyEightsGameState, CrazyEightsAction>
    @State private var localProfile: PlayerProfile
    @State private var screen: AppScreen = .lobby

    init() {
        let connectivity = ConnectivityManager()
        let profile = PlayerProfile(
            id: UUID(),
            username: UIDevice.current.name,
            avatar: AvatarConfig(
                baseSymbol: "person.fill",
                skinColorHex: "#F5E0C3",
                hairSymbol: nil,
                hairColorHex: "#000000",
                accessorySymbol: nil,
                backgroundColorHex: "#222222"
            ),
            globalStats: GlobalStats(totalGamesPlayed: 0, totalWins: 0),
            statsByGameId: [:],
            ownedProductIDs: []
        )

        let settings = CrazyEightsGameModule.defaultSettings()
        var initialState = CrazyEightsGameModule.initialState(players: [profile], settings: settings)
        initialState.hostId = profile.id
        connectivity.setActiveGame(.crazyEights)

        _store = StateObject(
            wrappedValue: GameStore(
                initialState: initialState,
                transport: connectivity,
                reducer: CrazyEightsGameModule.reducer,
                isHost: true
            )
        )
        _localProfile = State(initialValue: profile)
        self.connectivity = connectivity
    }

    var body: some View {
        NavigationStack {
            switch screen {
            case .lobby:
                VStack(spacing: 16) {
                    Text("Crazy Eights Lobby")
                        .font(.title2.bold())
                    Button("Start Game") {
                        screen = .game
                        store.send(.startRound)
                    }
                }
                .navigationTitle("OneForTheBoys")

            case .game:
                CrazyEightsGameModule
                    .makeView(store: store)
                    .navigationBarBackButtonHidden(true)
            }
        }
    }
}
