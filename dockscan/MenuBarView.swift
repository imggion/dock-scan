#if os(macOS)
import SwiftUI
import AppKit
import Foundation

struct MenuBarView: View {
    private enum Section: CaseIterable, Hashable {
        case containers
        case stacks
        case images
        case volumes
        case networks

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
            case .containers: return "square.stack.3d.up"
            case .stacks: return "square.stack.3d.up.fill"
            case .images: return "shippingbox"
            case .volumes: return "externaldrive"
            case .networks: return "network"
            }
        }
    }

    @EnvironmentObject private var dockerService: DockerService
    @State private var section: Section = .containers
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var isTogglingBackend = false
    @State private var confirmingKillAll = false
    @State private var expandedStacks = Set<String>()

    private let autoRefreshIntervalNanoseconds: UInt64 = 5_000_000_000

    private var filteredContainers: [DockerContainer] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return dockerService.containers }
        return dockerService.containers.filter { container in
            container.name.localizedCaseInsensitiveContains(trimmed) ||
                container.image.localizedCaseInsensitiveContains(trimmed) ||
                container.status.localizedCaseInsensitiveContains(trimmed) ||
                container.portSummary.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var stackGroups: [DockerStackGroup] {
        dockerService.containers.groupedByStack()
    }

    private var filteredStackGroups: [DockerStackGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return stackGroups }

        return stackGroups.compactMap { group in
            if group.name.localizedCaseInsensitiveContains(trimmed) { return group }
            let matchingContainers = group.containers.filter { container in
                container.name.localizedCaseInsensitiveContains(trimmed) ||
                    container.image.localizedCaseInsensitiveContains(trimmed) ||
                    container.status.localizedCaseInsensitiveContains(trimmed) ||
                    container.portSummary.localizedCaseInsensitiveContains(trimmed) ||
                    (container.stackServiceName?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
            guard !matchingContainers.isEmpty else { return nil }
            return DockerStackGroup(id: group.id, name: group.name, kindLabel: group.kindLabel, containers: matchingContainers)
        }
    }

    private var filteredUngroupedContainers: [DockerContainer] {
        let candidates = dockerService.containers.filter { ($0.stackName ?? "").isEmpty }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return candidates }
        return candidates.filter { container in
            container.name.localizedCaseInsensitiveContains(trimmed) ||
                container.image.localizedCaseInsensitiveContains(trimmed) ||
                container.status.localizedCaseInsensitiveContains(trimmed) ||
                container.portSummary.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                header
                Divider()
                contentList
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                globalActions
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(9)
        }
        .frame(width: 340, height: 480)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.15), value: section)
        .alert("Kill all running containers?", isPresented: $confirmingKillAll) {
            Button("Cancel", role: .cancel) {}
            Button("Kill All", role: .destructive) {
                Task { await dockerService.killAllRunningContainers() }
            }
        } message: {
            Text("This will send SIGKILL to all running containers.")
        }
        .task(id: dockerService.backendPreference) {
            await refreshCurrent(setRefreshing: true)
            await autoRefreshLoop()
        }
        .onChange(of: section) { _, newValue in
            guard dockerService.backend != .unavailable else { return }
            guard shouldFetchOnSectionChange(newValue) else { return }
            Task { await refreshCurrent(setRefreshing: true) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openDashboard()
            } label: {
                HStack(spacing: 8) {
                    Label("Open Dashboard", systemImage: "rectangle.and.hand.point.up.left")
                        .labelStyle(.titleAndIcon)
                    Spacer(minLength: 10)
                    Text("⌘O")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    private var contentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            listHeader

            if dockerService.backend == .unavailable {
                Text("Docker backend unavailable.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if isRefreshing && isCurrentSectionEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading \(section.title)…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isCurrentSectionEmpty {
                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? emptyStateTitle : "No matches.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        contentRows
                    }
                    .padding(.vertical, 1)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var listHeader: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(Section.allCases, id: \.self) { candidate in
                    Button {
                        if shouldFetchOnSectionChange(candidate) {
                            isRefreshing = true
                        }
                        section = candidate
                    } label: {
                        Label(candidate.title, systemImage: candidate.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Text("\(currentCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            if section == .images {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(imagesTotalSizeString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await refreshCurrent(setRefreshing: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(isRefreshing ? .degrees(120) : .degrees(0))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(isRefreshing)
        }
        .animation(.easeInOut(duration: 0.15), value: section)
    }

    @ViewBuilder
    private var contentRows: some View {
        switch section {
        case .containers:
            ForEach(filteredContainers) { container in
                MenuBarContainerRow(container: container) { action in
                    Task { await performContainerAction(action, for: container) }
                }
                .contextMenu { containerContextMenu(for: container) }
            }
        case .stacks:
            ForEach(filteredStackGroups) { group in
                DisclosureGroup(isExpanded: stackExpansionBinding(group.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(group.containers) { container in
                            MenuBarContainerRow(
                                container: container,
                                title: container.stackServiceName ?? container.name
                            ) { action in
                                Task { await performContainerAction(action, for: container) }
                            }
                            .padding(.leading, 14)
                            .contextMenu { containerContextMenu(for: container) }
                        }
                    }
                    .padding(.top, 2)
                } label: {
                    MenuBarStackHeaderRow(group: group)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }

            if !filteredUngroupedContainers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ungrouped")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)

                    ForEach(filteredUngroupedContainers) { container in
                        MenuBarContainerRow(container: container) { action in
                            Task { await performContainerAction(action, for: container) }
                        }
                        .contextMenu { containerContextMenu(for: container) }
                    }
                }
            }
        case .images:
            ForEach(filteredImages, id: \.self) { image in
                MenuBarImageRow(
                    image: image,
                    isInUse: isImageInUse(image),
                    isDangling: image.tags.isEmpty
                )
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            Task { await dockerService.removeImage(id: image.id, force: false) }
                        }
                    }
            }
        case .volumes:
            ForEach(filteredVolumes, id: \.self) { volume in
                MenuBarVolumeRow(volume: volume)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            Task { await dockerService.removeVolume(name: volume.name) }
                        }
                    }
            }
        case .networks:
            ForEach(filteredNetworks, id: \.self) { network in
                MenuBarNetworkRow(network: network)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            Task { await dockerService.removeNetwork(id: network.id) }
                        }
                    }
            }
        }
    }

    private var filteredImages: [DockerImage] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return dockerService.images }
        return dockerService.images.filter { image in
            image.id.localizedCaseInsensitiveContains(trimmed) ||
                image.tags.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) })
        }
    }

    private var filteredVolumes: [DockerVolume] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return dockerService.volumes }
        return dockerService.volumes.filter { volume in
            volume.name.localizedCaseInsensitiveContains(trimmed) ||
                volume.driver.localizedCaseInsensitiveContains(trimmed) ||
                volume.mountpoint.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var containerImageRefs: Set<String> {
        Set(dockerService.containers.map { $0.image.lowercased() })
    }

    private func isImageInUse(_ image: DockerImage) -> Bool {
        let refs = containerImageRefs
        if refs.contains(image.id.lowercased()) { return true }

        let idNoPrefix = image.id.replacingOccurrences(of: "sha256:", with: "").lowercased()
        if refs.contains(idNoPrefix) { return true }
        if idNoPrefix.count >= 12 && refs.contains(String(idNoPrefix.prefix(12))) { return true }

        for tag in image.tags {
            if refs.contains(tag.lowercased()) { return true }
        }
        return false
    }

    private var filteredNetworks: [DockerNetwork] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return dockerService.networks }
        return dockerService.networks.filter { network in
            network.name.localizedCaseInsensitiveContains(trimmed) ||
                network.driver.localizedCaseInsensitiveContains(trimmed) ||
                network.scope.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var currentCount: Int {
        switch section {
        case .containers: return filteredContainers.count
        case .stacks: return filteredStackGroups.count
        case .images: return filteredImages.count
        case .volumes: return filteredVolumes.count
        case .networks: return filteredNetworks.count
        }
    }

    private var isCurrentSectionEmpty: Bool {
        switch section {
        case .stacks:
            return filteredStackGroups.isEmpty && filteredUngroupedContainers.isEmpty
        default:
            return currentCount == 0
        }
    }

    private var imagesTotalSizeString: String {
        let total = dockerService.images.reduce(Int64(0)) { partial, image in
            partial + image.sizeBytes
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    private var emptyStateTitle: String {
        switch section {
        case .containers: return "No containers."
        case .stacks: return "No stacks."
        case .images: return "No images."
        case .volumes: return "No volumes."
        case .networks: return "No networks."
        }
    }

    private var globalActions: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isBackendOnline ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)

                Menu {
                    Button("Automatic") {
                        dockerService.setBackendPreference(.automatic)
                        Task { await dockerService.ping() }
                    }
                    Button("Colima") {
                        dockerService.setBackendPreference(.colima)
                        Task { await dockerService.ping() }
                    }
                    Button("Docker") {
                        dockerService.setBackendPreference(.docker)
                        Task { await dockerService.ping() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(socketStatusText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .disabled(isTogglingBackend)

                Button {
                    Task { await toggleBackend() }
                } label: {
                    Image(systemName: isBackendOnline ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isTogglingBackend || dockerService.backend == .custom)
            }

            Spacer()

            Button(role: .destructive) {
                confirmingKillAll = true
            } label: {
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(dockerService.containers.allSatisfy { !$0.isRunning })

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    @MainActor
    private func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }

        await dockerService.resolveBackend()
        guard dockerService.backend != .unavailable else {
            await dockerService.ping()
            return
        }

        await dockerService.fetchContainers()
        await dockerService.fetchImages()
        await dockerService.fetchVolumes()
        await dockerService.fetchNetworks()
        await dockerService.ping()
    }

    private func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func shouldFetchOnSectionChange(_ newValue: Section) -> Bool {
        switch newValue {
        case .containers:
            return dockerService.containers.isEmpty
        case .stacks:
            return dockerService.containers.isEmpty
        case .images:
            return dockerService.images.isEmpty
        case .volumes:
            return dockerService.volumes.isEmpty
        case .networks:
            return dockerService.networks.isEmpty
        }
    }

    private func stackExpansionBinding(_ stackID: String) -> Binding<Bool> {
        Binding(
            get: { expandedStacks.contains(stackID) },
            set: { isExpanded in
                if isExpanded {
                    expandedStacks.insert(stackID)
                } else {
                    expandedStacks.remove(stackID)
                }
            }
        )
    }

    private func performContainerAction(_ action: MenuBarContainerRow.Action, for container: DockerContainer) async {
        switch action {
        case .start:
            await dockerService.startContainer(id: container.id)
        case .stop:
            await dockerService.stopContainer(id: container.id)
        case .restart:
            await dockerService.restartContainer(id: container.id)
        }
    }

    @ViewBuilder
    private func containerContextMenu(for container: DockerContainer) -> some View {
        let goToLinks = goToLinks(for: container)

        if container.isRunning {
            Button("Stop") { Task { await dockerService.stopContainer(id: container.id) } }
            Button("Restart") { Task { await dockerService.restartContainer(id: container.id) } }
        } else {
            Button("Start") { Task { await dockerService.startContainer(id: container.id) } }
        }

        if container.isRunning, !goToLinks.isEmpty {
            Divider()
            Menu("Go to") {
                ForEach(goToLinks, id: \.self) { link in
                    Button(link.label) {
                        openWebURL(host: link.host, port: link.port)
                    }
                }
            }
        }

        Divider()
        Button("Remove", role: .destructive) {
            Task { await dockerService.removeContainer(id: container.id, force: true) }
        }
    }

    private func openWebURL(host: String, port: Int) {
        guard let url = URL(string: "http://\(host):\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    private struct GoToLink: Hashable {
        let host: String
        let port: Int

        var label: String { "\(host):\(port)" }
    }

    private func goToLinks(for container: DockerContainer) -> [GoToLink] {
        let sortedPorts = container.ports
            .filter { $0.publicPort != nil }
            .sorted { ($0.publicPort ?? 0, $0.privatePort, $0.type) < ($1.publicPort ?? 0, $1.privatePort, $1.type) }

        var seen = Set<GoToLink>()
        var links: [GoToLink] = []
        links.reserveCapacity(sortedPorts.count)

        for port in sortedPorts {
            let host = (port.ip?.isEmpty == false && port.ip != "0.0.0.0") ? (port.ip ?? "localhost") : "localhost"
            let publicPort = port.publicPort ?? port.privatePort
            let link = GoToLink(host: host, port: publicPort)
            if seen.insert(link).inserted {
                links.append(link)
            }
        }

        return links
    }

    private var isBackendOnline: Bool {
        guard dockerService.backend != .unavailable else { return false }
        guard let lastPing = dockerService.lastPing else { return false }
        return lastPing.hasPrefix("HTTP 200")
    }

    private var socketStatusText: String {
        let backendName: String = {
            switch dockerService.backendPreference {
            case .automatic:
                switch dockerService.backend {
                case .docker: return "Docker"
                case .colima: return "Colima"
                case .custom: return "Socket"
                case .unavailable: return "Auto"
                }
            case .docker:
                return "Docker"
            case .colima:
                return "Colima"
            }
        }()

        if isTogglingBackend {
            return isBackendOnline ? "\(backendName) stopping…" : "\(backendName) starting…"
        }

        if dockerService.backend == .unavailable {
            return dockerService.backendPreference == .automatic ? "Socket disconnected" : "\(backendName) disconnected"
        }

        return isBackendOnline ? "\(backendName) connected" : "\(backendName) disconnected"
    }

    private func toggleBackend() async {
        guard !isTogglingBackend else { return }
        isTogglingBackend = true
        defer { isTogglingBackend = false }

        await dockerService.ping()
        let wasOnline = isBackendOnline

        do {
            let targetBackend: DockerBackend? = {
                switch dockerService.backendPreference {
                case .automatic:
                    return nil
                case .docker:
                    return .docker
                case .colima:
                    return .colima
                }
            }()

            if wasOnline {
                switch targetBackend ?? dockerService.backend {
                case .docker:
                    stopDockerDesktop()
                case .colima:
                    try await runColima(arguments: ["stop"])
                case .custom, .unavailable:
                    break
                }
            } else {
                switch targetBackend {
                case .docker?:
                    startDockerDesktop()
                case .colima?:
                    try await runColima(arguments: ["start"])
                case nil:
                    if colimaIsAvailable() {
                        try await runColima(arguments: ["start"])
                    } else {
                        startDockerDesktop()
                    }
                case .custom?, .unavailable?:
                    break
                }
            }
        } catch {
            dockerService.setError(error)
        }

        await waitForBackend(shouldBeOnline: !wasOnline, timeoutSeconds: 20)
    }

    private func waitForBackend(shouldBeOnline: Bool, timeoutSeconds: Int) async {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            await dockerService.resolveBackend()
            await dockerService.ping()
            let online = isBackendOnline
            if shouldBeOnline == online { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func stopDockerDesktop() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.docker.docker")
        for app in apps {
            app.terminate()
        }
    }

    private func startDockerDesktop() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.docker.docker") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            NSWorkspace.shared.launchApplication("Docker")
        }
    }

    private func colimaIsAvailable() -> Bool {
        colimaExecutableURL() != nil
    }

    private func colimaExecutableURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/colima",
            "/usr/local/bin/colima"
        ]
        let fileManager = FileManager.default
        return candidates.first(where: { fileManager.fileExists(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    private func cliEnvironmentWithHomebrewPaths() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let combined = (extra + existingPath.split(separator: ":").map(String.init))
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { acc, item in
                if !acc.contains(item) { acc.append(item) }
            }
            .joined(separator: ":")
        env["PATH"] = combined
        return env
    }

    private func runColima(arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.environment = cliEnvironmentWithHomebrewPaths()
            if let colima = colimaExecutableURL() {
                process.executableURL = colima
                process.arguments = arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["colima"] + arguments
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let err = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: err, encoding: .utf8) ?? "Failed to run colima."
                throw NSError(domain: "dockscan.colima", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errStr])
            }
        }.value
    }

    @MainActor
    private func refreshCurrent(setRefreshing: Bool) async {
        if setRefreshing {
            isRefreshing = true
        }
        defer {
            if setRefreshing {
                isRefreshing = false
            }
        }

        await dockerService.resolveBackend()
        guard dockerService.backend != .unavailable else {
            await dockerService.ping()
            return
        }
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
        await dockerService.ping()
    }

    private func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: autoRefreshIntervalNanoseconds)
            if Task.isCancelled { return }
            if isTogglingBackend || isRefreshing { continue }
            await refreshCurrent(setRefreshing: false)
        }
    }
}

