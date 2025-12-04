import Foundation

public enum UNOColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case red, yellow, green, blue, wild
    public var id: String { rawValue }
    public var display: String { rawValue.capitalized }
}

public enum UNOValue: Codable, Equatable, Hashable, Sendable {
    case number(Int)      // 0–9
    case skip
    case reverse
    case draw2
    case wild
    case wildDraw4
    case fog
}

extension UNOValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .number(let n): return String(n)
        case .skip: return "Skip"
        case .reverse: return "Reverse"
        case .draw2: return "+2"
        case .wild: return "Wild"
        case .wildDraw4: return "Wild+4"
        case .fog: return "Fog"
        }
    }
}

public struct UNOCard: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var color: UNOColor
    public var value: UNOValue

    public init(id: UUID = UUID(), color: UNOColor, value: UNOValue) {
        self.id = id
        self.color = color
        self.value = value
    }
}
