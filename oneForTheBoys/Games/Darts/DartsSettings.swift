import Foundation

struct DartsSettings: Codable, Hashable {
    var settingsVersion: Int = 1
    var startingScore: Int = 101
    var doubleOutRequired: Bool = false
}
