import Foundation
import OFTBShared

/// Routes networked game messages to the correct registered game store in a game-agnostic way.
/// Register each game module + store, then call `activate()` to bind to ConnectivityManager's onMessage handler.
final class GameTransportRouter {
    private let connectivity: ConnectivityManager
    private var handlers: [GameID: AnyHandler] = [:]
    private let decoder = JSONDecoder()
    private var activeGameId: GameID?
    var onHostLeft: ((String) -> Void)?
    private var hasActivated = false

    init(connectivity: ConnectivityManager) {
        self.connectivity = connectivity
    }

    /// Call once after registration to begin handling incoming messages and peer events.
    func activate() async {
        if hasActivated { return }
        hasActivated = true
        await connectivity.addOnMessageHandler { [weak self] message, _ in
            self?.handle(message)
        }
        await connectivity.addOnPeerConnectedHandler { [weak self] _ in
            self?.broadcastStateIfHost()
        }
        await connectivity.addOnPeerDisconnectedHandler { [weak self] _ in
            self?.broadcastStateIfHost()
        }
    }

    /// Register a module/store pair for routing.
    func register<T: GameModule>(store: GameStore<T.State, T.Action>, module: T.Type) {
        activeGameId = T.id
        print("[Router] Registering handlers for \(T.id)")
        handlers[T.id] = AnyHandler(
            onAction: { [weak store] data in
                guard let store else { return }
                guard let action = try? self.decoder.decode(T.Action.self, from: data) else { return }
                Task { @MainActor in
                    print("[Router] onAction \(T.id) isHost=\(store.isHost)")
                    let newState = T.reducer(store.state, action, store.isHost)
                    store.updateState(newState)
                    if store.isHost {
                        await self.connectivity.broadcast(newState)
                    }
                    await self.creditIfNeeded(state: newState, store: store, gameId: T.id)
                }
            },
            onState: { [weak store] data in
                guard let store else { return }
                guard let state = try? self.decoder.decode(T.State.self, from: data) else { return }
                Task { @MainActor in
                    print("[Router] onState \(T.id)")
                    store.updateState(state)
                    await self.creditIfNeeded(state: state, store: store, gameId: T.id)
                }
            },
            onStateRequest: { [weak store] in
                Task { @MainActor in
                    guard let store, store.isHost else { return }
                    let state = store.state
                    Task {
                        print("[Router] onStateRequest broadcast \(T.id)")
                        await self.connectivity.broadcast(state)
                    }
                }
            }
        )
        Task { @MainActor in
            guard store.isHost else { return }
            let state = store.state
            Task {
                print("[Router] Initial broadcast for \(T.id)")
                await connectivity.broadcast(state)
            }
        }
    }

    private func handle(_ message: NetworkMessage) {
        switch message {
        case .gameAction(let gameId, let payload):
            handlers[gameId]?.onAction(payload)
        case .gameState(let gameId, let payload):
            handlers[gameId]?.onState(payload)
        case .gameStateRequest(let gameId):
            handlers[gameId]?.onStateRequest()
        case .hostLeft(_, let reason):
            onHostLeft?(reason)
        case .crazyEightsClient(let ceMessage):
            handleCrazyEightsClientMessage(ceMessage)
        case .crazyEightsServer(let ceMessage):
            handleCrazyEightsServerMessage(ceMessage)
        default:
            break
        }
    }

    private func handleCrazyEightsClientMessage(_ message: CrazyEightsClientMessage) {
        guard let handler = handlers[.crazyEights] else { return }
        switch message {
        case .joinRoom:
            break // handled elsewhere for P2P; server will use this.
        case .sendAction(_, _, let action):
            guard let data = try? JSONEncoder().encode(action) else { return }
            handler.onAction(data)
        case .createRoom:
            break
        case .requestRoomList:
            break
        case .readyUpdate:
            break
        }
    }

    private func handleCrazyEightsServerMessage(_ message: CrazyEightsServerMessage) {
        guard let handler = handlers[.crazyEights] else { return }
        switch message {
        case .roomJoined(_, _, let state):
            guard let data = try? JSONEncoder().encode(state) else { return }
            handler.onState(data)
        case .stateUpdated(let state):
            guard let data = try? JSONEncoder().encode(state) else { return }
            handler.onState(data)
        case .error:
            break
        case .roomList:
            break
        case .readySnapshot:
            break
        }
    }

    private func broadcastStateIfHost() {
        // Hosts rebroadcast current state to help new/reconnecting peers.
        guard let activeGameId, let handler = handlers[activeGameId] else { return }
        handler.onStateRequest()
    }

    private func creditIfNeeded<T, A>(state: T, store: GameStore<T, A>, gameId: GameID) async {
        if gameId == .crazyEights, let ceState = state as? CrazyEightsGameState {
            await StatsTracker.shared.creditCrazyEights(state: ceState, localPlayerId: store.localPlayerId)
        } else if gameId == .darts, let dartsState = state as? DartsGameState {
            await StatsTracker.shared.creditDarts(state: dartsState, localPlayerId: store.localPlayerId)
        }
    }
}

private struct AnyHandler {
    let onAction: (Data) -> Void
    let onState: (Data) -> Void
    let onStateRequest: () -> Void
}
