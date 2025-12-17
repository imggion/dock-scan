import SwiftUI

struct NetworksView: View {
    @EnvironmentObject private var dockerService: DockerService
    @State private var selection: DockerNetwork.ID?
    @State private var isRefreshing = false

    var body: some View {
        NavigationSplitView {
            Group {
                if dockerService.backend == .unavailable {
                    ContentUnavailableView(
                        "Backend unavailable",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text("Start Docker Desktop or Colima and try again.")
                    )
                } else if dockerService.networks.isEmpty {
                    ContentUnavailableView(
                        "No networks",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Press Refresh to fetch networks.")
                    )
                } else {
                    List(dockerService.networks, selection: $selection) { network in
                        NavigationLink(value: network.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(network.name).font(.headline)
                                Text("\(network.driver) • \(network.scope.isEmpty ? "local" : network.scope)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                Task { await dockerService.removeNetwork(id: network.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Network")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .task {
                await refresh(initial: true)
            }
        } detail: {
            if let selection,
               let network = dockerService.networks.first(where: { $0.id == selection }) {
                NetworkDetailView(network: network)
            } else {
                ContentUnavailableView("Select a network", systemImage: "point.3.connected.trianglepath.dotted", description: nil)
            }
        }
    }

    @MainActor
    private func refresh(initial: Bool = false) async {
        if initial { await dockerService.resolveBackend() }
        isRefreshing = true
        defer { isRefreshing = false }
        await dockerService.fetchNetworks()
    }
}

struct NetworkDetailView: View {
    @EnvironmentObject private var dockerService: DockerService
    let network: DockerNetwork

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(network.name).font(.title2)
                    Text(network.driver).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            LabeledContent("Driver") { Text(network.driver) }
            LabeledContent("Scope") { Text(network.scope.isEmpty ? "local" : network.scope) }
            LabeledContent("ID") { Text(network.id).textSelection(.enabled).font(.caption) }

            Spacer()
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    Task { await dockerService.removeNetwork(id: network.id) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

#if DEBUG
struct NetworksView_Previews: PreviewProvider {
    static var previews: some View {
        NetworksView()
            .environmentObject(DockerService())
    }
}
#endif
