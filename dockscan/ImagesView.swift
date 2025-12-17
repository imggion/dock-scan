import SwiftUI

struct ImagesView: View {
    @EnvironmentObject private var dockerService: DockerService
    @State private var selection: DockerImage.ID?
    @State private var isRefreshing = false

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB]
        f.countStyle = .file
        return f
    }()

    var body: some View {
        NavigationSplitView {
            Group {
                if dockerService.backend == .unavailable {
                    ContentUnavailableView(
                        "Backend non disponibile",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text("Avvia Docker Desktop o Colima e riprova.")
                    )
                } else if dockerService.images.isEmpty {
                    ContentUnavailableView(
                        "Nessuna immagine",
                        systemImage: "shippingbox",
                        description: Text("Tocca Aggiorna per recuperare le immagini.")
                    )
                } else {
                    List(dockerService.images, selection: $selection) { image in
                        NavigationLink(value: image.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(image.tags.first ?? "Untagged")
                                    .font(.headline)
                                HStack(spacing: 10) {
                                    Text(byteFormatter.string(fromByteCount: image.sizeBytes))
                                    if let date = image.createdAt {
                                        Text(date.formatted(date: .abbreviated, time: .omitted))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            Button("Rimuovi", role: .destructive) {
                                Task { await dockerService.removeImage(id: image.id, force: false) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Immagini")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Label("Aggiorna", systemImage: "arrow.clockwise")
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
               let image = dockerService.images.first(where: { $0.id == selection }) {
                ImageDetailView(image: image, byteFormatter: byteFormatter)
            } else {
                ContentUnavailableView("Seleziona un'immagine", systemImage: "shippingbox", description: nil)
            }
        }
    }

    @MainActor
    private func refresh(initial: Bool = false) async {
        if initial { await dockerService.resolveBackend() }
        isRefreshing = true
        defer { isRefreshing = false }
        await dockerService.fetchImages()
    }
}

struct ImageDetailView: View {
    @EnvironmentObject private var dockerService: DockerService
    let image: DockerImage
    let byteFormatter: ByteCountFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.tags.first ?? "Untagged").font(.title2)
                    Text(image.tags.dropFirst().prefix(4).joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            LabeledContent("Dimensione") { Text(byteFormatter.string(fromByteCount: image.sizeBytes)) }
            if let date = image.createdAt {
                LabeledContent("Creato") { Text(date.formatted(date: .complete, time: .omitted)) }
            }
            LabeledContent("ID") { Text(image.id).textSelection(.enabled).font(.caption) }

            Spacer()
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    Task { await dockerService.removeImage(id: image.id, force: false) }
                } label: {
                    Label("Rimuovi", systemImage: "trash")
                }
            }
        }
    }
}

#if DEBUG
struct ImagesView_Previews: PreviewProvider {
    static var previews: some View {
        ImagesView()
            .environmentObject(DockerService())
    }
}
#endif
