import Foundation
import RealityKit
import ARKit
import Combine
import SwiftUI
import UIKit

/// Coordinates the RealityKit scene: board setup, dart spawning/physics, and hit callback.
@MainActor
final class DartsRealityController: ObservableObject {
    @Published private(set) var isThrowInFlight = false
    @Published private(set) var isCameraAnimatingBack = false

    private(set) var arView: ARView?
    private var anchor: AnchorEntity?
    private var board: ModelEntity?
    private var currentDart: ModelEntity?
    private var cameraEntity: PerspectiveCamera?
    private var cancellables: Set<AnyCancellable> = []
    private var onHit: ((CGPoint) -> Void)?
    var onFlightSpawn: ((UUID) -> Void)?
    var onFlightUpdate: ((UUID, [Float], [Float]) -> Void)?
    var onFlightLanded: ((UUID, CGPoint) -> Void)?
    private let boardSize: Float = 2.0 // meters (scaled back down to reduce tunneling risk)
    // Starting point for the held dart in world space (x,y,z meters).
    // +X is right, +Y is up, -Z is forward toward the board. Move this to reposition the “in hand” dart.
    private let readyDartBasePosition = SIMD3<Float>(0, 1.3, -0.15)
    private var activeDartId: UUID?
    private var remoteDarts: [UUID: ModelEntity] = [:]
    // Toggle to enable/disable flight camera animation (for debugging or comfort).
    var enableFlightCameraAnimation = true
    private let dartCollisionGroup = CollisionGroup(rawValue: 1 << 0)
    private let boardCollisionGroup = CollisionGroup(rawValue: 1 << 1)
    private let cameraHomePosition = SIMD3<Float>(0, 2, 0.5)
    private let cameraHomeOrientation = simd_quatf(angle: -.pi / 12, axis: SIMD3<Float>(1, 0, 0))
    
    func makeView(onHit: @escaping (CGPoint) -> Void) -> ARView {
        if let arView {
            self.onHit = onHit
            return arView
        }

        // Non-AR view for a fully virtual scene; we control the camera programmatically.
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.black)
        view.environment.sceneUnderstanding.options = []
        self.onHit = onHit

        let anchor = AnchorEntity(world: .zero)
        view.scene.anchors.append(anchor)
        self.anchor = anchor

        // Camera setup (virtual head position). +Z pulls back; board is at roughly z = -3.4.
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 75
        camera.position = cameraHomePosition // Adjust this to move the viewing point.
        // Tilt downward: negative pitch rotates the view down toward -Y (assuming -Z is forward).
        let downTilt = simd_quatf(angle: -.pi/12, axis: SIMD3<Float>(1, 0, 0)) // ~15°
        camera.orientation = downTilt
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        view.scene.addAnchor(cameraAnchor)
        self.cameraEntity = camera

        setupRoom(in: anchor)
        setupBoard(in: anchor)
        setupLighting(in: view.scene)

        // Collision subscription
        view.scene.subscribe(to: CollisionEvents.Began.self) { [weak self] event in
            self?.handleCollision(event)
        }.store(in: &cancellables)

