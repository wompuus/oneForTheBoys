import SwiftUI

func crazyOpponentPosition(index: Int, total: Int, in size: CGSize) -> CGPoint {
    let cx = size.width / 2
    let cy = size.height * 0.22
    let radius = min(size.width, size.height) * 0.34

    let angle = crazyOpponentAngle(index: index, total: total)

    let x = cx + cos(angle) * radius
    let y = cy - sin(angle) * radius
    return CGPoint(x: x, y: y)
}

func crazyOpponentAngle(index: Int, total: Int) -> CGFloat {
    let startAngle = CGFloat.pi * 5.0 / 6.0
    let endAngle   = CGFloat.pi * 1.0 / 6.0
    let t: CGFloat = total <= 1 ? 0.5 : CGFloat(index) / CGFloat(max(total - 1, 1))
    return startAngle + (endAngle - startAngle) * t
}

func crazyDeckPosition(in size: CGSize) -> CGPoint {
    CGPoint(x: size.width * 0.35, y: size.height * 0.45)
}

func crazyDiscardPosition(in size: CGSize) -> CGPoint {
    CGPoint(x: size.width * 0.65, y: size.height * 0.45)
}

func crazySortHand(_ hand: [UNOCard]) -> [UNOCard] {
    hand.sorted { lhs, rhs in
        let colorRank: (UNOColor) -> Int = { color in
            switch color {
            case .red: return 0
            case .blue: return 1
            case .yellow: return 2
            case .green: return 3
            case .wild: return 4
            }
        }

        let valueRank: (UNOValue) -> Int = { value in
            switch value {
            case .number(let n): return n
            case .skip:          return 20
            case .reverse:       return 21
            case .draw2:         return 22
            case .wild:          return 30
            case .wildDraw4:     return 31
            }
        }

        let lc = colorRank(lhs.color)
        let rc = colorRank(rhs.color)
        if lc != rc { return lc < rc }

        let lv = valueRank(lhs.value)
        let rv = valueRank(rhs.value)
        if lv != rv { return lv < rv }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
