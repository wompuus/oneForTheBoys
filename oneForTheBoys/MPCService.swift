//
//  MPCService.swift
//  oneForTheBoys
//
//  Created by Wyatt Nail on 11/18/25.
//

import Foundation
import MultipeerConnectivity

// MARK: - Wire protocol between peers

enum WireEvent: Codable {
    case hello(peerId: UUID, name: String, deviceName: String)
    case start(config: GameConfig)
    case updateConfig(config: GameConfig)

    case intentPlay(card: UNOCard, chosenColor: UNOColor?, targetId: UUID?)
    case intentDraw(peerId: UUID)
    case callUno(peerId: UUID)
    case leave(peerId: UUID)
    case sync(state: GameState)
}

// MARK: - Discovered lobby model

/// Represents a single hosted game found over MultipeerConnectivity.
struct FoundLobby: Identifiable {
    let id = UUID()
    let hostName: String
    let lobbyId: String
    let playerCount: Int
    let peerID: MCPeerID
}

// MARK: - Service wrapper

final class MPCService: NSObject, ObservableObject {
    @Published var isHost = false
    @Published var connectedNames: [String] = []
    
    /// All nearby lobbies discovered by the browser.
    @Published var discoveredLobbies: [FoundLobby] = []
    
    private let serviceType = "uno-local"
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    var onPeerDisconnected: ((MCPeerID) -> Void)? // This is called when a peer disconnects
    private var hostDisplayName: String = UIDevice.current.name
    
    private lazy var session: MCSession = {
        let s = MCSession(peer: myPeerId,
                          securityIdentity: nil,
                          encryptionPreference: .required)
        s.delegate = self
        return s
    }()
    
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    /// Lobby ID for the game we are hosting (if host).
    private(set) var currentLobbyId: String?
    
    /// Event callback into the orchestrator.
    var onEvent: ((WireEvent) -> Void)?
    
    // Expose local MC peer display name to the orchestrator
    var localPeerDisplayName: String {
        myPeerId.displayName
    }
    
    // MARK: - Public API
    
    /// Start hosting a game session.
    /// Creates a random lobbyId and advertises with discoveryInfo so clients
    /// can see host name, lobby ID, and player count.
    func startHosting(displayName: String) {
        isHost = true
        discoveredLobbies = []

        // Remember the user-chosen name for advertising
        hostDisplayName = displayName

        let lobbyId = makeLobbyId()
        currentLobbyId = lobbyId

        restartAdvertiser(playerCount: 1)  // host alone initially

        // Host can also browse; not required but harmless.
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }
    
    /// Start browsing for lobbies as a client.
    func join() {
        isHost = false
        discoveredLobbies = []
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }
    
    /// Stop all networking activity and clear state.
    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        
        advertiser = nil
        browser = nil
        
        session.disconnect()
        connectedNames = []
        discoveredLobbies = []
        currentLobbyId = nil
        isHost = false
    }
    
    /// Broadcast a wire event to all connected peers.
    func broadcast(_ event: WireEvent) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(event)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Send error:", error)
        }
    }
    
    /// Connect to a specific lobby (host peer) found in the browser list.
    func connect(to lobby: FoundLobby) {
        browser?.invitePeer(lobby.peerID, to: session, withContext: nil, timeout: 10)
    }
    
    /// Host-only: update the advertised player count whenever lobby size changes.
    func updateHostedLobbyPlayerCount(_ count: Int) {
        guard isHost else { return }
        restartAdvertiser(playerCount: count)
    }
    
    // MARK: - Helpers
    
    /// Generate a short, human-readable lobby ID (e.g., "A7F2").
    private func makeLobbyId(length: Int = 4) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
    
    /// (Host) Restart advertiser with updated discovery info including playerCount.
    private func restartAdvertiser(playerCount: Int) {
        guard let lobbyId = currentLobbyId ?? makeLobbyId() as String? else { return }
        currentLobbyId = lobbyId

        advertiser?.stopAdvertisingPeer()

        let discoveryInfo: [String: String] = [
            "hostName": hostDisplayName,             // <- changed
            "lobbyId": lobbyId,
            "playerCount": String(max(playerCount, 1))
        ]

        let adv = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
    }
}

// MARK: - Multipeer delegates

extension MPCService: MCNearbyServiceAdvertiserDelegate,
                      MCNearbyServiceBrowserDelegate,
                      MCSessionDelegate {
    
    // Host side: accept all invitations into our MCSession.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    // Browser side: host discovered.
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String : String]?) {
        
        let hostName = info?["hostName"] ?? peerID.displayName
        let lobbyId = info?["lobbyId"] ?? "----"
        let playerCount = Int(info?["playerCount"] ?? "1") ?? 1
        
        let lobby = FoundLobby(
            hostName: hostName,
            lobbyId: lobbyId,
            playerCount: playerCount,
            peerID: peerID
        )
        
        DispatchQueue.main.async {
            // Avoid duplicates based on peer displayName + lobbyId.
            if !self.discoveredLobbies.contains(where: {
                $0.peerID.displayName == peerID.displayName && $0.lobbyId == lobbyId
            }) {
                self.discoveredLobbies.append(lobby)
            } else {
                // If we see it again with a new playerCount, update it.
                if let idx = self.discoveredLobbies.firstIndex(where: {
                    $0.peerID.displayName == peerID.displayName && $0.lobbyId == lobbyId
                }) {
                    self.discoveredLobbies[idx] = lobby
                }
            }
        }
    }
    
    // Browser side: host disappeared, remove from list.
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredLobbies.removeAll {
                $0.peerID.displayName == peerID.displayName
            }
        }
    }
    
    // Session state changes: update list of connected peers.
    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedNames = session.connectedPeers.map { $0.displayName }

            if state == .notConnected {
                // Tell whoever owns the game logic that this peer is gone now.
                self.onPeerDisconnected?(peerID)
            }
        }
    }
    
    // Data receive → decode event → bounce into orchestrator.
    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        guard let event = try? JSONDecoder().decode(WireEvent.self, from: data) else { return }
        DispatchQueue.main.async {
            self.onEvent?(event)
        }
    }
    
    // Unused MCSession bits (required by protocol).
    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) {}
    
    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {}
    
    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) {}
}