        spawnReadyDart()
        self.arView = view
        return view
    }

    func throwDart(flick: CGPoint) {
        guard anchor != nil, let dart = currentDart, !isThrowInFlight else { return }
        isThrowInFlight = true
        let dartId = UUID()
        activeDartId = dartId
        onFlightSpawn?(dartId)
        currentDart = nil

        // Activate physics (heavier + damping to slow down flight)
        if var body = dart.components[PhysicsBodyComponent.self] {
            body.mode = .dynamic
            body.massProperties = .init(mass: 0.14)
            body.linearDamping = 0.1 // bleed velocity over time (tune this up/down to slow/speed flight)
            dart.components.set(body)
        } else {
            var body = PhysicsBodyComponent(massProperties: .init(mass: 0.14), material: .default, mode: .dynamic)
            body.linearDamping = 0.1
            dart.components.set(body)
        }
        if dart.components[PhysicsMotionComponent.self] == nil {
            dart.components.set(PhysicsMotionComponent())
        }

        // Map flick to 3D impulse relative to camera forward (-Z), including horizontal aim from held offset.
        let holdOffsetX = dart.position.x - readyDartBasePosition.x
        let impulse = mapFlickToImpulse(flick: flick, holdOffsetX: holdOffsetX)
        dart.physicsMotion?.linearVelocity = impulse

        // Orient to velocity each frame (forward axis is -Z, roll constrained).
        arView?.scene.subscribe(to: SceneEvents.Update.self) { [weak dart] (_: SceneEvents.Update) in
            guard let dart, let motion = dart.components[PhysicsMotionComponent.self] else { return }
            let v = motion.linearVelocity
            if simd_length(v) > 0.01 {
                dart.orientation = self.orientationForVelocity(v)
                // Stream transform for remote viewers.
                if let dartId = self.activeDartId {
                    self.onFlightUpdate?(dartId,
                                         [dart.position.x, dart.position.y, dart.position.z],
                                         [dart.orientation.imag.x, dart.orientation.imag.y, dart.orientation.imag.z, dart.orientation.real])
                }
            }
        }.store(in: &cancellables)

        // Safety reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.isThrowInFlight = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.spawnReadyDart()
        }
    }

    private func mapFlickToImpulse(flick: CGPoint, holdOffsetX: Float) -> SIMD3<Float> {
        // Axis: +X (Right), +Y (Up), -Z (Forward)
        // 1. Raw flick intensity (points per second)
        let velocityY = Float(-flick.y)
        let velocityX = Float(flick.x)
        // 2. Sensitivity multipliers
        let forwardSensitivity: Float = 0.0022
        let verticalSensitivity: Float = 0.0012
        let horizontalSensitivity: Float = 0.0012
        let aimOffsetMultiplier: Float = 6.0 // use held offset to influence lateral aim
        // 3. Forward power based on upward flick speed
        let forwardSpeed = 1.4 + (max(0, velocityY) * forwardSensitivity)
        // 4. Vertical lift
        let verticalSpeed = velocityY * verticalSensitivity
        // 5. Side drift
        let horizontalSpeed = (velocityX * horizontalSensitivity) + (holdOffsetX * aimOffsetMultiplier)
        // 6. Clamp
        let clampedZ = min(9.0, forwardSpeed)
        let clampedY = min(4.0, verticalSpeed)
        let clampedX = max(-8.0, min(8.0, horizontalSpeed))
        return SIMD3<Float>(clampedX, clampedY, -clampedZ)
    }

    /// Build an orientation that points the dart's local +Y (tip) forward, constraining roll so it doesn't spin sideways.
    private func orientationForVelocity(_ v: SIMD3<Float>) -> simd_quatf {
        let len = simd_length(v)
        if len < 0.01 { return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)) }
        let biasDown: SIMD3<Float> = [0, -0.2, 0] // nudge orientation slightly downward so tip leads
        let forwardWorld = simd_normalize(v + biasDown)
        let worldUp = SIMD3<Float>(0, 1, 0)
        var rightWorld = simd_cross(forwardWorld, worldUp)
        if simd_length_squared(rightWorld) < 1e-6 {
            rightWorld = SIMD3<Float>(1, 0, 0)
        } else {
            rightWorld = simd_normalize(rightWorld)
        }
        let adjustedUp = simd_normalize(simd_cross(rightWorld, forwardWorld))
        // Local basis: X=right, Y=forward (dart tip), Z=up. Model geometry is built along +Y.
        let rotMatrix = simd_float3x3(columns: (rightWorld, forwardWorld, adjustedUp))
        return simd_quatf(rotMatrix)
    }

    func updateHeldDart(translation: CGPoint) {
        guard let dart = currentDart else { return }
        // Map screen points to meters with tuned sensitivity.
        let sensitivity: Float = 0.0025
        let metersX = Float(translation.x) * sensitivity
        let metersY = Float(-translation.y) * sensitivity
        // Keep the held dart in a narrow vertical band so taps don't drop it to the floor.
        //let clampedY = max(0.0, min(0.6, readyDartBasePosition.y + metersY))
        dart.position = [readyDartBasePosition.x + metersX,
                         readyDartBasePosition.y + metersY,
                         readyDartBasePosition.z]
    }

    func ensureReadyDart() {
        if currentDart == nil {
            spawnReadyDart()
        }
    }

    func syncHistory(_ history: [DartThrow]) {
        // SwiftUI is authoritative for stuck darts; RealityKit only shows the live dart.
        if history.isEmpty {
            clearBoardDarts()
        }
    }

    /// Remove all dart entities (local, stuck, remote) and reset ready dart.
    func clearBoardDarts() {
        remoteDarts.values.forEach { $0.removeFromParent() }
        remoteDarts.removeAll()
        currentDart?.removeFromParent()
        currentDart = nil

        func removeDartsRecursively(from entity: Entity) {
            for child in Array(entity.children) {
                let lower = child.name.lowercased()
                if lower.hasPrefix("dart") || lower.hasPrefix("remote-dart") {
                    child.removeFromParent()
                } else {
                    removeDartsRecursively(from: child)
                }
            }
        }

        if let board { removeDartsRecursively(from: board) }
        if let anchor { removeDartsRecursively(from: anchor) }

        spawnReadyDart()
    }

    func spawnReadyDart() {
        guard let anchor else { return }
        currentDart?.removeFromParent()

        let dart = makeRedDartEntity()
        dart.name = "dart-\(UUID().uuidString)"
        dart.position = readyDartBasePosition // near camera, slightly low/forward
        // Default orientation: nose points toward the board using the same forward-alignment as flight updates.
        dart.orientation = orientationForVelocity(SIMD3<Float>(0, 0, -1))
        if var body = dart.components[PhysicsBodyComponent.self] {
            body.mode = .kinematic
            body.massProperties = .init(mass: 0.14)
            dart.components.set(body)
        } else {
            dart.components.set(PhysicsBodyComponent(massProperties: .init(mass: 0.14), material: .default, mode: .kinematic))
        }
        if dart.components[PhysicsMotionComponent.self] == nil {
            dart.components.set(PhysicsMotionComponent())
        }

        anchor.addChild(dart)
        currentDart = dart
    }

    private func makeRedDartEntity() -> ModelEntity {
        let root = ModelEntity()

        // Body
        let bodyMesh = MeshResource.generateCylinder(height: 0.15, radius: 0.015)
        let bodyMaterial = SimpleMaterial(color: .red, roughness: 0.2, isMetallic: false)
        let body = ModelEntity(mesh: bodyMesh, materials: [bodyMaterial])

        // Tip (front)
        let tipMesh = MeshResource.generateCone(height: 0.08, radius: 0.01)
        let tipMaterial = SimpleMaterial(color: .white, roughness: 0.2, isMetallic: true)
        let tip = ModelEntity(mesh: tipMesh, materials: [tipMaterial])
        tip.position = [0, 0.12, 0]

        // Decorative joint sphere
        let jointMesh = MeshResource.generateSphere(radius: 0.012)
        let jointMaterial = SimpleMaterial(color: .gray, roughness: 0.2, isMetallic: true)
        let joint = ModelEntity(mesh: jointMesh, materials: [jointMaterial])
        joint.position = [0, 0.06, 0]

        // Flights (crossed vanes) using cones for a more 3D look
        let flightMesh = MeshResource.generateCone(height: 0.08, radius: 0.03)
        let flightMaterial = SimpleMaterial(color: .red, roughness: 0.25, isMetallic: false)
        let flight1 = ModelEntity(mesh: flightMesh, materials: [flightMaterial])
        flight1.position = [0, -0.08, 0]
        flight1.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        let flight2 = ModelEntity(mesh: flightMesh, materials: [flightMaterial])
        flight2.position = [0, -0.08, 0]
        flight2.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])

        [body, tip, joint, flight1, flight2].forEach { root.addChild($0) }

        // Collider biased slightly toward the tip so penetration depth stays consistent across pitch angles.
        let filter = CollisionFilter(group: dartCollisionGroup, mask: boardCollisionGroup)
        let tipBiasedCapsule = ShapeResource
            .generateCapsule(height: 0.26, radius: 0.02)
            .offsetBy(translation: SIMD3<Float>(0, 0.06, 0))
        root.components.set(CollisionComponent(shapes: [tipBiasedCapsule], mode: .default, filter: filter))
        root.components.set(PhysicsBodyComponent(massProperties: .init(mass: 0.05), material: .default, mode: .kinematic))

        return root
    }

    /// Apply incoming remote flight transforms to kinematic darts. RealityKit is only visual for remote darts.
    func syncRemoteFlights(_ flights: [UUID: DartFlightSnapshot]) {
        guard let anchor else { return }
        // Remove stale darts
        let incomingIds = Set(flights.keys)
        let existingIds = Set(remoteDarts.keys)
        for id in existingIds.subtracting(incomingIds) {
            remoteDarts[id]?.removeFromParent()
            remoteDarts.removeValue(forKey: id)
        }
        // Update or create darts
        for (id, snap) in flights {
            let dart = remoteDarts[id] ?? {
                let d = makeRedDartEntity()
                d.name = "remote-dart-\(id)"
                d.components[PhysicsBodyComponent.self]?.mode = .kinematic
                anchor.addChild(d)
                remoteDarts[id] = d
                return d
            }()
            if snap.position.count == 3 {
                dart.position = [snap.position[0], snap.position[1], snap.position[2]]
            }
            if snap.orientation.count == 4 {
                let quat = simd_quatf(ix: snap.orientation[0], iy: snap.orientation[1], iz: snap.orientation[2], r: snap.orientation[3])
                dart.orientation = quat
            }
        }
    }

    /// Animates the camera toward the hit, then back to the base position. Moves to the left of the dart and rotates to look at the hit.
    func animateCameraToHit(at location: CGPoint) {
        guard let cameraEntity, let board else { return }
        // Base/default camera position (higher and farther for a wider shot).
        let basePos = cameraHomePosition
        let baseOrientation = cameraHomeOrientation
        isCameraAnimatingBack = true
        
        // Map normalized hit (radius=1) to world space near the board center (z ~ board plane).
        let hitLocal = SIMD3<Float>(Float(location.x) * (boardSize / 2), Float(location.y) * (boardSize / 2), 0)
        let hitWorld = board.convert(position: hitLocal, to: nil)
        // Offset left/back/up of the dart for a side angle view and keep distance.
        let targetCamPos = hitWorld + SIMD3<Float>(-1.0, 0.25, 1.4)
        // Build a rotation that points the camera forward (-Z) toward the hit point.
        let lookDir = simd_normalize(hitWorld - targetCamPos)
        let targetOrientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: lookDir)
        let targetTransform = Transform(rotation: targetOrientation, translation: targetCamPos)
        cameraEntity.move(to: targetTransform, relativeTo: nil, duration: 0.6, timingFunction: .easeInOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let cam = self?.cameraEntity else { return }
            // Reset to base pos/orientation (default facing -Z).
            cam.move(to: Transform(scale: .one, rotation: baseOrientation, translation: basePos),
                     relativeTo: nil,
                     duration: 0.6,
                     timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                self?.isCameraAnimatingBack = false
            }
        }
    }

    private func setupBoard(in anchor: AnchorEntity) {
        let boardRoot = ModelEntity()
        boardRoot.position = [0, 1.2, -3.4] // Closer/smaller board to reduce tunneling while keeping similar framing.

        // Body (thick disk)
        let boardThickness = boardSize * 0.05
        let bodyMesh = MeshResource.generateCylinder(height: boardThickness, radius: boardSize / 2)
        let bodyMaterial = SimpleMaterial(color: .black, roughness: 0.8, isMetallic: false)
        let body = ModelEntity(mesh: bodyMesh, materials: [bodyMaterial])
        body.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0]) // Rotation of the board
        boardRoot.addChild(body)

        // Face
        let faceMesh = MeshResource.generatePlane(width: boardSize, height: boardSize)
        let face = ModelEntity(mesh: faceMesh, materials: [Self.makeBoardMaterial(diameter: boardSize)])
        face.position = [0, 0, boardThickness / 2 + 0.001]
        boardRoot.addChild(face)

        // Spider rings
        let rings: [(Float, Float)] = [
            ((boardSize / 2) * 0.8, 0.008),  // double outer at 80%
            ((boardSize / 2) * 0.48, 0.008), // triple outer
            ((boardSize / 2) * 0.12, 0.01),  // outer bull
            ((boardSize / 2) * 0.06, 0.01)   // inner bull
        ]
        for (radius, thickness) in rings {
            let ring = createMetalRing(radius: radius, thickness: thickness)
            ring.position = [0, 0, boardThickness / 2 + 0.01] // slightly above the face
            boardRoot.addChild(ring)
        }

        // Colliders inset behind the visual face with overhang/depth to catch fast darts near edges.
        let boardFilter = CollisionFilter(group: boardCollisionGroup, mask: dartCollisionGroup)
        let faceZ = boardThickness / 2 + 0.001

        // Front thin collider: minimal inset to allow visible tip penetration.
        let frontCollider = ModelEntity()
        let frontDepth: Float = 0.02
        // Move the front collider further behind the texture so the tip sinks in more before contact.
        frontCollider.position = [0, 0, faceZ - 0.12 - (frontDepth / 2)]
        frontCollider.components.set(CollisionComponent(shapes: [.generateBox(size: [boardSize * 1.02, boardSize * 1.02, frontDepth])], mode: .default, filter: boardFilter))
        frontCollider.components.set(PhysicsBodyComponent(mode: .static))
        boardRoot.addChild(frontCollider)

        // Back catch collider: deeper and slightly larger to prevent tunneling at steep angles/top-bottom.
        let backCollider = ModelEntity()
        let backDepth: Float = 0.16
        backCollider.position = [0, 0, faceZ - 0.25 - (backDepth / 2)]
        backCollider.components.set(CollisionComponent(shapes: [.generateBox(size: [boardSize * 1.05, boardSize * 1.05, backDepth])], mode: .default, filter: boardFilter))
        backCollider.components.set(PhysicsBodyComponent(mode: .static))
        boardRoot.addChild(backCollider)
        anchor.addChild(boardRoot)
        self.board = boardRoot
    }

    private func setupRoom(in anchor: AnchorEntity) {
        // Back wall
        let wallMesh = MeshResource.generateBox(size: [20, 30, 0.3])
        let wallMaterial = SimpleMaterial(color: UIColor(red: 0.35, green: 0.2, blue: 0.1, alpha: 1.0), roughness: 0.8, isMetallic: false)
        let wall = ModelEntity(mesh: wallMesh, materials: [wallMaterial])
        wall.position = [0, 1.0, -4.0]
        wall.components.set(PhysicsBodyComponent(mode: .static))
        anchor.addChild(wall)

        // Floor
        let floorMesh = MeshResource.generateBox(size: [20, 0.1, 20])
        let floorMaterial = SimpleMaterial(color: UIColor.brown.withAlphaComponent(0.9), roughness: 0.9, isMetallic: false)
        let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        // Floor height reference. +Y raises it, -Y lowers it. Lowered to stay out of dart flight path.
        floor.position = [0, -15.0, 0] // push the floor well below the camera/framing so it stays out of view
        floor.components.set(PhysicsBodyComponent(mode: .static))
        anchor.addChild(floor)
    }

    private func setupLighting(in scene: RealityKit.Scene) {
        let light = DirectionalLight()
        light.light.intensity = 2200
        light.light.color = .white
        light.look(at: [0, 1.0, -1.5], from: [0, 2.0, -1.0], relativeTo: nil)
        let lightAnchor = AnchorEntity(world: .zero)
        lightAnchor.addChild(light)
        scene.addAnchor(lightAnchor)
    }

    private func createMetalRing(radius: Float, thickness: Float) -> ModelEntity {
        let ring = ModelEntity()
        let segments = 48
        let material = SimpleMaterial(color: UIColor(white: 0.9, alpha: 1.0), roughness: 0.1, isMetallic: true)
        let segmentSize = SIMD3<Float>(thickness * 2.2, thickness * 0.2, 0.005)
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * (.pi * 2)
            let segment = ModelEntity(mesh: .generateBox(size: segmentSize), materials: [material])
            let x = cos(angle) * radius
            let y = sin(angle) * radius
            segment.position = [x, y, 0]
            segment.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
            ring.addChild(segment)
        }
        return ring
    }

    private func handleCollision(_ event: CollisionEvents.Began) {
        guard
            let board,
            let dart = (event.entityA.name.hasPrefix("dart") ? event.entityA : event.entityB.name.hasPrefix("dart") ? event.entityB : nil) as? ModelEntity
        else { return }
        let isBoardHit: (Entity) -> Bool = { entity in
            var current: Entity? = entity
            while let node = current {
                if node === board { return true }
                current = node.parent
            }
            return false
        }
        guard isBoardHit(event.entityA) || isBoardHit(event.entityB) else { return }

        // Stop all motion immediately and lock in place so it appears stuck in the board.
        // Stop all motion immediately and lock in place so it appears stuck in the board.
        dart.components[PhysicsMotionComponent.self]?.linearVelocity = .zero
        dart.components[PhysicsMotionComponent.self]?.angularVelocity = .zero
        if var body = dart.components[PhysicsBodyComponent.self] {
            body.mode = .static
            dart.components.set(body)
        }
        // Optional: parent to the board so it moves with the board if repositioned.
        dart.setParent(board, preservingWorldTransform: true)
        isThrowInFlight = false

        // Compute impact point in board-local space normalized by board radius (radius = boardSize/2).
        // (0,0) is board center; magnitude 1.0 lies on the board edge.
        let local = dart.position(relativeTo: board)
        let radius = boardSize / 2
        let hitPoint = CGPoint(x: CGFloat(local.x / radius), y: CGFloat(local.y / radius))

        if let dartId = activeDartId {
            onFlightLanded?(dartId, hitPoint)
        }
        activeDartId = nil

        // Camera zoom/rotate for notable hits (bulls or double/triple) if enabled.
        if enableFlightCameraAnimation {
            animateCameraToHit(at: hitPoint)
        }

        onHit?(hitPoint)
    }
}

