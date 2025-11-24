//
//  Untitled.swift
//  oneForTheBoys
//
//  Created by Wyatt Nail on 11/18/25.
//

import SwiftUI
import MultipeerConnectivity

// Simple Multipeer wrapper just to prove host/join works.
final class MPCDemoService: NSObject, ObservableObject {
    @Published var isHosting = false
    @Published var isBrowsing = false
    @Published var connectedPeers: [String] = []
    @Published var log: [String] = []

    private let serviceType = "uno-demo"
    private var myPeerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    init(displayName: String) {
        super.init()
        myPeerID = MCPeerID(displayName: displayName)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        append("Created peer: \(displayName)")
    }

    func startHosting() {
        append("Start hosting")
        isHosting = true
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func startBrowsing() {
        append("Start browsing")
        isBrowsing = true
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stopAll() {
        append("Stop all")
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session.disconnect()
        connectedPeers = []
        isHosting = false
        isBrowsing = false
    }

    private func append(_ msg: String) {
        print("[MPCDemo]", msg)
        DispatchQueue.main.async {
            self.log.append(msg)
        }
    }
}

// MARK: - Multipeer delegates

extension MPCDemoService: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    // Advertiser
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        append("Invited by \(peerID.displayName) -> accepting")
        invitationHandler(true, session)
    }

    // Browser
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String : String]?) {
        append("Found peer: \(peerID.displayName), sending invite")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        append("Lost peer: \(peerID.displayName)")
    }

    // Session
    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        append("Peer \(peerID.displayName) state: \(state.rawValue)")
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers.map { $0.displayName }
        }
    }

    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {}

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

// MARK: - Test UI

struct ConnectivityRootView: View {
    @State private var name: String = UIDevice.current.name
    @State private var service: MPCDemoService?

    var body: some View {
        VStack(spacing: 16) {
            Text("UNO Connectivity Test")
                .font(.title2).bold()

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if let svc = service {
                Text("Peer ID: \(svc.connectedPeers.isEmpty ? "No peers" : "Connected")")
                HStack {
                    Button("Host") {
                        svc.startHosting()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Join") {
                        svc.startBrowsing()
                    }
                    .buttonStyle(.bordered)

                    Button("Stop") {
                        svc.stopAll()
                    }
                    .buttonStyle(.bordered)
                }

                List {
                    Section("Connected Peers") {
                        if svc.connectedPeers.isEmpty {
                            Text("None")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(svc.connectedPeers, id: \.self) { p in
                                Text(p)
                            }
                        }
                    }
                    Section("Log") {
                        ForEach(svc.log.indices, id: \.self) { i in
                            Text(svc.log[i])
                                .font(.caption)
                        }
                    }
                }
            } else {
                Button("Initialize Session") {
                    service = MPCDemoService(displayName: name)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
