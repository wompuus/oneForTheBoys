import Foundation
import SwiftUI
import OFTBShared

public struct CrazyEightsGameModule: GameModule {
    private static let registerOnce: Void = {
        Task { @MainActor in
            GameRegistry.shared.register(CrazyEightsGameModule.self)
        }
    }()

    public static var id: GameID {
        registerOnce
        return .crazyEights
    }

    public static var catalogEntry: GameCatalogEntry {
        GameCatalogEntry(
            id: id,
            displayName: "Crazy Eights",
            iconSymbol: "circle.grid.3x3.fill",
            maxPlayers: 8,
            difficultyLevel: "Easy"
        )
    }

    public static var policy: GamePolicy {
        GamePolicy(
            minPlayers: 2,
            maxPlayers: 8,
            isTurnBased: true,
            allowsRejoin: false,
            supportsSpectators: false
        )
    }

    public static var reducer: (CrazyEightsGameState, CrazyEightsAction, Bool) -> CrazyEightsGameState = {
        state, action, isHost in
        CrazyEightsEngine.reducer(state: state, action: action, isHost: isHost)
    }

    public static func initialState(players: [PlayerProfile], settings: CrazyEightsSettings) -> CrazyEightsGameState {
        let cePlayers = players.map { profile in
            CrazyEightsPlayer(id: profile.id, name: profile.username, deviceName: "", hand: [], avatar: profile.avatar)
        }
        return CrazyEightsEngine.initialState(players: cePlayers, settings: settings)
    }

    public static func isGameOver(state: CrazyEightsGameState) -> Bool {
        CrazyEightsEngine.isGameOver(state: state)
    }

    @MainActor
    static func makeView(store: GameStore<CrazyEightsGameState, CrazyEightsAction>) -> AnyView {
        let localId = store.localPlayerId ?? store.state.hostId ?? store.state.players.first?.id ?? UUID()
        return AnyView(CrazyEightsGameView(store: store, localPlayerId: localId))
    }

    @MainActor
    public static func makeResultsView(state: CrazyEightsGameState, players: [PlayerProfile], localPlayerId: UUID) -> AnyView {
        AnyView(EmptyView())
    }

    @MainActor
    public static func makeSettingsView(binding: Binding<CrazyEightsSettings>) -> AnyView {
        AnyView(CrazyEightsSettingsView(settings: binding))
    }

    @MainActor
    public static func makeRulesView() -> AnyView {
        AnyView(EmptyView())
    }

    public static func defaultSettings() -> CrazyEightsSettings {
        CrazyEightsSettings()
    }

    public static func leaveAction(for playerId: UUID) -> CrazyEightsAction? {
        .leave(playerId: playerId)
    }
}
