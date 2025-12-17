import SwiftUI

struct VolumesView: View {
    @EnvironmentObject private var dockerService: DockerService
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            Group {
                if dockerService.backend == .unavailable {
                    ContentUnavailableView(
                        "Backend unavailable",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text("Start Docker Desktop or Colima and try again.")
                    )
                } else if dockerService.volumes.isEmpty {
                    ContentUnavailableView(
                        "No volumes",
                        systemImage: "externaldrive",
                        description: Text("Press Refresh to fetch volumes.")
                    )
                } else {
                    List(dockerService.volumes) { volume in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(volume.name)
                                    .font(.headline)
                                Spacer()
                                Text(volume.driver)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(volume.mountpoint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Created: \(volume.createdAt)")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                Task { await dockerService.removeVolume(name: volume.name) }
                            }
                        }
                    }
#if os(iOS)
                    .listStyle(.insetGrouped)
#else
                    .listStyle(.inset)
#endif
                }
            }
            .navigationTitle("Docker Volumes")
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
        }
    }

    @MainActor
    private func refresh(initial: Bool = false) async {
        if initial { await dockerService.resolveBackend() }
        isRefreshing = true
        defer { isRefreshing = false }
        await dockerService.fetchVolumes()
    }
}

#if DEBUG
struct VolumesView_Previews: PreviewProvider {
    static var previews: some View {
        VolumesView()
            .environmentObject(DockerService())
    }
}
#endif
