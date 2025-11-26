import SwiftUI

struct OpponentSeatView: View {
    let player: CEOpponent
    let isCurrentTurn: Bool
    let rotationAngle: CGFloat
    private let cardsPerRow = 15
    private let maxRows = 1

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                if let avatarConfig = player.avatar {
                    AvatarView(config: avatarConfig, size: 28)
                        .overlay(
                            Circle()
                                .stroke(isCurrentTurn ? Color.green : Color.clear, lineWidth: 2)
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isCurrentTurn ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(isCurrentTurn ? "Turn" : "Waiting")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            ZStack {
                ForEach(Array(cardRows.enumerated()), id: \.offset) { rowIndex, count in
                    ForEach(0..<count, id: \.self) { col in
                        let layout = layoutForCard(row: rowIndex, indexInRow: col, countInRow: count)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.8))
                            .frame(width: 24, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                            .rotationEffect(.radians(layout.cardRotation))
                            .offset(x: layout.offset.x, y: layout.offset.y)
                    }
                }
                Text("\(player.handCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .rotationEffect(.radians(-(rotationAngle + .pi / 2)))
            }
            .rotationEffect(.radians(rotationAngle + .pi / 2))
        }
    }

    private var cardRows: [Int] {
        let total = player.handCount
        guard total > 0 else { return [] }
        var rows: [Int] = []
        var remaining = total
        while remaining > 0 && rows.count < maxRows {
            let count = min(cardsPerRow, remaining)
            rows.append(count)
            remaining -= count
        }
        return rows
    }

    private func layoutForCard(row: Int, indexInRow: Int, countInRow: Int) -> (offset: CGPoint, cardRotation: Double) {
        let mid = Double(max(countInRow - 1, 1)) / 2.0
        let offsetIdx = Double(indexInRow) - mid
        // Gentle arc spread
        let angle = offsetIdx * 0.18 // radians
        let radius = 55.0 - Double(row) * 4.0
        let x = sin(angle) * radius
        let y = -cos(angle) * radius - Double(row) * 28.0
        // Rotate card slightly along the arc
        return (CGPoint(x: x, y: y), angle)
    }
}