private struct MenuBarStackHeaderRow: View {
    let group: DockerStackGroup

    private var statusTint: Color {
        if group.errorCount > 0 { return .red }
        if group.runningCount == group.containers.count { return .green }
        if group.runningCount == 0 { return .secondary }
        return .yellow
    }

    private var subtitle: String {
        var parts: [String] = []
        if let kind = group.kindLabel { parts.append(kind) }
        parts.append("\(group.runningCount)/\(group.containers.count) running")
        if group.errorCount > 0 { parts.append("\(group.errorCount) error") }
        return parts.joined(separator: "  •  ")
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusTint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }
}

private struct MenuBarContainerRow: View {
    enum Action {
        case start
        case stop
        case restart
    }

    let container: DockerContainer
    let title: String
    let subtitle: String
    let action: (Action) -> Void

    @State private var isHovering = false

    init(container: DockerContainer, title: String? = nil, subtitle: String? = nil, action: @escaping (Action) -> Void) {
        self.container = container
        self.title = title ?? container.name
        self.subtitle = subtitle ?? container.image
        self.action = action
    }

    private var trailingText: String {
        let ports = container.portSummary
        return ports
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(container.isRunning ? Color.green : (container.isError ? Color.red : Color.secondary))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if !trailingText.isEmpty {
                Text(trailingText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if container.isRunning {
                    Button {
                        action(.restart)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        action(.stop)
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                } else {
                    Button {
                        action(.start)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct MenuBarImageRow: View {
    let image: DockerImage
    let isInUse: Bool
    let isDangling: Bool

    private var iconTint: Color {
        if isInUse { return .green }
        if isDangling { return .orange }
        return .secondary
    }

    private var title: String {
        image.tags.first ?? image.id
    }

    private var subtitle: String {
        if image.tags.count <= 1 { return image.id }
        return "\(image.id)  •  +\(image.tags.count - 1) tags"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconTint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            Text(ByteCountFormatter.string(fromByteCount: image.sizeBytes, countStyle: .file))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }
}

private struct MenuBarVolumeRow: View {
    let volume: DockerVolume

    private var iconTint: Color {
        volume.isInUse ? .green : .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconTint)

            VStack(alignment: .leading, spacing: 1) {
                Text(volume.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(volume.driver)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if let refCount = volume.refCount {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .opacity(volume.isInUse ? 1 : 0.35)
                    Text("\(refCount)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if !volume.mountpoint.isEmpty {
                Text(volume.mountpoint)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }
}

private struct MenuBarNetworkRow: View {
    let network: DockerNetwork

    private var iconTint: Color {
        network.isInUse ? .green : .secondary
    }

    private var subtitle: String {
        if network.scope.isEmpty { return network.driver }
        if network.driver.isEmpty { return network.scope }
        return "\(network.driver)  •  \(network.scope)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconTint)

            VStack(alignment: .leading, spacing: 1) {
                Text(network.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if let count = network.containerCount {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .opacity(network.isInUse ? 1 : 0.35)
                    Text("\(count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }
}

#if DEBUG
struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView()
            .environmentObject(DockerService())
    }
}
#endif
#endif
