import Foundation

public enum DeckBuilder {
    public static func deck(with config: CrazyEightsSettings) -> [UNOCard] {
        var deck: [UNOCard] = []

        for color in [UNOColor.red, .yellow, .green, .blue] {
            deck.append(UNOCard(color: color, value: .number(0)))
            for n in 0...9 where n != 8 {
                deck.append(UNOCard(color: color, value: .number(n)))
                deck.append(UNOCard(color: color, value: .number(n)))
                deck.append(UNOCard(color: color, value: .number(n)))
                deck.append(UNOCard(color: color, value: .number(n)))
            }
            for _ in 0..<config.skipPerColor {
                deck.append(UNOCard(color: color, value: .skip))
            }
            for _ in 0..<config.reversePerColor {
                deck.append(UNOCard(color: color, value: .reverse))
            }
            for _ in 0..<config.draw2PerColor {
                deck.append(UNOCard(color: color, value: .draw2))
            }
        }

        for _ in 0..<config.wildCount {
            deck.append(UNOCard(color: .wild, value: .wild))
        }
        for _ in 0..<config.wildDraw4Count {
            deck.append(UNOCard(color: .wild, value: .wildDraw4))
        }
        if config.fogEnabled {
            for _ in 0..<max(0, config.fogCardCount) {
                deck.append(UNOCard(color: .wild, value: .fog))
            }
        }

        return deck.shuffled()
    }
}
