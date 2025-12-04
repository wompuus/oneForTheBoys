import SwiftUI
import OFTBShared

struct AvatarView: View {
    let config: AvatarConfig
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: config.backgroundColorHex))
            Image(systemName: config.baseSymbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(hex: config.skinColorHex))
                .padding(size * 0.2)
            if let hairSymbol = config.hairSymbol {
                Image(systemName: hairSymbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(hex: config.hairColorHex))
                    .padding(size * 0.18)
            }
            if let accessorySymbol = config.accessorySymbol {
                Image(systemName: accessorySymbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

extension Color {
    init(hex: String) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexString.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
