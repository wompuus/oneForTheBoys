import Foundation
import OFTBShared

/// Dumb, minimal WebSocket client just to prove we can talk to the server.
/// We will plug this into GameTransport later.
final class WebSocketClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)
    }

    func connect() {
        // TODO: replace with your Mac/server IP on the same network.
        // Example: ws://192.168.1.50:8080/crazy-eights
        guard let url = URL(string: "wss://oftb-server.fly.dev/crazy-eights") else {
            print("WebSocket: invalid URL")
            return
        }

        let task = session.webSocketTask(with: url)
        webSocketTask = task

        print("WebSocket: connecting to \(url)")
        task.resume()

        // Start listening for server messages
        listen()
        sendTestJoin()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    /// For now, send raw Data. We’ll switch this to CrazyEightsClientMessage later.
    func send(data: Data) {
        guard let task = webSocketTask else {
            print("WebSocket: no active connection")
            return
        }

        task.send(.data(data)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    private func listen() {
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error)")
            case .success(let message):
                switch message {
                case .data(let data):
                    print("WebSocket received binary (\(data.count) bytes)")
                case .string(let text):
                    print("WebSocket received text: \(text)")
                @unknown default:
                    print("WebSocket received unknown message")
                }
            }

            // Keep listening for the next message
            self?.listen()
        }
    }

    private func sendTestJoin() {
        let player = PublicPlayerSnapshot(
            id: UUID(),
            displayName: "DebugWyatt",
            avatar: nil
        )

        let message = CrazyEightsClientMessage.joinRoom(
            roomCode: "TEST",
            player: player
        )

        guard let data = try? JSONEncoder().encode(message) else {
            print("WebSocket: failed to encode join message")
            return
        }

        print("WebSocket: sending joinRoom TEST")
        send(data: data)
    }
}
