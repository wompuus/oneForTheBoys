import Foundation
import OFTBShared

final class WebSocketTransport: NSObject, GameTransport {
    private let roomCode: String
    private let playerSnapshot: PublicPlayerSnapshot
    private let serverURL: URL
    private let isHost: Bool
    private var task: URLSessionWebSocketTask?
    private let session: URLSession

    var onStateReceived: ((CrazyEightsGameState) -> Void)?
    var onError: ((String) -> Void)?
    var onReadySnapshot: (([UUID]) -> Void)?

    init(roomCode: String, playerSnapshot: PublicPlayerSnapshot, serverURL: URL, isHost: Bool) {
        self.roomCode = roomCode
        self.playerSnapshot = playerSnapshot
        self.serverURL = serverURL
        self.isHost = isHost
        self.session = URLSession(configuration: .default)
    }

    func connect() {
        let task = session.webSocketTask(with: serverURL)
        self.task = task
        print("WebSocketTransport: connecting to \(serverURL)")
        task.resume()
        listen()
        if isHost {
            sendMessage(.createRoom(roomCode: roomCode, host: playerSnapshot, isPublic: true))
        }
        sendMessage(.joinRoom(roomCode: roomCode, player: playerSnapshot))
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    deinit {
        task?.cancel(with: .goingAway, reason: nil)
    }

    func send<A: Codable>(_ action: A) async {
        guard let crazyAction = action as? CrazyEightsAction else { return }
        sendMessage(.sendAction(roomCode: roomCode, playerId: playerSnapshot.id, action: crazyAction))
    }

    func broadcast<S: Codable>(_ state: S) async {
        // Client does not broadcast state; server is authoritative.
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.onError?("Receive error: \(error)")
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handle(data: data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handle(data: data)
                    }
                @unknown default:
                    break
                }
                self.listen()
            }
        }
    }

    private func handle(data: Data) {
        guard let message = try? JSONDecoder().decode(CrazyEightsServerMessage.self, from: data) else { return }
        switch message {
        case .roomJoined(_, _, let state):
            onStateReceived?(state)
        case .stateUpdated(let state):
            onStateReceived?(state)
        case .error(let message):
            onError?("Server error: \(message)")
        case .roomList:
            break
        case .readySnapshot(let readyIds):
            onReadySnapshot?(readyIds)
        }
    }

    private func sendMessage(_ message: CrazyEightsClientMessage) {
        guard let data = try? JSONEncoder().encode(message) else {
            onError?("Failed to encode message")
            return
        }
        task?.send(.data(data)) { [weak self] error in
            if let error = error {
                self?.onError?("Send error: \(error)")
            }
        }
    }

    func sendReady(roomCode: String, playerId: UUID, isReady: Bool) {
        sendMessage(.readyUpdate(roomCode: roomCode, playerId: playerId, isReady: isReady))
    }
}
