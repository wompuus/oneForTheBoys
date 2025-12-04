import SwiftUI
import OFTBShared

struct DartsResultsView: View {
    let state: DartsGameState
    let players: [PlayerProfile]
    let localPlayerId: UUID

    var body: some View {
        VStack(spacing: 12) {
            if let winnerId = state.winnerId,
               let winner = players.first(where: { $0.id == winnerId }) {
                Text("🏆 \(winner.username) wins!")
                    .font(.title2.bold())
            } else {
                Text("Game over")
                    .font(.title2.bold())
            }

            List {
                ForEach(state.players) { p in
                    HStack {
                        Text(p.name)
                        Spacer()
                        Text("\(state.scores[p.id] ?? 0)")
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding()
    }
}
