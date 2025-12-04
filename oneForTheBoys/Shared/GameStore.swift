import Foundation
import Combine
import OFTBShared

@MainActor
final class GameStore<State: Codable & Equatable, Action: Codable>: ObservableObject {
    @Published private(set) var state: State

    private let transport: GameTransport
    private let reducer: (State, Action, Bool) -> State // Injected Reducer

    var isHost: Bool
    let allowsOptimisticUI: Bool
    private(set) var localPlayerId: UUID?

    init(initialState: State,
         transport: GameTransport,
         reducer: @escaping (State, Action, Bool) -> State,
         isHost: Bool,
         allowsOptimisticUI: Bool = true) {
        self.state = initialState
        self.transport = transport
        self.reducer = reducer
        self.isHost = isHost
        self.allowsOptimisticUI = allowsOptimisticUI
    }

    func send(_ action: Action) {
        // 1. Optimistic Update (Client Side) or Authoritative Update (Host Side)
        if isHost || allowsOptimisticUI {
            self.state = reducer(state, action, isHost)
            if isHost {
                Task { await transport.broadcast(state) }
            }
        }

        // 2. Transport
        Task {
            await transport.send(action)
        }
    }

    func updateState(_ newState: State) {
        // Called when network state arrives (Source of Truth)
        self.state = newState
    }

    func setHost(_ isHost: Bool) {
        self.isHost = isHost
    }

    func setLocalPlayerId(_ id: UUID) {
        self.localPlayerId = id
    }
}
