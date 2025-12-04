import Foundation

public enum CrazyEightsAction: Codable, Sendable {
    case startRound
    case updateSettings(CrazyEightsSettings)
    case intentDraw(playerId: UUID)
    case intentPlay(card: UNOCard, chosenColor: UNOColor?, targetId: UUID?)
    case callUno(playerId: UUID)
    case swapHand(targetId: UUID)
    case blindPlayRandom(playerId: UUID)
    case leave(playerId: UUID)
}
