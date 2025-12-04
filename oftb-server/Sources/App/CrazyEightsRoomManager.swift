import Vapor
import OFTBShared
import NIOConcurrencyHelpers

struct ConnectedPlayer {
    let snapshot: PublicPlayerSnapshot
    let socket: WebSocket
}

final class CrazyEightsRoom {
    let code: String
    var players: [UUID: ConnectedPlayer] = [:]
    var state: CrazyEightsGameState?
    var isPublic: Bool
    var hostSnapshot: PublicPlayerSnapshot?
    var settings: CrazyEightsSettings = CrazyEightsSettings()
    var readyPlayers: Set<UUID> = []

    init(code: String, isPublic: Bool = true) {
        self.code = code
        self.isPublic = isPublic
    }
}

final class CrazyEightsRoomManager: @unchecked Sendable {
    private var rooms: [String: CrazyEightsRoom] = [:]
    private let lock = NIOLock()

    func handle(message: CrazyEightsClientMessage, from ws: WebSocket) {
        switch message {
        case .createRoom(let roomCode, let host, let isPublic):
            _ = createRoom(roomCode: roomCode, host: host, isPublic: isPublic)
        case .joinRoom(let roomCode, let player):
            join(roomCode: roomCode, player: player, ws: ws)
        case .sendAction(let roomCode, _, let action):
            applyAction(roomCode: roomCode, action: action)
        case .requestRoomList:
            sendRoomList(to: ws)
        case .readyUpdate(let roomCode, let playerId, let isReady):
            updateReady(roomCode: roomCode, playerId: playerId, isReady: isReady)
        }
    }

    func createRoom(roomCode: String, host: PublicPlayerSnapshot, isPublic: Bool = true) -> CrazyEightsRoom? {
        lock.withLock {
            if rooms[roomCode] != nil { return nil }
            let room = CrazyEightsRoom(code: roomCode, isPublic: isPublic)
            room.hostSnapshot = host
            rooms[roomCode] = room
            print("[Server] Created room \(roomCode) host=\(host.displayName)")
            return room
        }
    }

    private func join(roomCode: String, player: PublicPlayerSnapshot, ws: WebSocket) {
        lock.withLock {
            guard let room = rooms[roomCode] else {
                let errorMessage = CrazyEightsServerMessage.error(message: "Room \(roomCode) does not exist.")
                send(message: errorMessage, to: ws)
                print("[Server] Join failed: \(roomCode) not found for \(player.displayName)")
                return
            }

            room.players[player.id] = ConnectedPlayer(snapshot: player, socket: ws)
            if room.hostSnapshot == nil {
                room.hostSnapshot = player
            }
            room.readyPlayers.remove(player.id)

            // Rebuild pre-game state when not started so late joiners are included.
            if room.state?.started != true {
                let players = room.players.values
                    .map { $0.snapshot }
                    .sorted { lhs, rhs in
                        if lhs.displayName == rhs.displayName {
                            return lhs.id.uuidString < rhs.id.uuidString
                        }
                        return lhs.displayName < rhs.displayName
                    }
                    .map {
                        CrazyEightsPlayer(
                            id: $0.id,
                            name: $0.displayName,
                            deviceName: $0.displayName,
                            hand: [],
                            avatar: $0.avatar
                        )
                    }
                let settings = room.state?.config ?? room.settings
                room.settings = settings
                room.state = CrazyEightsEngine.initialState(players: players, settings: settings)
            }

            rooms[roomCode] = room

            guard let state = room.state else { return }
            let serverMessage = CrazyEightsServerMessage.roomJoined(
                roomCode: roomCode,
                players: room.players.values.map { $0.snapshot },
                state: state
            )
            print("[Server] \(player.displayName) joined \(roomCode). Players=\(room.players.count)")
            broadcast(serverMessage, in: roomCode)
            broadcastReady(roomCode: roomCode)
        }
    }

