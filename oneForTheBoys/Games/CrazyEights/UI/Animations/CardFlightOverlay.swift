import SwiftUI

struct CardFlightOverlay: View {
    struct Flight: Identifiable {
        enum Kind { case play(UNOCard), draw }
        let id = UUID()
        let kind: Kind
        let start: CGPoint
        let end: CGPoint
        var progress: CGFloat = 0
    }

    let flights: [Flight]

    var body: some View {
        ZStack {
            ForEach(flights) { flight in
                flightView(for: flight.kind)
                    .modifier(FlightAnimModifier(start: flight.start, end: flight.end, progress: flight.progress))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func flightView(for kind: Flight.Kind) -> some View {
        switch kind {
        case .play(let card):
            CardView(card: card, isPlayable: false)
                .frame(width: 90, height: 130)
        case .draw:
            BackCardView()
                .frame(width: 70, height: 100)
        }
    }
}

private struct FlightAnimModifier: AnimatableModifier {
    var start: CGPoint
    var end: CGPoint
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let x = start.x + (end.x - start.x) * progress
        let y = start.y + (end.y - start.y) * progress
        return content
            .position(x: x, y: y)
            .opacity(0.5 + 0.5 * Double(1 - abs(progress - 0.5)))
    }
}
