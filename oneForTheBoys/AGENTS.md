OneForTheBoys – Project Overview

## 1. Vision

OneForTheBoys is a master iOS app that hosts a collection of fast, offline, peer-to-peer multiplayer games designed for break rooms.

Core Principles:

iPhone Only: iOS 16+ (Portrait mode primary). Must support iPhone SE resolution.

Local Progression: No cloud backend required for V1. Rich local player profiles with avatars, detailed stats, and unlockables sync via P2P and persist via iCloud Key-Value Store.

Offline First: Primary transport is peer-to-peer (MultipeerConnectivity). Architecture allows for a future "Hybrid Mode" (Server/Cellular) without rewriting game logic.

Instant Fun: Playable within 10 seconds of launch.

Respect the User: No Ads, No Subscriptions, No Energy Systems. Monetization is strictly cosmetic (skins).

Modular: One shared connectivity backbone, policy layer, and profile system reused across all games.

The flagship game is Crazy Eights (an Uno-like shedding game), but the architecture is built to support multiple future modules (High Card, Dice, etc.).

## 2. Tech Stack & Constraints

Language: Swift 5+

UI: SwiftUI

Concurrency: Swift Structured Concurrency (async/await, Actors) — Avoid GCD/Closures where possible.

Networking: MultipeerConnectivity wrapped in an Actor.

Constraint: Network payloads must remain under 1MB compressed.

Compatibility: New fields in NetworkMessage must be optional/defaultable so older clients do not crash.

Persistence:

Files: JSON in Documents for complex objects.

Sync: NSUbiquitousKeyValueStore (iCloud KVS) for "Zero-Config" profile backup.

Assets:

Bundled Binary: All cosmetic assets are included in the app binary.

Style: SF Symbols ONLY for V1. Rendered via a layered system.

Haptics/Audio: Standardized via HapticManager.

Versioning: Semantic Versioning (major.minor.patch) required for backward compatibility checks.

Target: iOS 16+

## 3. High-Level Architecture

Modules

AppShell: App entry, root navigation, global styling.

Responsibility: Includes a Permissions Dashboard that actively checks LocalNetwork authorization.

Connectivity: The shared backbone. Handles discovery, session lifecycle, and data transport.

Games: Isolated modules. Each game contains its own logic, views, and rules, adhering to GameModule.

Profiles: Persistent identity (Name/Avatar) + Win tracking + Cosmetics.

UI: Reusable interface components (Spotlight, PlayerSeat, CardView).

Shared: Contracts, Extensions, Managers (Haptics, Store, Logging, Viral).

Folder Layout

OneForTheBoys/
  App/
    OneForTheBoysApp.swift
    AppRouter.swift
    PermissionsView.swift
  Connectivity/
    ConnectivityManager.swift
    GameRegistry.swift
    NetworkPayloads.swift
  Profiles/
    PlayerProfile.swift
    AvatarConfig.swift
    AvatarView.swift
    ProfileStore.swift
  Games/
    _Common/          // Shared Game Assets (Decks, Piles, Timers)
    CrazyEights/
      CrazyEightsGameModule.swift
      CrazyEightsGameState.swift
      CrazyEightsAction.swift
      CrazyEightsGameView.swift
      CrazyEightsSettings.swift
  UI/
    Common/
    Lobby/
    Results/
  Shared/
    Managers/
      HapticManager.swift
      StoreManager.swift
      ViralManager.swift
    GameContracts.swift
    GameStore.swift
    Theme.swift
    AnimationUtils.swift
    GameError.swift   // Standardized Error Enum


## 4. Policy-Based Game Architecture

Games plug into the system through a shared Protocol-Oriented Design.

### 4.1 Game Identity & Metadata

enum GameID: String, Codable, CaseIterable {
    case crazyEights
    // case highCard (future)
}

// Metadata for Game Selection Screen
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


### 4.2 Game Lifecycle & Disconnects

Settings Snapshot: Each game defines a Settings struct.

Versioning: Settings must include a settingsVersion: Int to prevent mismatched rule schemas across app versions.

Storage: The active snapshot is stored in LobbyInfo.activeSettings (as Data).

Timing: Snapshot is updated when Host changes settings in Lobby, and locked when Host presses "Start Game."

End of Game:

When isGameOver(state) returns true, the view transitions to the Results View defined by the module.

Host Actions: "Play Again" resets state using the locked snapshot settings.

Host Disconnect: 5-second Grace Period. If failed, session terminates.

Client Leave/Background:

Tapping "Back" triggers a confirmation.

Background Timeout: If a player app is backgrounded for > 30 seconds, they are considered disconnected and removed from the session.

### 4.3 GameModule Contract

import SwiftUI

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


## 5. Game Runtime (GameStore)

To ensure thread safety and strict authority, all games use GameStore.

@MainActor
final class GameStore<State: Codable & Equatable, Action: Codable>: ObservableObject {
    @Published private(set) var state: State
    
    private let transport: GameTransport
    private let reducer: (State, Action, Bool) -> State // Injected Reducer
    
