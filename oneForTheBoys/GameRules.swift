extension GameState {
    /// Returns true if `card` is legally playable on top of the current discard,
    /// given pending draw stacks, Shot Caller, and wild color choice.
    func canPlay(_ card: UNOCard) -> Bool {
        // If there's no top card, anything can start the round.
        guard let top = topCard else { return true }

        // 1) Pending draw stacks
        if pendingDraw > 0 {
            // Stacking disabled: you must draw, nothing is playable
            guard config.allowStackDraws else { return false }

            // Only draw2 / wildDraw4 may be stacked
            switch top.value {
            case .draw2:
                switch card.value {
                case .draw2:
                    return true
                case .wildDraw4:
                    return config.allowMixedDrawStacking
                default:
                    return false
                }
            case .wildDraw4:
                switch card.value {
                case .wildDraw4:
                    return true
                case .draw2:
                    return config.allowMixedDrawStacking
                default:
                    return false
                }
            default:
                // Shouldn't happen, but be safe: no stacking if top isn't a draw card
                return false
            }
        }

        // 2) Shot Caller restriction:
        // If it's the target's turn and no pending draw, they must follow the chosen color,
        // or play another wild. This applies regardless of what the top card actually is.
        if let targetId = shotCallerTargetId,
           currentPlayerId == targetId,
           let forcedColor = chosenWildColor {

            if card.color == .wild {
                return true
            }
            return card.color == forcedColor
        }

        // 3) Normal matching rules (color OR value OR wild)

        // If the card itself is wild, it's always playable (color chosen separately).
        if case .wild = card.value { return true }
        if case .wildDraw4 = card.value { return true }

        // Determine the effective color/value on the top of the discard pile.
        // If a wild was played previously, we treat its color as `chosenWildColor`.
        let effectiveTopColor: UNOColor
        if top.color == .wild, let forced = chosenWildColor {
            effectiveTopColor = forced
        } else {
            effectiveTopColor = top.color
        }
        let effectiveTopValue = top.value

        // Match by color OR by value
        if card.color == effectiveTopColor { return true }
        if card.value == effectiveTopValue { return true }

        return false
    }
}
