import Foundation

enum GameError: Error, Codable {
    case invalidAction
    case desync
    case corruptedPayload
    case versionMismatch
}
