import SwiftUI

struct DockscanHomeView: View {
    @EnvironmentObject private var dockerService: DockerService
    @State private var section: NavSection = .containers
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var selectedContainerID: DockerContainer.ID?
    @State private var selectedStackID: DockerStackGroup.ID?
    @State private var selectedImageID: DockerImage.ID?
    @State private var selectedVolumeID: DockerVolume.ID?
    @State private var selectedNetworkID: DockerNetwork.ID?

    @State private var showingPruneVolumesConfirm = false
    @State private var logsSheetContainer: LogsSheetItem?

    private struct LogsSheetItem: Identifiable {
        let id: DockerContainer.ID
    }

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB]
        f.countStyle = .file
        return f
    }()

    enum NavSection: String, CaseIterable, Identifiable, Hashable {
        case containers
        case stacks
        case images
        case volumes
        case networks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .containers: return "Containers"
            case .stacks: return "Stacks"
            case .images: return "Images"
            case .volumes: return "Volumes"
            case .networks: return "Networks"
            }
        }

        var systemImage: String {
            switch self {
            case .containers: return "shippingbox"
            case .stacks: return "square.stack.3d.up.fill"
            case .images: return "server.rack"
            case .volumes: return "internaldrive"
            case .networks: return "network"
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(selection: $section) {
                    SwiftUI.Section {
                        ForEach(NavSection.allCases) { item in
                            Label(item.title, systemImage: item.systemImage)
                                .tag(item)
                        }
                    } header: {
                        Text("Dockscan")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .padding(.top, 6)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: dockerService.backend == .unavailable ? "externaldrive.badge.xmark" : "externaldrive.connected.to.line.below")
                        .foregroundStyle(.secondary)
                    Text(dockerService.backend.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } content: {
            contentColumn
                .navigationTitle(section.title)
                .toolbar { contentToolbar }
                .task(id: section) {
                    await refresh(initial: false)
                }
                .navigationSplitViewColumnWidth(min: 520, ideal: 920, max: .infinity)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(
                    min: section == .stacks ? 460 : 360,
                    ideal: section == .stacks ? 820 : 520,
                    max: section == .stacks ? .infinity : 900
                )
        }
        .environment(
            \.dockscanNavigate,
            DockscanNavigateAction(
                showImage: { imageRef in
                    Task { @MainActor in
                        section = .images
                        columnVisibility = .all
                        await dockerService.fetchImages()
                        selectedImageID = dockerService.images.first(where: { $0.tags.contains(imageRef) })?.id
                    }
                },
                showNetwork: { networkName in
                    Task { @MainActor in
                        section = .networks
                        columnVisibility = .all
                        await dockerService.fetchNetworks()
                        selectedNetworkID = dockerService.networks.first(where: { $0.name == networkName })?.id
                    }
                },
                showVolume: { volumeName in
                    Task { @MainActor in
                        section = .volumes
                        columnVisibility = .all
                        await dockerService.fetchVolumes()
                        selectedVolumeID = dockerService.volumes.first(where: { $0.name == volumeName })?.id
                    }
                }
            )
        )
        .sheet(item: $logsSheetContainer) { item in
            ContainerLogsSheet(containerID: item.id)
                .environmentObject(dockerService)
        }
        .alert("Eseguire Prune Volumi?", isPresented: $showingPruneVolumesConfirm) {
            Button("Annulla", role: .cancel) {}
            Button("Prune", role: .destructive) {
                Task { await dockerService.pruneVolumes() }
            }
        } message: {
            Text("Rimuove tutti i volumi non utilizzati.")
        }
        .task {
            await refresh(initial: true)
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch section {
        case .containers:
            containersTable
        case .stacks:
            stacksTable
        case .images:
            imagesTable
        case .volumes:
            volumesTable
        case .networks:
            networksTable
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch section {
        case .containers:
            if let selectedContainerID,
               let container = dockerService.containers.first(where: { $0.id == selectedContainerID }) {
                ContainerDetailView(container: container)
            } else {
                NoSelectionView(title: "Nessun container selezionato", systemImage: "shippingbox")
            }
        case .stacks:
            let groups = dockerService.containers.groupedByStack()
            if let selectedStackID,
               let group = groups.first(where: { $0.id == selectedStackID }) {
                StackDetailView(group: group) { containerID in
                    Task { @MainActor in
                        section = .containers
                        columnVisibility = .all
                        await dockerService.fetchContainers()
                        selectedContainerID = containerID
                    }
                }
            } else {
                NoSelectionView(title: "Nessuno stack selezionato", systemImage: "square.stack.3d.up.fill")
            }
        case .images:
            if let selectedImageID,
               let image = dockerService.images.first(where: { $0.id == selectedImageID }) {
                ImageDetailView(image: image, byteFormatter: byteFormatter)
            } else {
                NoSelectionView(title: "Nessuna immagine selezionata", systemImage: "server.rack")
            }
        case .volumes:
            if let selectedVolumeID,
               let volume = dockerService.volumes.first(where: { $0.id == selectedVolumeID }) {
                VolumeDetailView(volume: volume)
            } else {
                NoSelectionView(title: "Nessun volume selezionato", systemImage: "internaldrive")
            }
        case .networks:
            if let selectedNetworkID,
               let network = dockerService.networks.first(where: { $0.id == selectedNetworkID }) {
                NetworkDetailView(network: network)
            } else {
                NoSelectionView(title: "Nessun network selezionato", systemImage: "network")
            }
        }
    }

    @ToolbarContentBuilder
    private var contentToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await refresh(initial: false) }
            } label: {
                Label("Aggiorna", systemImage: "arrow.clockwise")
            }

            if section == .volumes {
                Button(role: .destructive) {
                    showingPruneVolumesConfirm = true
                } label: {
                    Label("Prune", systemImage: "trash.slash")
                }
            }
        }
    }

    private var containersTable: some View {
        Group {
            if dockerService.backend == .unavailable {
                ContentUnavailableView(
                    "Backend non disponibile",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("Avvia Docker Desktop o Colima e riprova.")
                )
            } else if dockerService.containers.isEmpty {
                ContentUnavailableView(
                    "Nessun container",
                    systemImage: "shippingbox",
                    description: Text("Tocca Aggiorna per recuperare i container.")
                )
            } else {
                Table(dockerService.containers, selection: $selectedContainerID) {
                    TableColumn("Name") { container in
                        HStack(spacing: 8) {
                            Image(systemName: container.isRunning ? "play.circle.fill" : "stop.circle")
                                .foregroundStyle(container.isRunning ? .green : .secondary)
                            Text(container.name)
                                .font(.body.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu { containerContextMenu(container) }
                    }
                    .width(min: 260, ideal: 360, max: 520)
                    TableColumn("ID") { container in
                        Text(shortID(container.id))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { containerContextMenu(container) }
                    }
                    .width(min: 140, ideal: 160, max: 200)
                    TableColumn("Status") { container in
                        StatusBadge(
                            title: container.isRunning ? "Running" : "Stopped",
                            color: container.isRunning ? .green : .orange
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu { containerContextMenu(container) }
                    }
                    .width(min: 110, ideal: 130, max: 160)
                    TableColumn("Created") { container in
                        Text(formatCreated(container.createdAt))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { containerContextMenu(container) }
                    }
                    .width(min: 160, ideal: 200, max: 260)
                    TableColumn("") { container in
                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    if container.isRunning {
                                        await dockerService.stopContainer(id: container.id)
                                    } else {
                                        await dockerService.startContainer(id: container.id)
                                    }
                                }
                            } label: {
                                Image(systemName: container.isRunning ? "stop.fill" : "play.fill")
                            }

                            Button {
                                logsSheetContainer = LogsSheetItem(id: container.id)
                            } label: {
                                Image(systemName: "doc.text.magnifyingglass")
                            }
                            .disabled(!container.isRunning)

                            Button(role: .destructive) {
                                Task { await dockerService.removeContainer(id: container.id, force: true) }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                        .contextMenu { containerContextMenu(container) }
                    }
                    .width(min: 140, ideal: 160, max: 220)
                }
            }
        }
        .padding()
    }

    private var stacksTable: some View {
        let groups = dockerService.containers.groupedByStack()

        return Group {
            if dockerService.backend == .unavailable {
                ContentUnavailableView(
                    "Backend non disponibile",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("Avvia Docker Desktop o Colima e riprova.")
                )
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "Nessuno stack",
                    systemImage: "square.stack.3d.up.fill",
                    description: Text("Nessuno stack Compose/Swarm trovato nei container correnti.")
                )
            } else {
                Table(groups, selection: $selectedStackID) {
                    TableColumn("Name") { group in
                        HStack(spacing: 8) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(.secondary)
                            Text(group.name)
                                .font(.body.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .width(min: 260, ideal: 360, max: 520)

                    TableColumn("Kind") { group in
                        Text(group.kindLabel ?? "—")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .width(min: 110, ideal: 130, max: 160)

                    TableColumn("Containers") { group in
                        Text("\(group.containers.count)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .width(min: 110, ideal: 130, max: 160)

                    TableColumn("Running") { group in
                        StatusBadge(title: "\(group.runningCount)", color: group.runningCount > 0 ? .green : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .width(min: 110, ideal: 130, max: 160)

                    TableColumn("Errors") { group in
                        StatusBadge(title: "\(group.errorCount)", color: group.errorCount > 0 ? .red : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .width(min: 110, ideal: 130, max: 160)
                }
            }
        }
        .padding()
    }

    private var imagesTable: some View {
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
                    systemImage: "server.rack",
                    description: Text("Tocca Aggiorna per recuperare le immagini.")
                )
            } else {
                Table(dockerService.images, selection: $selectedImageID) {
                    TableColumn("Name") { image in
                        Text(image.tags.first ?? "Untagged")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { imageContextMenu(image) }
                    }
                    .width(min: 260, ideal: 360, max: 520)
                    TableColumn("ID") { image in
                        Text(shortID(image.id))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { imageContextMenu(image) }
                    }
                    .width(min: 140, ideal: 160, max: 200)
                    TableColumn("Size") { image in
                        Text(byteFormatter.string(fromByteCount: image.sizeBytes))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { imageContextMenu(image) }
                    }
                    .width(min: 110, ideal: 130, max: 180)
                    TableColumn("Status") { image in
                        StatusBadge(
                            title: image.tags.isEmpty ? "Untagged" : "Tagged",
                            color: image.tags.isEmpty ? .secondary : .blue
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu { imageContextMenu(image) }
                    }
                    .width(min: 110, ideal: 130, max: 160)
                    TableColumn("Created") { image in
                        Text(formatCreated(image.createdAt))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { imageContextMenu(image) }
                    }
                    .width(min: 160, ideal: 200, max: 260)
                    TableColumn("") { image in
                        HStack(spacing: 10) {
                            Button {
                                selectedImageID = image.id
                                columnVisibility = .all
                            } label: {
                                Image(systemName: "info.circle")
                            }

                            Button(role: .destructive) {
                                Task { await dockerService.removeImage(id: image.id, force: false) }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                        .contextMenu { imageContextMenu(image) }
                    }
                    .width(min: 110, ideal: 130, max: 200)
                }
            }
        }
        .padding()
    }

    private var volumesTable: some View {
        Group {
            if dockerService.backend == .unavailable {
                ContentUnavailableView(
                    "Backend non disponibile",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("Avvia Docker Desktop o Colima e riprova.")
                )
            } else if dockerService.volumes.isEmpty {
                ContentUnavailableView(
                    "Nessun volume",
                    systemImage: "internaldrive",
                    description: Text("Tocca Aggiorna per recuperare i volumi.")
                )
            } else {
                Table(dockerService.volumes, selection: $selectedVolumeID) {
                    TableColumn("Name") { volume in
                        Text(volume.name)
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { volumeContextMenu(volume) }
                    }
                    .width(min: 260, ideal: 360, max: 520)
                    TableColumn("ID") { volume in
                        Text(shortID(volume.id))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { volumeContextMenu(volume) }
                    }
                    .width(min: 140, ideal: 160, max: 200)
                    TableColumn("Status") { volume in
                        StatusBadge(title: volume.driver, color: .purple)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { volumeContextMenu(volume) }
                    }
                    .width(min: 110, ideal: 130, max: 160)
                    TableColumn("Created") { volume in
                        Text(volume.createdAt.isEmpty ? "—" : volume.createdAt)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { volumeContextMenu(volume) }
                    }
                    .width(min: 160, ideal: 240, max: 420)
                    TableColumn("") { volume in
                        HStack(spacing: 10) {
                            Button {
                                selectedVolumeID = volume.id
                                columnVisibility = .all
                            } label: {
                                Image(systemName: "info.circle")
                            }

                            Button(role: .destructive) {
                                Task { await dockerService.removeVolume(name: volume.name) }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                        .contextMenu { volumeContextMenu(volume) }
                    }
                    .width(min: 110, ideal: 130, max: 200)
                }
            }
        }
        .padding()
    }

    private var networksTable: some View {
        Group {
            if dockerService.backend == .unavailable {
                ContentUnavailableView(
                    "Backend non disponibile",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("Avvia Docker Desktop o Colima e riprova.")
                )
            } else if dockerService.networks.isEmpty {
                ContentUnavailableView(
                    "Nessun network",
                    systemImage: "network",
                    description: Text("Tocca Aggiorna per recuperare i network.")
                )
            } else {
                Table(dockerService.networks, selection: $selectedNetworkID) {
                    TableColumn("Name") { network in
                        Text(network.name)
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { networkContextMenu(network) }
                    }
                    .width(min: 260, ideal: 360, max: 520)
                    TableColumn("ID") { network in
                        Text(shortID(network.id))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { networkContextMenu(network) }
                    }
                    .width(min: 140, ideal: 160, max: 200)
                    TableColumn("Status") { network in
                        StatusBadge(title: network.scope.isEmpty ? "local" : network.scope, color: .teal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { networkContextMenu(network) }
                    }
                    .width(min: 110, ideal: 130, max: 160)
                    TableColumn("Created") { network in
                        Text(formatCreated(network.createdAt))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { networkContextMenu(network) }
                    }
                    .width(min: 160, ideal: 200, max: 260)
                    TableColumn("") { network in
                        HStack(spacing: 10) {
                            Button {
                                selectedNetworkID = network.id
                                columnVisibility = .all
                            } label: {
                                Image(systemName: "info.circle")
                            }

                            Button(role: .destructive) {
                                Task { await dockerService.removeNetwork(id: network.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                        .contextMenu { networkContextMenu(network) }
                    }
                    .width(min: 110, ideal: 130, max: 200)
                }
            }
        }
        .padding()
    }

    @MainActor
    private func refresh(initial: Bool) async {
        if initial { await dockerService.resolveBackend() }
        guard dockerService.backend != .unavailable else { return }

        switch section {
        case .containers:
            await dockerService.fetchContainers()
        case .stacks:
            await dockerService.fetchContainers()
        case .images:
            await dockerService.fetchImages()
        case .volumes:
            await dockerService.fetchVolumes()
        case .networks:
            await dockerService.fetchNetworks()
        }
    }

    @ViewBuilder
    private func containerContextMenu(_ container: DockerContainer) -> some View {
        if container.isRunning {
            Button("Stop") { Task { await dockerService.stopContainer(id: container.id) } }
            Button("Restart") { Task { await dockerService.restartContainer(id: container.id) } }
        } else {
            Button("Start") { Task { await dockerService.startContainer(id: container.id) } }
        }
        Divider()
        Button("Logs") { logsSheetContainer = LogsSheetItem(id: container.id) }
            .disabled(!container.isRunning)
        Divider()
        Button("Rimuovi", role: .destructive) {
            Task { await dockerService.removeContainer(id: container.id, force: true) }
        }
    }

    @ViewBuilder
    private func imageContextMenu(_ image: DockerImage) -> some View {
        Button("Dettagli") {
            selectedImageID = image.id
            columnVisibility = .all
        }
        Divider()
        Button("Rimuovi", role: .destructive) {
            Task { await dockerService.removeImage(id: image.id, force: false) }
        }
    }

    @ViewBuilder
    private func volumeContextMenu(_ volume: DockerVolume) -> some View {
        Button("Dettagli") {
            selectedVolumeID = volume.id
            columnVisibility = .all
        }
        Divider()
        Button("Rimuovi", role: .destructive) {
            Task { await dockerService.removeVolume(name: volume.name) }
        }
    }

    @ViewBuilder
    private func networkContextMenu(_ network: DockerNetwork) -> some View {
        Button("Dettagli") {
            selectedNetworkID = network.id
            columnVisibility = .all
        }
        Divider()
        Button("Rimuovi", role: .destructive) {
            Task { await dockerService.removeNetwork(id: network.id) }
        }
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(12))
    }

    private func formatCreated(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

#if os(macOS)
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }
#endif
}

private struct StackDetailView: View {
    @EnvironmentObject private var dockerService: DockerService
    let group: DockerStackGroup
    let onSelectContainer: (DockerContainer.ID) -> Void

    @State private var selectedTab: Tab = .info

    private enum Tab: Hashable {
        case info
        case logs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch selectedTab {
                case .info:
                    infoTab
                case .logs:
                    logsTab
                }
            }
        }
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Sezione", selection: $selectedTab) {
                    Text("Info").tag(Tab.info)
                    Text("Logs").tag(Tab.logs)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
            }
        }
    }

    private var infoTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.title2)
                    Text(group.kindLabel ?? "Compose/Swarm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.containers) { container in
                    Button {
                        onSelectContainer(container.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: container.isRunning ? "play.circle.fill" : "stop.circle")
                                .foregroundStyle(container.isRunning ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(container.stackServiceName ?? container.name)
                                    .font(.headline)
                                Text(container.image)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !container.portSummary.isEmpty {
                                Text(container.portSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Menu("Azioni") {
                            if container.isRunning {
                                Button("Stop") { Task { await dockerService.stopContainer(id: container.id) } }
                                Button("Restart") { Task { await dockerService.restartContainer(id: container.id) } }
                            } else {
                                Button("Start") { Task { await dockerService.startContainer(id: container.id) } }
                            }
                        }
                        Divider()
                        Button("Apri Dettagli") { onSelectContainer(container.id) }
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    private var logsTab: some View {
        StackLogsView(
            stackName: group.name,
            containers: group.containers
        )
        .environmentObject(dockerService)
    }
}

private struct StatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule(style: .continuous))
            .foregroundStyle(color)
    }
}

private struct NoSelectionView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ContainerLogsSheet: View {
    @EnvironmentObject private var dockerService: DockerService
    let containerID: DockerContainer.ID

    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    private let tail: Int = 500
    @State private var flushTask: Task<Void, Never>?
    @State private var error: String?
    @State private var partialLine: String = ""
    @State private var pendingLines: [String] = []

    @StateObject private var buffer = TerminalLogBuffer(maxChars: 250_000)
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Logs", systemImage: "doc.text.magnifyingglass")
                    .font(.title3.weight(.semibold))
                Spacer()
                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button("Pulisci") { clear() }
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            TerminalLogTextView(buffer: buffer, autoScroll: $autoScroll)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        }
        .padding()
        .frame(minWidth: 760, minHeight: 520)
        .task(id: containerID) { startStreaming() }
        .onDisappear { stopStreaming() }
    }

    @MainActor
    private func clear() {
        buffer.clear()
        pendingLines = []
        partialLine = ""
    }

    @MainActor
    private func startStreaming() {
        stopStreaming()
        error = nil
        clear()
        isStreaming = true

        streamTask = Task {
            var isFirstConnection = true

            while !Task.isCancelled {
                do {
                    let tailForAttempt = isFirstConnection ? tail : 0
                    isFirstConnection = false

                    var didReceive = false
                    for try await chunk in dockerService.streamContainerLogs(id: containerID, tail: tailForAttempt) {
                        await MainActor.run {
                            if !didReceive {
                                didReceive = true
                                isStreaming = false
                            }
                            append(chunk)
                        }
                    }

                    await MainActor.run {
                        if buffer.isEmpty {
                            isStreaming = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.error = (error as NSError).localizedDescription
                        self.isStreaming = false
                    }
                }

                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run { isStreaming = true }
            }
        }
    }

    @MainActor
    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        flushTask?.cancel()
        flushTask = nil
        isStreaming = false
    }

    @MainActor
    private func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        let combined = partialLine + chunk
        let endsWithNewline = combined.hasSuffix("\n")
        let parts = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var completeLines = parts
        if !endsWithNewline, let last = completeLines.popLast() {
            partialLine = last
        } else {
            partialLine = ""
        }

        pendingLines.append(contentsOf: completeLines)
        scheduleFlush()
    }

    @MainActor
    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                flushTask = nil
                if !pendingLines.isEmpty {
                    let batch = pendingLines
                    pendingLines = []
                    for line in batch {
                        buffer.append(service: "", line: line, showPrefix: false)
                    }
                }
            }
        }
    }
}

private struct StackLogsView: View {
    @EnvironmentObject private var dockerService: DockerService

    let stackName: String
    let containers: [DockerContainer]

    @State private var isStreaming = false
    @State private var error: String?

    @State private var streamTasks: [DockerContainer.ID: Task<Void, Never>] = [:]
    @State private var flushTask: Task<Void, Never>?
    @State private var partialLines: [DockerContainer.ID: String] = [:]
    @State private var pendingLines: [(service: String, line: String)] = []

    @StateObject private var buffer = TerminalLogBuffer(maxChars: 250_000)
    @State private var autoScroll = true

    private let tail: Int = 250

    private var runningContainers: [DockerContainer] {
        containers.filter(\.isRunning)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Logs Stack", systemImage: "text.alignleft")
                    .font(.title3.weight(.semibold))
                Spacer()
                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button("Pulisci") { clear() }
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if runningContainers.isEmpty {
                ContentUnavailableView(
                    "Stack non in esecuzione",
                    systemImage: "square.stack.3d.up.fill",
                    description: Text("Avvia almeno un container dello stack per vedere i log.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TerminalLogTextView(buffer: buffer, autoScroll: $autoScroll)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
            }
        }
        .padding()
        .task(id: runningContainers.map(\.id).joined(separator: ",")) {
            if runningContainers.isEmpty {
                await MainActor.run { stopStreaming() }
            } else {
                await MainActor.run { startStreaming() }
            }
        }
        .onDisappear {
            stopStreaming()
        }
    }

    @MainActor
    private func clear() {
        buffer.clear()
        pendingLines = []
        partialLines = [:]
    }

    @MainActor
    private func startStreaming() {
        stopStreaming()
        clear()
        error = nil
        isStreaming = true

        flushTask = Task {
            while !Task.isCancelled {
                if !pendingLines.isEmpty {
                    let batch = pendingLines
                    pendingLines = []
                    for entry in batch {
                        buffer.append(service: entry.service, line: entry.line)
                    }
                }
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }

        for container in runningContainers {
            let containerID = container.id
            let prefix = container.stackServiceName ?? container.name

            streamTasks[containerID] = Task {
                var isFirstConnection = true

                while !Task.isCancelled {
                    do {
                        let tailForAttempt = isFirstConnection ? tail : 0
                        isFirstConnection = false

                        for try await chunk in dockerService.streamContainerLogs(id: containerID, tail: tailForAttempt, timestamps: false) {
                            await MainActor.run {
                                isStreaming = false
                                append(chunk: chunk, prefix: prefix, containerID: containerID)
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.error = (error as NSError).localizedDescription
                            self.isStreaming = false
                        }
                    }

                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await MainActor.run { isStreaming = true }
                }
            }
        }
    }

    @MainActor
    private func stopStreaming() {
        for (_, task) in streamTasks {
            task.cancel()
        }
        streamTasks = [:]

        flushTask?.cancel()
        flushTask = nil

        isStreaming = false
    }

    @MainActor
    private func append(chunk: String, prefix: String, containerID: DockerContainer.ID) {
        let carry = partialLines[containerID] ?? ""
        let combined = carry + chunk
        let endsWithNewline = combined.hasSuffix("\n")
        let parts = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var completeLines = parts
        if !endsWithNewline, let last = completeLines.popLast() {
            partialLines[containerID] = last
        } else {
            partialLines[containerID] = ""
        }

        for line in completeLines {
            pendingLines.append((service: prefix, line: line))
        }
    }
}

private struct VolumeDetailView: View {
    let volume: DockerVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name).font(.title2)
                    Text(volume.driver).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            LabeledContent("Driver") { Text(volume.driver) }
            LabeledContent("Mountpoint") { Text(volume.mountpoint).textSelection(.enabled).font(.caption) }
            LabeledContent("Created") { Text(volume.createdAt.isEmpty ? "—" : volume.createdAt).font(.caption) }
            LabeledContent("ID") { Text(volume.id).textSelection(.enabled).font(.caption) }

            Spacer()
        }
        .padding()
    }
}
