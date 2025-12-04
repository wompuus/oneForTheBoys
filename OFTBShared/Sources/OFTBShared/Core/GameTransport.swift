import Foundation

@available(iOS 13.0, macOS 10.15, *)
public protocol GameTransport {
    func send<A: Codable>(_ action: A) async
    func broadcast<S: Codable>(_ state: S) async
}
