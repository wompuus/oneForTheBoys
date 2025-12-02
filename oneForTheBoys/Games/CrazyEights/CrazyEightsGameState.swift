import Foundation

struct CrazyEightsPlayer: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var deviceName: String
    var hand: [UNOCard]
    var avatar: AvatarConfig?
}

struct CrazyEightsGameState: Codable, Equatable {
    struct BombEvent: Codable, Equatable {
        let triggerId: UUID
        let victimIds: [UUID]
        let cardId: UUID
    }

    var players: [CrazyEightsPlayer] = []
    var hostId: UUID?
    var roundId: UUID = UUID()
    var resultCredited: Bool = false

    // Flow
    var turnIndex: Int = 0
    var clockwise: Bool = true
    var started: Bool = false

    // Piles
    var discardPile: [UNOCard] = []
    var drawPile: [UNOCard] = []

    // Rule accumulators
    var pendingDraw: Int = 0
    var chosenWildColor: UNOColor? = nil

    // Rules state
    var unoCalled: Set<UUID> = []
    var shotCallerTargetId: UUID? = nil
    var shotCallerDemands: [UUID: [UNOColor]] = [:]
    var bombCardId: UUID? = nil
    var bombEvent: BombEvent? = nil
    var blindedPlayerId: UUID? = nil
    var blindedTurnsRemaining: Int = 0
    var pendingSwapPlayerId: UUID? = nil

    // End-of-round state
    var winnerId: UUID? = nil

    // Config snapshot for round
    var config: CrazyEightsSettings = .init()

    var currentPlayerId: UUID? {
        guard players.indices.contains(turnIndex) else { return nil }
        return players[turnIndex].id
    }

    var topCard: UNOCard? { discardPile.last }
}

extension CrazyEightsGameState {
    /// Returns true if `card` is legally playable on top of the current discard.
    func canPlay(_ card: UNOCard) -> Bool {
        guard let top = topCard else { return true }

        if pendingDraw > 0 {
            guard config.allowStackDraws else { return false }

            switch top.value {
            case .draw2:
                switch card.value {
                case .draw2: return true
                case .wildDraw4: return config.allowMixedDrawStacking
                default: return false
                }
            case .wildDraw4:
                switch card.value {
                case .wildDraw4: return true
                case .draw2: return config.allowMixedDrawStacking
                default: return false
                }
            default:
                return false
            }
        }

        if let targetId = shotCallerTargetId,
           currentPlayerId == targetId,
           let forcedColor = shotCallerDemands[targetId]?.first {
            if card.color == .wild || card.value == .wildDraw4 { return true }
            return card.color == forcedColor
        }

        if case .wild = card.value { return true }
        if case .wildDraw4 = card.value { return true }
        if case .fog = card.value { return true }

        let effectiveTopColor: UNOColor
        if top.color == .wild, let forced = chosenWildColor {
            effectiveTopColor = forced
        } else {
            effectiveTopColor = top.color
        }
        let effectiveTopValue = top.value

        if card.color == effectiveTopColor { return true }
        if card.value == effectiveTopValue { return true }

        return false
    }
}
