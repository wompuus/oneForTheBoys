import Foundation
import MultipeerConnectivity
import UIKit
actor ConnectivityManager: GameTransport {
    struct FoundLobby: Identifiable {
        let id = UUID()
        let hostName: String
        let lobbyId: String
        let playerCount: Int
        let peerID: MCPeerID
    }
    private let maxPayloadBytes = 1_000_000
    private let serviceType = "oftb-p2p"
    private let peerID: MCPeerID
    let session: MCSession
    private let delegateProxy: DelegateProxy
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var lastMessageType: String?
    private var lastMessageBytes: Int?

    private(set) var isHost = false
    private(set) var discoveredLobbies: [FoundLobby] = []
    private(set) var currentLobbyId: String?
    private var hostDisplayName: String
    private var activeGameId: GameID?

    private var primaryHandlers: [(NetworkMessage, MCPeerID) -> Void] = []
    private var additionalHandlers: [(NetworkMessage, MCPeerID) -> Void] = []
    private var primaryPeerDisconnected: ((MCPeerID) -> Void)?
    private var primaryPeerConnected: ((MCPeerID) -> Void)?
    private var additionalPeerDisconnected: [(MCPeerID) -> Void] = []
    private var additionalPeerConnected: [(MCPeerID) -> Void] = []

    init(displayName: String, defaultGameId: GameID = .crazyEights) {
        hostDisplayName = displayName
        peerID = MCPeerID(displayName: displayName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        delegateProxy = DelegateProxy()
        activeGameId = defaultGameId
        session.delegate = delegateProxy
        delegateProxy.attach(self)
    }

    func setActiveGame(_ gameId: GameID?) {
        activeGameId = gameId
    }

    func setOnMessageHandler(_ handler: @escaping (NetworkMessage, MCPeerID) -> Void) {
        primaryHandlers = [handler]
    }

    func addOnMessageHandler(_ handler: @escaping (NetworkMessage, MCPeerID) -> Void) {
        additionalHandlers.append(handler)
    }

    func setOnPeerDisconnectedHandler(_ handler: @escaping (MCPeerID) -> Void) {
        primaryPeerDisconnected = handler
    }

    func setOnPeerConnectedHandler(_ handler: @escaping (MCPeerID) -> Void) {
        primaryPeerConnected = handler
    }

    func addOnPeerDisconnectedHandler(_ handler: @escaping (MCPeerID) -> Void) {
        additionalPeerDisconnected.append(handler)
    }

    func addOnPeerConnectedHandler(_ handler: @escaping (MCPeerID) -> Void) {
        additionalPeerConnected.append(handler)
    }

    func startHosting(lobbyId: String? = nil, playerCount: Int = 1, hostName: String? = nil) {
        isHost = true
        if let hostName { hostDisplayName = hostName }
        discoveredLobbies = []
        currentLobbyId = lobbyId ?? makeLobbyId()
        restartAdvertiser(playerCount: playerCount)
        startBrowsing()
    }

    func startBrowsing() {
        browser?.stopBrowsingForPeers()
        let newBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser = newBrowser
        newBrowser.delegate = delegateProxy
        newBrowser.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session.disconnect()
        discoveredLobbies = []
        currentLobbyId = nil
        isHost = false
    }

    func connect(to lobby: FoundLobby) {
        browser?.invitePeer(lobby.peerID, to: session, withContext: nil, timeout: 10)
    }

    func updateHostedLobbyPlayerCount(_ count: Int) {
        guard isHost else { return }
        restartAdvertiser(playerCount: count)
    }

    private func restartAdvertiser(playerCount: Int) {
        let lobbyId = currentLobbyId ?? makeLobbyId()
        currentLobbyId = lobbyId
        advertiser?.stopAdvertisingPeer()

        let discoveryInfo: [String: String] = [
            "hostName": hostDisplayName,
            "lobbyId": lobbyId,
            "playerCount": String(max(playerCount, 1))
        ]

        let adv = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        advertiser = adv
        adv.delegate = delegateProxy
        adv.startAdvertisingPeer()
    }

    func sendNetworkMessage(_ message: NetworkMessage) async {
        guard let data = try? JSONEncoder().encode(message) else { return }
        guard data.count <= maxPayloadBytes else { return }
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        print("[Connectivity] Sending \(message.kindDescription) to \(peers.count) peers")
        lastMessageType = "out:\(message.kindDescription)"
        lastMessageBytes = data.count
        do {
            try session.send(data, toPeers: peers, with: .reliable)
        } catch {
            print("Send error:", error)
        }
    }

    func send<A: Codable>(_ action: A) async {
        guard let gameId = activeGameId else { return }
        guard let payload = try? JSONEncoder().encode(action) else { return }
        await sendNetworkMessage(.gameAction(gameId: gameId, payload: payload))
    }

    func broadcast<S: Codable>(_ state: S) async {
        guard let gameId = activeGameId else { return }
        guard let payload = try? JSONEncoder().encode(state) else { return }
        await sendNetworkMessage(.gameState(gameId: gameId, payload: payload))
    }

    func handleFoundPeer(_ peerID: MCPeerID, info: [String: String]?) {
        let hostName = info?["hostName"] ?? peerID.displayName
        let lobbyId = info?["lobbyId"] ?? "----"
        let playerCount = Int(info?["playerCount"] ?? "1") ?? 1
        let lobby = FoundLobby(hostName: hostName, lobbyId: lobbyId, playerCount: playerCount, peerID: peerID)

        if let idx = discoveredLobbies.firstIndex(where: { $0.peerID.displayName == peerID.displayName && $0.lobbyId == lobbyId }) {
            discoveredLobbies[idx] = lobby
        } else {
            discoveredLobbies.append(lobby)
        }
    }

    func handleLostPeer(_ peerID: MCPeerID) {
        discoveredLobbies.removeAll { $0.peerID.displayName == peerID.displayName }
    }

    func handleStateChange(_ state: MCSessionState, session: MCSession, peerID: MCPeerID) {
        switch state {
        case .connected:
            let handlers = [primaryPeerConnected].compactMap { $0 } + additionalPeerConnected
            Task { @MainActor in handlers.forEach { $0(peerID) } }
        case .notConnected:
            let handlers = [primaryPeerDisconnected].compactMap { $0 } + additionalPeerDisconnected
            Task { @MainActor in handlers.forEach { $0(peerID) } }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    func handleReceivedData(_ data: Data, from peerID: MCPeerID) {
        guard data.count <= maxPayloadBytes else { return }
        guard let message = try? JSONDecoder().decode(NetworkMessage.self, from: data) else { return }
        lastMessageType = "in:\(message.kindDescription)"
        lastMessageBytes = data.count
        print("[Connectivity] Received \(message.kindDescription) from \(peerID.displayName)")
        let handlers = primaryHandlers + additionalHandlers
        Task { @MainActor in
            for h in handlers { h(message, peerID) }
        }
    }

    private func makeLobbyId(length: Int = 4) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    func diagnosticsSnapshot() -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            peerCount: session.connectedPeers.count,
            lastMessageType: lastMessageType,
            lastMessageBytes: lastMessageBytes
        )
    }
}
private final class DelegateProxy: NSObject, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    weak var owner: ConnectivityManager?

    func attach(_ owner: ConnectivityManager) {
        self.owner = owner
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard let owner else {
            invitationHandler(false, nil)
            return
        }
        Task {
            let session = await owner.session
            invitationHandler(true, session)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard let owner else { return }
        Task { await owner.handleFoundPeer(peerID, info: info) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        guard let owner else { return }
        Task { await owner.handleLostPeer(peerID) }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Browser failed: \(error.localizedDescription)")
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard let owner else { return }
        Task { await owner.handleStateChange(state, session: session, peerID: peerID) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let owner else { return }
        Task { await owner.handleReceivedData(data, from: peerID) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
