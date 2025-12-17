import SwiftUI

struct ContainersView: View {
    @EnvironmentObject private var dockerService: DockerService
    @State private var selection: DockerContainer.ID?
    @State private var filter: Filter = .all
    @State private var isRefreshing = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tutti"
        case running = "Running"
        case stopped = "Stopped"

        var id: String { rawValue }
    }

    private var filteredContainers: [DockerContainer] {
        switch filter {
        case .all:
            return dockerService.containers
        case .running:
            return dockerService.containers.filter { $0.isRunning }
        case .stopped:
            return dockerService.containers.filter { !$0.isRunning }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if dockerService.backend == .unavailable {
                    ContentUnavailableView(
                        "Backend non disponibile",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text("Avvia Docker Desktop o Colima e riprova.")
                    )
                } else if filteredContainers.isEmpty {
                    ContentUnavailableView(
                        "Nessun container",
                        systemImage: "square.stack.3d.up",
                        description: Text("Tocca Aggiorna per recuperare i container.")
                    )
                } else {
                    ForEach(filteredContainers) { container in
                        NavigationLink(value: container.id) {
                            HStack(spacing: 10) {
                                Image(systemName: container.isRunning ? "circle.fill" : "circle")
                                    .foregroundStyle(container.isRunning ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(container.name)
                                        .font(.headline)
                                    Text(container.image)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !container.status.isEmpty {
                                    Text(container.status)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            if container.isRunning {
                                Button("Stop") { Task { await dockerService.stopContainer(id: container.id) } }
                                Button("Restart") { Task { await dockerService.restartContainer(id: container.id) } }
                            } else {
                                Button("Start") { Task { await dockerService.startContainer(id: container.id) } }
                            }
                            Divider()
                            Button("Rimuovi", role: .destructive) {
                                Task { await dockerService.removeContainer(id: container.id, force: true) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Container")
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

                ToolbarItem(placement: .automatic) {
                    Picker("Filtro", selection: $filter) {
                        ForEach(Filter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
            }
            .task {
                await refresh(initial: true)
            }
        } detail: {
            if let selection,
               let container = dockerService.containers.first(where: { $0.id == selection }) {
                ContainerDetailView(container: container)
            } else {
                ContentUnavailableView("Seleziona un container", systemImage: "square.stack.3d.up", description: nil)
            }
        }
    }

    @MainActor
    private func refresh(initial: Bool = false) async {
        if initial { await dockerService.resolveBackend() }
        isRefreshing = true
        defer { isRefreshing = false }
        await dockerService.fetchContainers()
    }
}

struct ContainerDetailView: View {
    @EnvironmentObject private var dockerService: DockerService
    @Environment(\.dockscanNavigate) private var navigate
    let container: DockerContainer
    @State private var details: DockerContainerDetails?
    @State private var flushTask: Task<Void, Never>?
    @State private var partialLine: String = ""
    @State private var pendingLines: [String] = []
    @StateObject private var buffer = TerminalLogBuffer(maxChars: 250_000)
    @State private var autoScroll = true
    @State private var selectedTab: Tab = .info
    @State private var isLoadingDetails = false
    @State private var isStreamingLogs = false
    @State private var logsStreamTask: Task<Void, Never>?
    private let tail: Int = 500

    enum Tab: Hashable {
        case info
        case env
        case logs
    }

    private var currentContainer: DockerContainer {
        dockerService.containers.first(where: { $0.id == container.id }) ?? container
    }

    private var volumeMounts: [DockerContainerDetails.Mount] {
        guard let details else { return [] }
        return details.mounts.filter { $0.type == "volume" && !$0.name.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch selectedTab {
                case .info:
                    infoTab
                case .env:
                    envTab
                case .logs:
                    logsTab
                }
            }
        }
        .navigationTitle(container.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Sezione", selection: $selectedTab) {
                    Text("Info").tag(Tab.info)
                    Text("Env").tag(Tab.env)
                    Text("Logs").tag(Tab.logs)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
            }
        }
        .task(id: container.id) {
            stopLogsStream()
            await loadDetails()
            startLogsStreamIfNeeded()
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .logs {
                startLogsStreamIfNeeded()
            } else {
                stopLogsStream()
            }
        }
        .onDisappear { stopLogsStream() }
    }

    private var infoTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Stato") { Text(container.status.isEmpty ? container.state : container.status) }
                    LabeledContent("Immagine") {
                        let imageName = details.flatMap { $0.image.isEmpty ? nil : $0.image } ?? currentContainer.image
                        Button(imageName) { navigate.showImage(imageName) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                    LabeledContent("ID") { Text(container.id).textSelection(.enabled).font(.caption) }
                    if let details {
                        if !details.createdAt.isEmpty {
                            LabeledContent("Creato") { Text(details.createdAt).font(.caption).textSelection(.enabled) }
                        }
                        if !details.command.isEmpty {
                            LabeledContent("Command") { Text(details.command).font(.caption).textSelection(.enabled) }
                        }
                        if !details.workingDir.isEmpty {
                            LabeledContent("Working dir") { Text(details.workingDir).font(.caption).textSelection(.enabled) }
                        }
                    }
                }
            }

            if let details, !details.networks.isEmpty {
                GroupBox("Network") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(details.networks) { net in
                            VStack(alignment: .leading, spacing: 2) {
                                Button(net.name) { navigate.showNetwork(net.name) }
                                    .buttonStyle(.link)
                                    .font(.headline)
                                if !net.ipAddress.isEmpty { Text("IP: \(net.ipAddress)").font(.caption).foregroundStyle(.secondary) }
                                if !net.gateway.isEmpty { Text("GW: \(net.gateway)").font(.caption).foregroundStyle(.secondary) }
                                if !net.macAddress.isEmpty { Text("MAC: \(net.macAddress)").font(.caption).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if !volumeMounts.isEmpty {
                GroupBox("Volumi") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(volumeMounts) { mount in
                            VStack(alignment: .leading, spacing: 2) {
                                Button(mount.name) { navigate.showVolume(mount.name) }
                                    .buttonStyle(.link)
                                    .font(.headline)

                                if !mount.destination.isEmpty {
                                    Text("Dest: \(mount.destination)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if mount.readOnly {
                                    Text("read-only")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if isLoadingDetails {
                ProgressView().padding(.top, 8)
            }
            Spacer()
        }
        .padding()
    }

    private var envTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoadingDetails {
                ProgressView()
            } else if let details, !details.env.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(details.env) { env in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(env.key)
                                    .font(.headline)
                                if !env.value.isEmpty {
                                    Text(env.value)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            } else {
                ContentUnavailableView("Nessuna variabile", systemImage: "terminal", description: Text("Env non disponibile o vuoto."))
            }
        }
        .padding()
    }

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isStreamingLogs {
                ProgressView()
                    .controlSize(.small)
            }

            if !currentContainer.isRunning {
                ContentUnavailableView("Container non in running", systemImage: "stop.circle", description: Text("Avvia il container per leggere i log."))
            } else if buffer.isEmpty, isStreamingLogs {
                ProgressView()
            } else if buffer.isEmpty {
                ContentUnavailableView("Nessun log", systemImage: "doc.text", description: Text("In attesa di output dal container."))
            } else {
                HStack {
                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                    Button("Pulisci") { clearLogs() }
                }

                TerminalLogTextView(buffer: buffer, autoScroll: $autoScroll)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
            }
            Spacer()
        }
        .padding()
    }

    @MainActor
    private func loadDetails() async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        do {
            details = try await dockerService.fetchContainerDetails(id: container.id)
        } catch {
            dockerService.setError(error)
        }
    }

    @MainActor
    private func startLogsStreamIfNeeded() {
        guard selectedTab == .logs else { return }
        startLogsStream()
    }

    @MainActor
    private func startLogsStream() {
        stopLogsStream()
        clearLogs()
        isStreamingLogs = true

        logsStreamTask = Task {
            var isFirstConnection = true

            while !Task.isCancelled {
                do {
                    let tailForAttempt = isFirstConnection ? tail : 0
                    isFirstConnection = false

                    var didReceive = false
                    for try await chunk in dockerService.streamContainerLogs(id: container.id, tail: tailForAttempt) {
                        await MainActor.run {
                            if !didReceive {
                                didReceive = true
                                isStreamingLogs = false
                            }
                            append(chunk)
                        }
                    }

                    await MainActor.run {
                        if buffer.isEmpty {
                            isStreamingLogs = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        dockerService.setError(error)
                        isStreamingLogs = false
                    }
                }

                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run { isStreamingLogs = true }
            }
        }
    }

    @MainActor
    private func stopLogsStream() {
        logsStreamTask?.cancel()
        logsStreamTask = nil
        flushTask?.cancel()
        flushTask = nil
        isStreamingLogs = false
    }

    @MainActor
    private func appendLogs(_ chunk: String) {
        append(chunk)
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

    @MainActor
    private func clearLogs() {
        buffer.clear()
        pendingLines = []
        partialLine = ""
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
}

#if DEBUG
struct ContainersView_Previews: PreviewProvider {
    static var previews: some View {
        ContainersView()
            .environmentObject(DockerService())
    }
}
#endif
