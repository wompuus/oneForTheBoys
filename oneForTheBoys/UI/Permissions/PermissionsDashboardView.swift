import SwiftUI
import Combine

struct PermissionsDashboardView: View {
    let connectivity: ConnectivityManager
    @StateObject private var networkMonitor = LocalNetworkMonitor()
    @State private var diagnostics = DiagnosticsSnapshot(peerCount: 0, lastMessageType: nil, lastMessageBytes: nil)

    var body: some View {
        List {
            Section("Permissions") {
                HStack {
                    Label("Local Network", systemImage: "network")
                    Spacer()
                    Text(networkMonitor.status.description)
                        .foregroundStyle(color(for: networkMonitor.status))
                }
                Text("If denied, go to Settings > Privacy & Security > Local Network to enable peer discovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                HStack {
                    Label("Connected peers", systemImage: "person.3")
                    Spacer()
                    Text("\(diagnostics.peerCount)")
                        .foregroundStyle(.primary)
                }
                HStack {
                    Label("Last message", systemImage: "arrow.left.arrow.right")
                    Spacer()
                    Text(diagnostics.lastMessageType ?? "—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("Last size", systemImage: "doc")
                    Spacer()
                    if let bytes = diagnostics.lastMessageBytes {
                        Text("\(bytes) bytes")
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Permissions & Diagnostics")
        .task {
            await refreshDiagnostics()
        }
        .task {
            for await _ in Timer.publish(every: 1.5, on: .main, in: .common).autoconnect().values {
                await refreshDiagnostics()
            }
        }
    }

    private func refreshDiagnostics() async {
        diagnostics = await connectivity.diagnosticsSnapshot()
    }

    private func color(for status: LocalNetworkMonitor.Status) -> Color {
        switch status {
        case .authorized: return .green
        case .denied, .error: return .red
        case .checking: return .orange
        case .unknown: return .secondary
        }
    }
}