private extension DartsRealityController {
    static func makeBoardMaterial(diameter: Float) -> UnlitMaterial {
        let size: CGFloat = 1024
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return UnlitMaterial(color: .black) }
        
        let center = CGPoint(x: size/2, y: size/2)
        let fullRadius = size / 2
        
        // LAYOUT CONSTANTS (Ratios relative to full image radius)
        // The playable area (Double Ring Outer) ends at 80% to leave room for numbers.
        let playableRadius = fullRadius * 0.80
        
        // Standard Dartboard Ratios relative to the playable radius
        // Double Ring: 170mm outer / 170mm = 1.0
        // Triple Ring: 107mm outer / 170mm = 0.63
        // Outer Bull: 16mm / 170mm = 0.094
        // Inner Bull: 6.35mm / 170mm = 0.037
        // Ring Width: 8mm / 170mm = 0.047
        
        let rDoubleOuter = playableRadius
        let rDoubleInner = playableRadius * 0.953
        let rTripleOuter = playableRadius * 0.63
        let rTripleInner = playableRadius * 0.58
        let rOuterBull   = playableRadius * 0.094
        let rInnerBull   = playableRadius * 0.037
        
        // COLORS (High Contrast)
        let cBlack = UIColor.black
        let cWhite = UIColor.white
        let cRed   = UIColor(red: 0.9, green: 0.05, blue: 0.05, alpha: 1.0)
        let cGreen = UIColor(red: 0.0, green: 0.65, blue: 0.0, alpha: 1.0)
        
