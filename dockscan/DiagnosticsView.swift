#if os(macOS)
import SwiftUI
import AppKit

struct DiagnosticsView: View {
    @EnvironmentObject private var dockerService: DockerService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostica socket").font(.headline)
                Spacer()
                Button("Rileva di nuovo") { Task { await dockerService.resolveBackend() } }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Backend") { Text(dockerService.backend.displayName) }
                    LabeledContent("Socket") { Text(dockerService.socketPath ?? "—").textSelection(.enabled) }
                    LabeledContent("Ping") { Text(dockerService.lastPing ?? "—").textSelection(.enabled) }
                }
            }

            GroupBox("Log") {
                ScrollView {
                    Text(dockerService.detectionLog.isEmpty ? "—" : dockerService.detectionLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 180)
            }

            HStack {
                Button("Scegli socket…") { pickSocket() }
                Button("Reset custom") { dockerService.setCustomSocketURL(nil) }
                Button("Ping") { Task { await dockerService.ping() } }
                Spacer()
            }

            Text("Il socket viene rilevato automaticamente (priorità: `DOCKER_HOST` → Colima → Docker). Se vuoi re-introdurre App Sandbox, dovrai gestire l’accesso file con “Scegli socket…”.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 560)
    }

    private func pickSocket() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Seleziona docker.sock"
        panel.message = "Seleziona il socket (es. ~/.colima/default/docker.sock)."
        panel.allowedFileTypes = ["sock"]
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK {
            dockerService.setCustomSocketURL(panel.url)
        }
    }
}

#if DEBUG
struct DiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        DiagnosticsView()
            .environmentObject(DockerService())
    }
}
#endif
#endif
