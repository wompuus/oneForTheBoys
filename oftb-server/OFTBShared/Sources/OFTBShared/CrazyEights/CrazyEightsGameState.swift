import Foundation

public struct CrazyEightsPlayer: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var deviceName: String
    public var hand: [UNOCard]
    public var avatar: AvatarConfig?

    public init(id: UUID, name: String, deviceName: String, hand: [UNOCard], avatar: AvatarConfig? = nil) {
        self.id = id
        self.name = name
        self.deviceName = deviceName
        self.hand = hand
        self.avatar = avatar
    }
}

public struct CrazyEightsGameState: Codable, Equatable, Sendable {
    public struct BombEvent: Codable, Equatable, Sendable {
        public let triggerId: UUID
        public let victimIds: [UUID]
        public let cardId: UUID

        public init(triggerId: UUID, victimIds: [UUID], cardId: UUID) {
            self.triggerId = triggerId
            self.victimIds = victimIds
            self.cardId = cardId
        }
    }

    public var players: [CrazyEightsPlayer] = []
    public var hostId: UUID?
    public var roundId: UUID = UUID()
    public var resultCredited: Bool = false

    // Flow
    public var turnIndex: Int = 0
    public var clockwise: Bool = true
    public var started: Bool = false

    // Piles
    public var discardPile: [UNOCard] = []
    public var drawPile: [UNOCard] = []

    // Rule accumulators
    public var pendingDraw: Int = 0
    public var chosenWildColor: UNOColor? = nil

    // Rules state
    public var unoCalled: Set<UUID> = []
    public var shotCallerTargetId: UUID? = nil
    public var shotCallerDemands: [UUID: [UNOColor]] = [:]
    public var bombCardId: UUID? = nil
    public var bombEvent: BombEvent? = nil
    public var blindedPlayerId: UUID? = nil
    public var blindedTurnsRemaining: Int = 0
    public var pendingSwapPlayerId: UUID? = nil

    // End-of-round state
    public var winnerId: UUID? = nil

    // Config snapshot for round
    public var config: CrazyEightsSettings = .init()

    public init() {}

    public var currentPlayerId: UUID? {
        guard players.indices.contains(turnIndex) else { return nil }
        return players[turnIndex].id
    }

    public var topCard: UNOCard? { discardPile.last }
}

public extension CrazyEightsGameState {
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
