import SwiftUI

struct BombOverlay: View {
    let event: CrazyEightsGameState.BombEvent
    let players: [CrazyEightsPlayer]
    let drawCount: Int

    private var triggerName: String {
        players.first(where: { $0.id == event.triggerId })?.name ?? "Someone"
    }

    private var victimNames: [String] {
        players.filter { event.victimIds.contains($0.id) }.map { $0.name }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("💣")
                .font(.system(size: 48))

            Text("\(triggerName) detonated the bomb!")
                .font(.title3.bold())
                .foregroundStyle(.white)

            if !victimNames.isEmpty {
                Text("\(victimNames.joined(separator: ", ")) got blown up")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))

                Text("They each drew \(max(1, drawCount)) card(s)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(radius: 12)
    }
}
