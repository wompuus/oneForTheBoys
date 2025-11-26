import SwiftUI

/// Type-erased game session to allow app/lobby code to work with any registered game.
final class AnyGameSession {
    let gameId: GameID
    let gameView: AnyView
    let resultsView: ([PlayerProfile], UUID) -> AnyView
    let registerWithRouter: (GameTransportRouter) -> Void
    let encodeSettings: () -> Data?
    let encodeState: () -> Data?
    let onLeave: (UUID) -> Void
    let isHost: Bool

    init(
        gameId: GameID,
        gameView: AnyView,
        resultsView: @escaping ([PlayerProfile], UUID) -> AnyView,
        registerWithRouter: @escaping (GameTransportRouter) -> Void,
        encodeSettings: @escaping () -> Data?,
        encodeState: @escaping () -> Data?,
        onLeave: @escaping (UUID) -> Void,
        isHost: Bool
    ) {
        self.gameId = gameId
        self.gameView = gameView
        self.resultsView = resultsView
        self.registerWithRouter = registerWithRouter
        self.encodeSettings = encodeSettings
        self.encodeState = encodeState
        self.onLeave = onLeave
        self.isHost = isHost
    }
}

extension GameModule {
    /// Builds a type-erased session for this module, wiring in transport and router registration.
    @MainActor
    static func makeAnySession(players: [PlayerProfile],
                               settings: Settings,
                               transport: GameTransport,
                               isHost: Bool,
                               localPlayerId: UUID) -> AnyGameSession {
        let store = GameStore(
            initialState: Self.initialState(players: players, settings: settings),
            transport: transport,
            reducer: Self.reducer,
            isHost: isHost
        )
        store.setLocalPlayerId(localPlayerId)

        let session = AnyGameSession(
            gameId: Self.id,
            gameView: Self.makeView(store: store),
            resultsView: { statePlayers, localId in
                Self.makeResultsView(state: store.state, players: statePlayers, localPlayerId: localId)
            },
            registerWithRouter: { router in
                router.register(store: store, module: Self.self)
            },
            encodeSettings: { try? JSONEncoder().encode(settings) },
            encodeState: { try? JSONEncoder().encode(store.state) },
            onLeave: { pid in
                if let action = Self.leaveAction(for: pid) {
                    store.send(action)
                }
            },
            isHost: isHost
        )
        return session
    }
}