        // 1. Draw Base Background (The Number Ring)
        ctx.setFillColor(cBlack.cgColor)
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        
        // 2. Draw Slices
        let numbers = [20,1,18,4,13,6,10,15,2,17,3,19,7,16,8,11,14,9,12,5]
        let sliceAngle = CGFloat.pi * 2 / 20
        
        for (i, _) in numbers.enumerated() {
            let angle = -CGFloat.pi/2 + (CGFloat(i) * sliceAngle)
            
            // "20" (index 0) is Black. "1" (index 1) is White.
            let isBlackSlice = (i % 2 == 0)
            let sliceColor = isBlackSlice ? cBlack : cWhite
            let ringColor = isBlackSlice ? cRed : cGreen
            
            // Draw full wedge (Single)
            ctx.setFillColor(sliceColor.cgColor)
            ctx.move(to: center)
            ctx.addArc(center: center, radius: rDoubleOuter, startAngle: angle - sliceAngle/2, endAngle: angle + sliceAngle/2, clockwise: false)
            ctx.fillPath()
            
            // Helper to draw ring segment
            func drawSeg(_ rOut: CGFloat, _ rIn: CGFloat, c: UIColor) {
                ctx.setFillColor(c.cgColor)
                let p = CGMutablePath()
                p.addArc(center: center, radius: rOut, startAngle: angle - sliceAngle/2, endAngle: angle + sliceAngle/2, clockwise: false)
                p.addArc(center: center, radius: rIn, startAngle: angle + sliceAngle/2, endAngle: angle - sliceAngle/2, clockwise: true)
                p.closeSubpath()
                ctx.addPath(p)
                ctx.fillPath()
            }
            
            // Draw Double & Triple segments
            drawSeg(rDoubleOuter, rDoubleInner, c: ringColor)
            drawSeg(rTripleOuter, rTripleInner, c: ringColor)
        }
        