    private func applyAction(roomCode: String, action: CrazyEightsAction) {
        lock.withLock {
            guard let room = rooms[roomCode],
                  let currentState = room.state
            else { return }

            // Basic membership check to prevent spoofed player IDs on actions that carry one.
            switch action {
            case .intentDraw(let pid),
                 .callUno(let pid),
                 .blindPlayRandom(let pid),
                 .leave(let pid):
                guard room.players.keys.contains(pid) else { return }
            case .intentPlay(_, _, let targetId):
                if let tid = targetId {
                    guard room.players.keys.contains(tid) else { return }
                }
            case .swapHand(let targetId):
                guard room.players.keys.contains(targetId) else { return }
            default:
                break
            }

            // If game not started yet and host sends startRound, rebuild state with all joined players.
            var workingState = currentState
            if currentState.started == false,
               case .startRound = action {
                let players = room.players.values
                    .map { $0.snapshot }
                    .sorted { lhs, rhs in
                        if lhs.displayName == rhs.displayName {
                            return lhs.id.uuidString < rhs.id.uuidString
                        }
                        return lhs.displayName < rhs.displayName
                    }
                    .map {
                        CrazyEightsPlayer(
                            id: $0.id,
                            name: $0.displayName,
                            deviceName: $0.displayName,
                            hand: [],
                            avatar: $0.avatar
                        )
                    }
                workingState = CrazyEightsEngine.initialState(players: players, settings: room.settings)
            }

            let newState = CrazyEightsEngine.reducer(
                state: workingState,
                action: action,
                isHost: true
            )
            room.state = newState
            rooms[roomCode] = room

            let msg = CrazyEightsServerMessage.stateUpdated(state: newState)
            broadcast(msg, in: roomCode)
            // Update ready list if someone leaves.
            if case .leave(let pid) = action {
                let name = room.players[pid]?.snapshot.displayName ?? pid.uuidString
                room.players.removeValue(forKey: pid)
                room.readyPlayers.remove(pid)
                if room.players.isEmpty {
                    print("[Server] Room \(roomCode) emptied, deleting")
                    rooms.removeValue(forKey: roomCode)
                    return
                }
                if room.hostSnapshot?.id == pid {
                    room.hostSnapshot = room.players.values.first?.snapshot
                    print("[Server] Host left \(roomCode); new host=\(room.hostSnapshot?.displayName ?? "nil")")
                }
                print("[Server] \(name) left \(roomCode). Players=\(room.players.count)")
                broadcastReady(roomCode: roomCode)
            }
        }
    }

    private func updateReady(roomCode: String, playerId: UUID, isReady: Bool) {
        lock.withLock {
            guard let room = rooms[roomCode] else { return }
            if isReady {
                room.readyPlayers.insert(playerId)
            } else {
                room.readyPlayers.remove(playerId)
            }
            rooms[roomCode] = room
            broadcastReady(roomCode: roomCode)
        }
    }

    func handleDisconnect(_ ws: WebSocket) {
        lock.withLock {
            for (code, room) in rooms {
                if let entry = room.players.first(where: { $0.value.socket === ws }) {
                    let pid = entry.key
                    let name = entry.value.snapshot.displayName
                    room.players.removeValue(forKey: pid)
                    room.readyPlayers.remove(pid)
                    if room.players.isEmpty {
                        print("[Server] Room \(code) emptied on disconnect, deleting")
                        rooms.removeValue(forKey: code)
                        return
                    }
                    if room.hostSnapshot?.id == pid {
                        room.hostSnapshot = room.players.values.first?.snapshot
                        print("[Server] Host disconnected in \(code); new host=\(room.hostSnapshot?.displayName ?? "nil")")
                    }
                    print("[Server] \(name) disconnected from \(code). Players=\(room.players.count)")
                    broadcastReady(roomCode: code)
                    return
                }
            }
        }
    }

    private func broadcast(_ message: CrazyEightsServerMessage, in roomCode: String) {
        guard let room = rooms[roomCode] else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }

        for (pid, player) in room.players {
            if player.socket.isClosed {
                room.players.removeValue(forKey: pid)
                room.readyPlayers.remove(pid)
                continue
            }
            player.socket.send(raw: data, opcode: .binary)
        }
        if room.players.isEmpty {
            rooms.removeValue(forKey: roomCode)
        }
    }

    private func broadcastReady(roomCode: String) {
        guard let room = rooms[roomCode] else { return }
        let message = CrazyEightsServerMessage.readySnapshot(Array(room.readyPlayers))
        broadcast(message, in: roomCode)
    }

    private func sendRoomList(to ws: WebSocket) {
        let summaries: [CrazyEightsRoomSummary] = lock.withLock {
            rooms.values
                .filter { $0.isPublic && !$0.players.isEmpty }
                .map { room in
                    let hostName = room.hostSnapshot?.displayName ?? "Host"
                    let playerCount = room.players.count
                    return CrazyEightsRoomSummary(
                        roomCode: room.code,
                        hostName: hostName,
                        playerCount: playerCount,
                        isPublic: room.isPublic
                    )
                }
        }

        let message = CrazyEightsServerMessage.roomList(summaries)
        send(message: message, to: ws)
    }

    private func send(message: CrazyEightsServerMessage, to ws: WebSocket) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        ws.send(raw: data, opcode: .binary)
    }
}
