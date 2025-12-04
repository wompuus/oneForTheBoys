import SwiftUI
import OFTBShared

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

    /// Optional hook for a module-specific leave action. Default returns nil.
    static func leaveAction(for playerId: UUID) -> Action?
}

extension GameModule {
    static func leaveAction(for playerId: UUID) -> Action? { nil }
}
