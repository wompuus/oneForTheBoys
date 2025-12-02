import SwiftUI
import RealityKit

struct DartsRealityView: UIViewRepresentable {
    @ObservedObject var controller: DartsRealityController
    let turnHistory: [DartThrow]
    let remoteFlights: [UUID: DartFlightSnapshot]
    let onHit: (CGPoint) -> Void
    let onFlightSpawn: ((UUID) -> Void)?
    let onFlightUpdate: ((UUID, [Float], [Float]) -> Void)?
    let onFlightLanded: ((UUID, CGPoint) -> Void)?

    func makeUIView(context: Context) -> ARView {
        controller.onFlightSpawn = onFlightSpawn
        controller.onFlightUpdate = onFlightUpdate
        controller.onFlightLanded = onFlightLanded
        return controller.makeView(onHit: onHit)
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        controller.syncRemoteFlights(remoteFlights)
    }
}
