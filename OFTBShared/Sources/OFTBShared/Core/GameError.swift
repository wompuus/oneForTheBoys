import Foundation

public enum GameError: Error, Codable {
    case invalidAction
    case desync
    case corruptedPayload
    case versionMismatch
}
