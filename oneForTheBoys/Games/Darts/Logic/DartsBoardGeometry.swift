import Foundation
import CoreGraphics

enum DartBoardSegment: Codable, Equatable {
    case miss
    case single(Int)
    case double(Int)
    case triple(Int)
    case outerBull
    case innerBull

    var scoreValue: Int {
        switch self {
        case .miss: return 0
        case .single(let v): return v
        case .double(let v): return v * 2
        case .triple(let v): return v * 3
        case .outerBull: return 25
        case .innerBull: return 50
        }
    }

    var isDoubleOutHit: Bool {
        switch self {
        case .double, .innerBull:
            return true
        default:
            return false
        }
    }

    /// Text label for quick display in the UI.
    var displayText: String {
        switch self {
        case .miss: return "Miss"
        case .single(let v): return "\(v)"
        case .double(let v): return "D\(v)"
        case .triple(let v): return "T\(v)"
        case .outerBull: return "Outer Bull"
        case .innerBull: return "Bull"
        }
    }
}

/// Calculates which board segment was hit given a point relative to the board center.
/// - Parameters:
///   - point: Point in board coordinates where (0,0) is center.
///   - boardRadius: Radius of the board in the same units.
func calculateSegment(at point: CGPoint, boardRadius: CGFloat) -> DartBoardSegment {
    let distance = hypot(point.x, point.y)
    guard distance <= boardRadius else { return .miss }

    // Ring thresholds (normalized to new visual layout)
    // Tightened ring thresholds to better match the rendered board (playable radius ~0.8 of full face).
    let bullRadius = boardRadius * 0.05
    let outerBullRadius = boardRadius * 0.10
    let tripleInner = boardRadius * 0.45
    let tripleOuter = boardRadius * 0.53
    let doubleInner = boardRadius * 0.72
    let doubleOuter = boardRadius * 0.78

    if distance <= bullRadius {
        return .innerBull
    } else if distance <= outerBullRadius {
        return .outerBull
    }

    // Angle to slice
    let angle = normalizedAngle(point: point)
    let sliceSize = 2 * CGFloat.pi / 20
    // Use rounding to the nearest wedge center to avoid edge misreads.
    let sliceIndex = Int((angle / sliceSize).rounded()) % 20
    let number = dartNumbers[sliceIndex]

    if distance > doubleOuter && distance <= boardRadius {
        return .miss // hits on the number ring count as miss
    } else if distance >= doubleInner && distance <= doubleOuter {
        return .double(number)
    } else if distance >= tripleInner && distance <= tripleOuter {
        return .triple(number)
    } else {
        return .single(number)
    }
}

private func normalizedAngle(point: CGPoint) -> CGFloat {
    // atan2 returns radians relative to +x axis; rotate so 20 is at top (angle 0) and mirror to match board layout.
    var theta = (.pi / 2) - atan2(point.y, point.x) // top -> 0, clockwise
    if theta < 0 { theta += 2 * .pi }
    return theta
}

private let dartNumbers: [Int] = [
    20, 1, 18, 4, 13,
    6, 10, 15, 2, 17,
    3, 19, 7, 16, 8,
    11, 14, 9, 12, 5
]
