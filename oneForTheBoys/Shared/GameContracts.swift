import SwiftUI

enum GameID: String, Codable, CaseIterable {
    case crazyEights
    // case highCard (future)
}

struct GameCatalogEntry {
    let id: GameID
    let displayName: String
    let iconSymbol: String
    let maxPlayers: Int
    let difficultyLevel: String // e.g., "Easy", "Medium"
}

struct GamePolicy {
    let minPlayers: Int
    let maxPlayers: Int
    let isTurnBased: Bool
    let allowsRejoin: Bool
    let supportsSpectators: Bool
}

// Future-proofing for V2
enum TransportMode {
    case p2p
    case hybrid
}

protocol GameModule {
    associatedtype State: Codable & Equatable
    associatedtype Action: Codable
    associatedtype Settings: Codable & Hashable

    static var id: GameID { get }
    static var catalogEntry: GameCatalogEntry { get } // Metadata
    static var policy: GamePolicy { get }

    // --- Logic ---
    // The Reducer must be PURE and DETERMINISTIC (unless explicitly documented otherwise).
    // Exposed statically for injection into GameStore.
    static var reducer: (State, Action, Bool) -> State { get }

    static func initialState(players: [PlayerProfile], settings: Settings) -> State
    static func isGameOver(state: State) -> Bool

    // --- UI Factory ---
    @MainActor
    static func makeView(store: GameStore<State, Action>) -> AnyView

    // Receives full player list for contextual stat/name display
    @MainActor
    static func makeResultsView(state: State, players: [PlayerProfile], localPlayerId: UUID) -> AnyView

    @MainActor
    static func makeSettingsView(binding: Binding<Settings>) -> AnyView

    @MainActor
    static func makeRulesView() -> AnyView

    // --- Registry ---
    static func defaultSettings() -> Settings
}

protocol GameTransport {
    func send<A: Codable>(_ action: A) async
    func broadcast<S: Codable>(_ state: S) async
}
