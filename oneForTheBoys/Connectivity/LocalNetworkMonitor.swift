import Foundation
import Network
import SwiftUI

/// Lightweight monitor for Local Network authorization/state using an NWBrowser probe.
@MainActor
final class LocalNetworkMonitor: ObservableObject {
    enum Status: Equatable {
        case unknown
        case checking
        case authorized
        case denied
        case error(String)

        var description: String {
            switch self {
            case .unknown: return "Unknown"
            case .checking: return "Checking…"
            case .authorized: return "Authorized"
            case .denied: return "Denied"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    @Published private(set) var status: Status = .unknown
    private var browser: NWBrowser?

    init() {
        startProbe()
    }

    private func startProbe() {
        status = .checking
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_oftb-perm._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.status = .authorized
                case .failed(let error):
                    if case .posix(let code) = (error as? NWError), code == .EACCES {
                        self?.status = .denied
                    } else {
                        self?.status = .error(error.localizedDescription)
                    }
                    browser.cancel()
                default:
                    break
                }
            }
        }
        browser.start(queue: .main)
    }
}
