import SwiftUI

// Found this on the internet. I'm not sure if it will work but would like global variables for the colors in the game, would make it easier in the future to add skins and stuff. Remember, modularity.
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    // Bright, readable card colors
    static let cardRed    = Color(hex: 0xFF3B30)  // bright red
    static let cardYellow = Color(hex: 0xFFD60A)  // strong yellow, not ugly mustard
    static let cardGreen  = Color(hex: 0x34C759)  // bright green
    static let cardBlue   = Color(hex: 0x0A84FF)  // vivid blue

    // Table color: dark red that won't blend with cardRed
    static let tableRed   = Color(hex: 0x4A1F1F)
}

struct CardView: View {
    // MARK: - Main card view (player hand)
    let card: UNOCard
    var isPlayable: Bool = true

    private var bgColor: AnyView {
        if card.color == .wild {
            // Rainbow-style wild
            return AnyView(
                LinearGradient(
                    colors: [.cardRed, .cardYellow, .cardGreen, .cardBlue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            )
        } else {
            let c: Color
            switch card.color {
            case .red:    c = .cardRed
            case .yellow: c = .cardYellow
            case .green:  c = .cardGreen
            case .blue:   c = .cardBlue
            case .wild:   c = .black   // handled above
            }
            return AnyView(
                c.clipShape(RoundedRectangle(cornerRadius: 12))
            )
        }
    }

    private var textColor: Color {
        card.color == .wild ? .white : .black
    }

    private var label: String {
        switch card.value {
        case .number(let n): return String(n)
        case .skip:          return "SKIP"     // or "S"
        case .reverse:       return "↺"
        case .draw2:         return "+2"
        case .wild:          return "8"      // big 8 for wild
        case .wildDraw4:     return "+4"
        }
    }

    var body: some View {
        ZStack {
            bgColor

            Text(label)
                .font(card.color == .wild ? .largeTitle.bold() : .title2.bold())
                .foregroundStyle(textColor)
        }
        .frame(width: 90, height: 130)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.3), lineWidth: 2)
        )
        .shadow(radius: isPlayable ? 4 : 1)
        .opacity(isPlayable ? 1.0 : 0.35)
        .scaleEffect(isPlayable ? 1.05 : 0.95)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isPlayable)
    }
}

// MARK: - Smaller card (center discard)

struct SmallCardView: View {
    let card: UNOCard
    var overrideColor: UNOColor? = nil   // for wilds, use chosen color

    private var bgColor: AnyView {
        if card.color == .wild {
            if let forced = overrideColor {
                // When wild color is chosen, show that solid color
                let c: Color
                switch forced {
                case .red:    c = .cardRed
                case .yellow: c = .cardYellow
                case .green:  c = .cardGreen
                case .blue:   c = .cardBlue
                case .wild:   c = .black
                }
                return AnyView(
                    c.clipShape(RoundedRectangle(cornerRadius: 10))
                )
            } else {
                // No color picked yet: rainbow wild
                return AnyView(
                    LinearGradient(
                        colors: [.cardRed, .cardYellow, .cardGreen, .cardBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                )
            }
        } else {
            let c: Color
            switch card.color {
            case .red:    c = .cardRed
            case .yellow: c = .cardYellow
            case .green:  c = .cardGreen
            case .blue:   c = .cardBlue
            case .wild:   c = .black
            }
            return AnyView(
                c.clipShape(RoundedRectangle(cornerRadius: 10))
            )
        }
    }

    private var textColor: Color {
        (card.color == .wild && overrideColor == nil) ? .white : .black
    }

    private var label: String {
        switch card.value {
        case .number(let n): return String(n)
        case .skip:          return "SKIP"
        case .reverse:       return "↺"
        case .draw2:         return "+2"
        case .wild:          return "8"
        case .wildDraw4:     return "+4"
        }
    }

    var body: some View {
        ZStack {
            bgColor

            Text(label)
                .font(.headline.bold())
                .foregroundStyle(textColor)
        }
        .frame(width: 70, height: 100)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.3), lineWidth: 2)
        )
        .shadow(radius: 2)
    }
}

// MARK: - Deck (face-down pile you tap to draw)

struct DeckView: View {
    let canDraw: Bool
    let draw: () -> Void

    var body: some View {
        Button(action: draw) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.9))
                    .frame(width: 70, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.6), lineWidth: 2)
                    )

                Text("UNO")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .opacity(canDraw ? 1.0 : 0.4)
        .disabled(!canDraw)
    }
}

// MARK: - Color picker for wild

struct ColorPickerSheet: View {
    let pick: (UNOColor) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Choose color")
                .font(.headline)
            HStack {
                ForEach([UNOColor.red, .yellow, .green, .blue]) { c in
                    Button(c.display) { pick(c) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
}

// MARK: - Shot Caller sheet

struct ShotCallerSheet: View {
    let players: [Player]
    let pick: (UNOColor, UUID?) -> Void

    @State private var selectedColor: UNOColor = .red
    @State private var selectedPlayer: UUID? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Choose color") {
                    Picker("Color", selection: $selectedColor) {
                        ForEach([UNOColor.red, .yellow, .green, .blue]) { c in
                            Text(c.display).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Choose target player") {
                    ForEach(players) { p in
                        Button(action: { selectedPlayer = p.id }) {
                            HStack {
                                Text(p.name)
                                if selectedPlayer == p.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    if selectedPlayer == nil {
                        Text("Select who must follow this color")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Apply") {
                        pick(selectedColor, selectedPlayer)
                    }
                    .disabled(selectedPlayer == nil)
                }
            }
            .navigationTitle("Shot Caller")
        }
    }
}

// MARK: - Opponent seat (around the table)

struct OpponentSeatView: View {
    let player: Player
    let isCurrentTurn: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Spotlight glow behind current player
                if isCurrentTurn {
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.32),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blur(radius: 3)
                        .scaleEffect(x: 0.9, y: 1.6)   // very small & tight
                        .frame(width: 80, height: 45)  // hard cap on size
                        .offset(y: -4)                 // tiny nudge upward
                }

                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: isCurrentTurn
                                ? [Color.white.opacity(0.35), Color.white.opacity(0.12)]
                                : [Color.black.opacity(0.35), Color.black.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isCurrentTurn
                                ? Color.white.opacity(0.8)
                                : Color.white.opacity(0.25),
                                lineWidth: isCurrentTurn ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isCurrentTurn
                            ? Color.white.opacity(0.9)
                            : Color.black.opacity(0.6),
                        radius: isCurrentTurn ? 12 : 3,
                        x: 0,
                        y: 0
                    )

                VStack(spacing: 2) {
                    Text("🃏")
                    Text("\(player.hand.count)")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
            }
            .scaleEffect(isCurrentTurn ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCurrentTurn)

            Text(player.name)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(width: 80)
        }
    }
}

// MARK: - Back-of-card for draw animations

struct BackCardView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
                )

            Text("cArDs")
                .font(.headline.bold())
                .foregroundStyle(.white)
        }
    }
}