        // 3. Draw Bulls
        ctx.setFillColor(cGreen.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - rOuterBull, y: center.y - rOuterBull, width: rOuterBull*2, height: rOuterBull*2))
        ctx.setFillColor(cRed.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - rInnerBull, y: center.y - rInnerBull, width: rInnerBull*2, height: rInnerBull*2))
        
        // 4. Draw Numbers (On the black rim)
        // Center the numbers in the black band (between playable radius and full edge)
        let numberRadius = (playableRadius + fullRadius) / 2
        let font = UIFont.systemFont(ofSize: 60, weight: .heavy) // Thicker, larger font
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        
        for (i, n) in numbers.enumerated() {
            let str = "\(n)" as NSString
            let textSize = str.size(withAttributes: textAttrs)
            let angle = -CGFloat.pi/2 + (CGFloat(i) * sliceAngle)
            
            // Position text centered on the angle
            let x = center.x + cos(angle) * numberRadius - (textSize.width / 2)
            let y = center.y + sin(angle) * numberRadius - (textSize.height / 2)
            
            // Rotate numbers to follow the rim.
            ctx.saveGState()
            ctx.translateBy(x: x + textSize.width/2, y: y + textSize.height/2)
            ctx.rotate(by: angle + .pi/2)
            str.draw(at: CGPoint(x: -textSize.width/2, y: -textSize.height/2), withAttributes: textAttrs)
            ctx.restoreGState()
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        
        var mat = UnlitMaterial()
        if let cg = image.cgImage, let tex = try? TextureResource(image: cg, options: .init(semantic: .color)) {
            mat.color = .init(tint: .white, texture: .init(tex))
        }
        mat.blending = .transparent(opacity: .init(scale: 1.0))
        return mat
    }
}
