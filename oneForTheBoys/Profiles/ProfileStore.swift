import Foundation
import SwiftUI
import OFTBShared

actor ProfileStore {
    static let shared = ProfileStore()

    private let fileURL: URL
    private let kvs = NSUbiquitousKeyValueStore.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = docs.appendingPathComponent("userProfile.json")
    }

    /// Returns profile and whether it was newly created (no persisted record found).
    func loadProfile(defaultName: String) async -> (PlayerProfile, Bool) {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode(PlayerProfile.self, from: data) {
            return (decoded, false)
        }

        if let data = kvs.data(forKey: "userProfile"),
           let decoded = try? decoder.decode(PlayerProfile.self, from: data) {
            await save(decoded) // persist locally
            return (decoded, false)
        }

        let profile = PlayerProfile(
            id: UUID(),
            username: defaultName,
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
        await save(profile)
        return (profile, true)
    }

    func save(_ profile: PlayerProfile) async {
        do {
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: .atomic)
            kvs.set(data, forKey: "userProfile")
            kvs.synchronize()
            NotificationCenter.default.post(name: .profileStoreUpdated, object: nil)
        } catch {
            print("Profile save failed: \(error)")
        }
    }
}

extension Notification.Name {
    static let profileStoreUpdated = Notification.Name("ProfileStoreUpdated")
}
