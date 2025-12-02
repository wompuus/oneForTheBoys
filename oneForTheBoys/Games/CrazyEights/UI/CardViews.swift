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
        case .fog:           return "FOG"
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
        case .fog:           return "FOG"
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

struct BackCardView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.black.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
            )
    }
}

// MARK: - Color picker for wild

struct ColorPickerSheet: View {
    let pick: (UNOColor) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Choose a color")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach([UNOColor.red, .yellow, .green, .blue], id: \.self) { c in
                    Button(action: { pick(c) }) {
                        Circle()
                            .fill(c.color)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Shot caller picker (wild + target)

struct ShotCallerSheet: View {
    let players: [Player]
    let pick: (UNOColor, UUID) -> Void
    @State private var chosenColor: UNOColor = .red
    @State private var targetId: UUID?

    var body: some View {
        VStack(spacing: 16) {
            Text("Pick color and target").font(.headline)

            HStack(spacing: 12) {
                ForEach([UNOColor.red, .yellow, .green, .blue], id: \.self) { c in
                    Button(action: { chosenColor = c }) {
                        Circle()
                            .fill(c.color)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle().stroke(chosenColor == c ? Color.white : Color.clear, lineWidth: 2)
                            )
                    }
                }
            }

            Picker("Target", selection: Binding(
                get: { targetId ?? players.first?.id },
                set: { targetId = $0 }
            )) {
                ForEach(players) { p in
                    HStack {
                        Text(p.name)
                        if targetId == p.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        }
                    }
                    .tag(Optional(p.id))
                }
            }
            .pickerStyle(.wheel)

            Button("Confirm") {
                if let targetId = targetId ?? players.first?.id {
                    pick(chosenColor, targetId)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            if targetId == nil { targetId = players.first?.id }
        }
    }
}

// MARK: - Swap hand picker (7 rule)

struct SwapHandSheet: View {
    let title: String
    let buttonTitle: String
    let players: [Player]
    let pick: (UUID) -> Void
    @State private var targetId: UUID?

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Picker("Target", selection: Binding(
                get: { targetId ?? players.first?.id },
                set: { targetId = $0 }
            )) {
                ForEach(players) { p in
                    HStack {
                        Text(p.name)
                        if targetId == p.id {
                            Image(systemName: "arrow.left.arrow.right")
                                .foregroundColor(.yellow)
                        }
                    }
                    .tag(Optional(p.id))
                }
            }
            .pickerStyle(.wheel)

            Button(buttonTitle) {
                if let target = targetId ?? players.first?.id {
                    pick(target)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            if targetId == nil { targetId = players.first?.id }
        }
    }
}

private extension UNOColor {
    var color: Color {
        switch self {
        case .red: return .cardRed
        case .yellow: return .cardYellow
        case .green: return .cardGreen
        case .blue: return .cardBlue
        case .wild: return .black
        }
    }
}
