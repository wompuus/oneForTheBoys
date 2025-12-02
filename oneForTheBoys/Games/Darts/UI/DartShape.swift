import SwiftUI

/// Simple dart silhouette (rear view) used as a marker for landed throws.
struct DartShape: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shaftWidth = w * 0.2

            DartSilhouette(shaftWidth: shaftWidth)
                .fill(Color.red)
                .overlay(
                    DartSilhouette(shaftWidth: shaftWidth)
                        .stroke(Color.black.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 2, x: 1, y: 1)
        }
    }
}

private struct DartSilhouette: Shape {
    let shaftWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let shaftX = (w - shaftWidth) / 2

        // Flights (triangle)
        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: w, y: h * 0.35))
        path.addLine(to: CGPoint(x: 0, y: h * 0.35))
        path.closeSubpath()

        // Shaft
        path.addRect(CGRect(x: shaftX, y: h * 0.35, width: shaftWidth, height: h * 0.65))

        return path
    }
}
