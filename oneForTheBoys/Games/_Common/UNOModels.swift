//
//  Untitled.swift
//  oneForTheBoys
//
//  Created by Wyatt Nail on 11/18/25.
//

import Foundation

enum UNOColor: String, Codable, CaseIterable, Identifiable {
    case red, yellow, green, blue, wild
    var id: String { rawValue }
    var display: String { rawValue.capitalized }
}

enum UNOValue: Codable, Equatable, Hashable {
    case number(Int)      // 0–9
    case skip
    case reverse
    case draw2
    case wild
    case wildDraw4
    case fog
}

extension UNOValue: CustomStringConvertible {
    var description: String {
        switch self {
        case .number(let n): return String(n)
        case .skip: return "Skip"
        case .reverse: return "Reverse"
        case .draw2: return "+2"
        case .wild: return "Wild"
        case .wildDraw4: return "Wild+4"
        case .fog: return "Fog"
        }
    }
}

struct UNOCard: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var color: UNOColor
    var value: UNOValue
}

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String // This is the custom ingame name
    var deviceName: String // MCPeerID.displayName for disconnect mapping
    var hand: [UNOCard]
}

struct GameState: Codable {
    // Lobby / identity
    var players: [Player] = []
    var hostId: UUID? = nil

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
    var bombCardId: UUID? = nil

    // End-of-round state
    var winnerId: UUID? = nil     // non-nil when someone has won the current round

    // Config snapshot for round
    var config: CrazyEightsSettings = .init()

    var currentPlayerId: UUID? {
        guard players.indices.contains(turnIndex) else { return nil }
        return players[turnIndex].id
    }

    var topCard: UNOCard? { discardPile.last }
}
