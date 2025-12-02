import SwiftUI

/// Registry for game modules to allow discovery, metadata display, and compatibility checks.
final class GameRegistry {
    static let shared = GameRegistry()

    /// Call once at launch to register all supported game modules.
    @MainActor
    static func bootstrap() {
        GameRegistry.shared.register(CrazyEightsGameModule.self)
        GameRegistry.shared.register(DartsGameModule.self)
    }

    struct AnyModuleDescriptor {
        let id: GameID
        let catalogEntry: GameCatalogEntry
        let policy: GamePolicy
        let defaultSettingsData: () -> Data?
        let makeSettingsView: @MainActor (Binding<Data>) -> AnyView
        let makeRulesView: @MainActor () -> AnyView
        let makeSession: @MainActor (_ players: [PlayerProfile], _ settingsData: Data?, _ transport: GameTransport, _ isHost: Bool, _ localPlayerId: UUID) -> AnyGameSession
        let canDecodeSettings: (Data) -> Bool
    }

    private var modules: [GameID: AnyModuleDescriptor] = [:]

    private init() {}

    @MainActor
    func register<T: GameModule>(_ module: T.Type) {
        modules[T.id] = module.makeDescriptor()
    }

    func descriptor(for id: GameID) -> AnyModuleDescriptor? {
        modules[id]
    }

    var allDescriptors: [AnyModuleDescriptor] {
        Array(modules.values)
    }

    @MainActor
    func makeSession(for id: GameID,
                     players: [PlayerProfile],
                     settingsData: Data?,
                     transport: GameTransport,
                     isHost: Bool,
                     localPlayerId: UUID) -> AnyGameSession? {
        guard let descriptor = modules[id] else { return nil }
        return descriptor.makeSession(players, settingsData, transport, isHost, localPlayerId)
    }
}

private extension GameModule {
    @MainActor
    static func makeDescriptor() -> GameRegistry.AnyModuleDescriptor {
        GameRegistry.AnyModuleDescriptor(
            id: Self.id,
            catalogEntry: Self.catalogEntry,
            policy: Self.policy,
            defaultSettingsData: {
                let settings = Self.defaultSettings()
                return try? JSONEncoder().encode(settings)
            },
            makeSettingsView: { dataBinding in
                // Bridge Binding<Data> -> Binding<Settings> so registry users can build settings UI generically.
                let settingsBinding = Binding<Settings>(
                    get: {
                        if let decoded = try? JSONDecoder().decode(Settings.self, from: dataBinding.wrappedValue) {
                            return decoded
                        }
                        return Self.defaultSettings()
                    },
                    set: { newSettings in
                        dataBinding.wrappedValue = (try? JSONEncoder().encode(newSettings)) ?? Data()
                    }
                )
                return Self.makeSettingsView(binding: settingsBinding)
            },
            makeRulesView: {
                Self.makeRulesView()
            },
            makeSession: { players, settingsData, transport, isHost, localPlayerId in
                let settings: Settings
                if let settingsData,
                   let decoded = try? JSONDecoder().decode(Settings.self, from: settingsData) {
                    settings = decoded
                } else {
                    settings = Self.defaultSettings()
                }
                return Self.makeAnySession(players: players, settings: settings, transport: transport, isHost: isHost, localPlayerId: localPlayerId)
            },
            canDecodeSettings: { data in
                (try? JSONDecoder().decode(Settings.self, from: data)) != nil
            }
        )
    }
}