    let isHost: Bool
    let allowsOptimisticUI: Bool
    
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
}


Authority Rule: The Host is authoritative. Clients may perform optimistic updates via the injected reducer, but the Host's broadcasted State is the source of truth and will overwrite client state upon receipt.

## 6. Connectivity Backbone

### 6.1 Network Messages

struct LobbyInfo: Codable, Equatable {
    var id: String
    var gameId: GameID
    var hostProfile: PlayerProfile
    var playerProfiles: [PlayerProfile]
    var readyPlayerIDs: Set<UUID>
    var isPrivate: Bool 
    var passcodeHash: String? 
    var activeSettings: Data? // Snapshot of GameSettings
}

enum NetworkMessage: Codable {
    // Lobby Phase
    case lobbyUpdate(LobbyInfo)
    case joinRequest(profile: PlayerProfile, appVersion: String, passcodeHash: String?)
    case joinAccepted(LobbyInfo)
    case joinRejected(reason: String)
    case kickPlayer(playerId: UUID, reason: String?)

    // Game Phase
    case gameAction(gameId: GameID, payload: Data)
    case gameState(gameId: GameID, payload: Data)
}


Forward Compatibility: Network messages must handle decoding failures gracefully. New fields added in future versions must be optional (?) so older clients do not crash when decoding payloads from newer hosts.

### 6.2 Debugging Support

GameError Enum: A shared enum GameError: Error, Codable must be defined to standardize debugging. Cases include: .invalidAction, .desync, .corruptedPayload, .versionMismatch.

### 6.3 Transport Protocol

protocol GameTransport {
    func send<A: Codable>(_ action: A) async
    func broadcast<S: Codable>(_ state: S) async
}


### 6.4 Game Registry & Version Safety

class GameRegistry {
    static let shared = GameRegistry()
    // Dictionary of [GameID: GameDescriptor]
    
    func register<T: GameModule>(_ module: T.Type) { ... }
}


Safety Rule: If a Host initiates a game (e.g., "HighCard") that the Client does not have registered (e.g., older app version), the Client must reject the LobbyInfo update or joinRequest with reason: "Unsupported Game Version".

## 7. Player Profiles & Persistence

### 7.1 Data Strategy

Primary: Documents/userProfile.json.

Sync: iCloud KVS for backup.

### 7.2 Profile Structure

struct GlobalStats: Codable, Hashable {
    var totalGamesPlayed: Int
    var totalWins: Int
}

struct GameStats: Codable, Hashable {
    var gamesPlayed: Int
    var wins: Int
    var streakCurrent: Int
    var streakBest: Int
}

struct AvatarConfig: Codable, Hashable {
    var version: Int = 1 // Schema version for migration
    var baseSymbol: String
    var skinColorHex: String
    var hairSymbol: String?
    var hairColorHex: String
    var accessorySymbol: String?
    var backgroundColorHex: String
}

struct PlayerProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var username: String
    var avatar: AvatarConfig
    var globalStats: GlobalStats
    var statsByGameId: [GameID: GameStats]
    var ownedProductIDs: Set<String> 
}


## 8. Shared Managers

### 8.1 StoreManager (V1 Stub)

Purpose: Product lookup/verification only.

### 8.2 ViralManager

Responsibility: * Generate QR Codes for App Store links.

Handle AirDrop sharing of the App Store link.

Trigger standard iOS Share Sheet (Messages, copy link).

Placement: Accessible in Lobby.

### 8.3 HapticManager

Standard: HapticManager.shared.play(.impact)

Toggle: Must respect user preference for reduced haptics.

## 9. Lobby & Ready System

Discovery Mode: Users start in "Discovery Mode," scanning for peers.

Lobby: Public/Private. Host has full control (Kick/Ban).

Metadata: GameCatalogEntry is used to render the selection screen.

Settings: Host can modify settings. These are serialized to LobbyInfo.activeSettings so clients can view rules.

Ready: Mandatory Ready toggle for all players.

## 10. UI Philosophy

Common Overlay: Every game must support a standardized "Menu" overlay containing:

Resume

How to Play (Rules)

Settings (Read-only if Client)

Exit Game

Performance: Animations must degrade gracefully on iPhone SE performance profiles. Avoid excessive particle effects.

Thumb-Friendly: Actions in bottom 30%.

Spotlight: Active player indication.

Resolution: Must allow for small screens (iPhone SE).

## 11. Coding Rules for AI

No God Files: Keep files under 200 lines.

Protocol Driven: Program to GameModule / GameTransport.

Safe Concurrency: Use MainActor for UI, Task / async for network.

Testing: Device-to-Device required.

## 12. Roadmap

Short-term:

Connectivity Backbone (Async).

Crazy Eights MVP.

Profile Persistence (Versioning).

Medium-term:

Practice Mode (Bots).

Avatar Builder.

Long-term:

Store UI.

Hybrid Mode.

## 13. Summary for AI Assistants

This is the immutable architecture contract.

Host is Authoritative.

Modules are Isolated.

Security is enforced (Hashing/Payload limits).

Offline First.
