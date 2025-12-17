//  DockerService.swift
//  dockscan
//  Created as part of the initial Docker/Colima integration plan.

import Foundation
import Combine
import Darwin
#if os(macOS)
import AppKit
#endif

// Enum for backend types
public enum DockerBackend: String, CaseIterable, Identifiable {
    case docker
    case colima
    case custom
    case unavailable

    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .docker: return "Docker"
        case .colima: return "Colima"
        case .custom: return "Custom"
        case .unavailable: return "Nessuno"
        }
    }

    fileprivate static func candidateSocketPaths(home: String) -> [(DockerBackend, [String])] {
        return [
            (.colima, [
                "\(home)/.colima/docker.sock",
                "\(home)/.colima/default/docker.sock"
            ]),
            (.docker, [
                "\(home)/.docker/run/docker.sock",
                "/var/run/docker.sock"
            ])
        ]
    }
}

public enum DockerBackendPreference: String, CaseIterable, Identifiable {
    case automatic
    case docker
    case colima

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .docker: return "Docker"
        case .colima: return "Colima"
        }
    }

    fileprivate var restrictedBackend: DockerBackend? {
        switch self {
        case .automatic: return nil
        case .docker: return .docker
        case .colima: return .colima
        }
    }
}

// Semplice modello per Container
public struct DockerContainer: Identifiable, Decodable, Hashable {
    public struct Port: Decodable, Hashable {
        public let ip: String?
        public let privatePort: Int
        public let publicPort: Int?
        public let type: String

        public var displayString: String {
            if let publicPort {
                return "\(publicPort):\(privatePort)"
            }
            return ""
        }
    }

    public let id: String
    public let name: String
    public let image: String
    public let state: String
    public let status: String
    public let createdAt: Date?
    public let ports: [Port]
    public let labels: [String: String]

    public var isRunning: Bool { state == "running" }
    public var isError: Bool {
        if state == "dead" { return true }
        if let code = exitCodeFromStatus(status), code != 0 { return true }
        return false
    }

    public var stackName: String? {
        labels["com.docker.compose.project"] ?? labels["com.docker.stack.namespace"]
    }

    public var stackServiceName: String? {
        labels["com.docker.compose.service"] ?? labels["com.docker.swarm.service.name"]
    }

    public var stackKindLabel: String? {
        if labels["com.docker.compose.project"] != nil { return "Compose" }
        if labels["com.docker.stack.namespace"] != nil { return "Swarm" }
        return nil
    }

    public var portSummary: String {
        let sortedPorts = ports
            .filter { $0.publicPort != nil }
            .sorted { ($0.publicPort ?? -1, $0.privatePort, $0.type) < ($1.publicPort ?? -1, $1.privatePort, $1.type) }

        var seen = Set<String>()
        var unique: [String] = []
        unique.reserveCapacity(sortedPorts.count)
        for port in sortedPorts {
            let mapped = port.displayString
            guard !mapped.isEmpty else { continue }
            if seen.insert(mapped).inserted {
                unique.append(mapped)
            }
        }

        return unique.prefix(2).joined(separator: "  ")
    }

    private func exitCodeFromStatus(_ raw: String) -> Int? {
        guard let exitedRange = raw.range(of: "Exited (") else { return nil }
        let after = raw[exitedRange.upperBound...]
        guard let closeIndex = after.firstIndex(of: ")") else { return nil }
        let digits = after[..<closeIndex]
        return Int(digits)
    }
}

// Semplice modello per Volume
public struct DockerVolume: Identifiable, Decodable, Hashable {
    public let id: String
    public let name: String
    public let driver: String
    public let mountpoint: String
    public let createdAt: String
    public let refCount: Int?
    public let sizeBytes: Int64?

    public var isInUse: Bool { (refCount ?? 0) > 0 }
}

public struct DockerImage: Identifiable, Decodable, Hashable {
    public let id: String
    public let tags: [String]
    public let sizeBytes: Int64
    public let createdAt: Date?
}

public struct DockerNetwork: Identifiable, Decodable, Hashable {
    public let id: String
    public let name: String
    public let driver: String
    public let scope: String
    public let createdAt: Date?
    public let containerCount: Int?

    public var isInUse: Bool { (containerCount ?? 0) > 0 }
}

public struct DockerContainerDetails: Identifiable, Hashable {
    public struct EnvVar: Identifiable, Hashable {
        public var id: String { key }
        public let key: String
        public let value: String
    }

    public struct NetworkAttachment: Identifiable, Hashable {
        public var id: String { name }
        public let name: String
        public let ipAddress: String
        public let macAddress: String
        public let gateway: String
    }

    public struct Mount: Identifiable, Hashable {
        public var id: String { "\(type)::\(name)::\(destination)::\(source)" }
        public let type: String
        public let name: String
        public let source: String
        public let destination: String
        public let readOnly: Bool
    }

    public let id: String
    public let name: String
    public let image: String
    public let createdAt: String
    public let state: String
    public let status: String
    public let workingDir: String
    public let command: String
    public let env: [EnvVar]
    public let networks: [NetworkAttachment]
    public let mounts: [Mount]
}

// Decoding helpers per API Docker /volumes
private struct DockerVolumesResponse: Decodable {
    let Volumes: [DockerVolumeItem]?
}

private struct DockerVolumeItem: Decodable {
    let Name: String
    let Driver: String
    let Mountpoint: String
    let CreatedAt: String?
    let UsageData: DockerVolumeUsageData?
}

private struct DockerVolumeUsageData: Decodable {
    let RefCount: Int?
    let Size: Int64?
}
private struct DockerErrorResponse: Decodable {
    let message: String?
}

private struct DockerContainerAPI: Decodable {
    let Id: String
    let Names: [String]?
    let Image: String
    let State: String?
    let Status: String?
    let Created: Int?
    let Ports: [DockerContainerPortAPI]?
    let Labels: [String: String]?
}

private struct DockerContainerPortAPI: Decodable {
    let ip: String?
    let privatePort: Int?
    let publicPort: Int?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case ip = "IP"
        case privatePort = "PrivatePort"
        case publicPort = "PublicPort"
        case type = "Type"
    }
}

private struct DockerImageAPI: Decodable {
    let Id: String
    let RepoTags: [String]?
    let Size: Int64?
    let Created: Int64?
}

private struct DockerNetworkAPI: Decodable {
    let Id: String
    let Name: String
    let Driver: String
    let Scope: String?
    let Created: String?
    let Containers: [String: DockerNetworkContainerAPI]?
}

private struct DockerNetworkContainerAPI: Decodable {
    let Name: String?
    let EndpointID: String?
    let IPv4Address: String?
    let IPv6Address: String?
    let MacAddress: String?
}

private enum DockerDateParser {
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = iso8601.date(from: raw) { return date }
        if let date = iso8601NoFraction.date(from: raw) { return date }
        return nil
    }
}

private struct DockerContainerInspectAPI: Decodable {
    let Id: String
    let Name: String?
    let Created: String?
    let Path: String?
    let Args: [String]?
    let Config: DockerContainerInspectConfig?
    let State: DockerContainerInspectState?
    let NetworkSettings: DockerContainerInspectNetworkSettings?
    let Mounts: [DockerContainerInspectMount]?
}

private struct DockerContainerInspectConfig: Decodable {
    let Image: String?
    let Env: [String]?
    let WorkingDir: String?
}

private struct DockerContainerInspectState: Decodable {
    let Status: String?
}

private struct DockerContainerInspectNetworkSettings: Decodable {
    let Networks: [String: DockerContainerInspectNetwork]?
}

private struct DockerContainerInspectNetwork: Decodable {
    let IPAddress: String?
    let MacAddress: String?
    let Gateway: String?
}

private struct DockerContainerInspectMount: Decodable {
    let type: String?
    let name: String?
    let source: String?
    let destination: String?
    let rw: Bool?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case name = "Name"
        case source = "Source"
        case destination = "Destination"
        case rw = "RW"
    }
}

// Service principale per detection backend e fetch dati
@MainActor
public final class DockerService: ObservableObject {
    @Published public private(set) var backend: DockerBackend = .unavailable
    @Published public private(set) var backendPreference: DockerBackendPreference = .automatic
    @Published public private(set) var socketPath: String? = nil
    @Published public private(set) var detectionLog: String = ""
    @Published public private(set) var lastPing: String? = nil
    @Published public private(set) var containers: [DockerContainer] = []
    @Published public private(set) var volumes: [DockerVolume] = []
    @Published public private(set) var images: [DockerImage] = []
    @Published public private(set) var networks: [DockerNetwork] = []
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var socketInfo: DockerSocketInfo? = nil
    @Published public private(set) var isLoadingSocketInfo: Bool = false

    private var resolvedSocketPath: String? = nil
    private var customSocketPath: String? = UserDefaults.standard.string(forKey: "Dockscan.CustomSocketPath")
#if os(macOS)
    private var securityScopedSocketURL: URL? = nil
    private var isAccessingSecurityScopedURL: Bool = false
#endif

    public init() {
        if let raw = UserDefaults.standard.string(forKey: "Dockscan.BackendPreference"),
           let pref = DockerBackendPreference(rawValue: raw) {
            backendPreference = pref
        }
        detectBackend()
    }

    public func setBackendPreference(_ preference: DockerBackendPreference) {
        backendPreference = preference
        UserDefaults.standard.set(preference.rawValue, forKey: "Dockscan.BackendPreference")
    }

    public func clearError() {
        errorMessage = nil
    }

    public func setErrorMessage(_ message: String?) {
        errorMessage = message
    }

    public func setError(_ error: Error) {
        setErrorMessage((error as NSError).localizedDescription)
    }

    private static func realUserHomeDirectory() -> String {
        if let home = getenv("HOME") {
            return String(cString: home)
        }
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private static func dockerHostSocketPathFromEnv() -> String? {
        guard let raw = getenv("DOCKER_HOST").map({ String(cString: $0) }),
              !raw.isEmpty else { return nil }
        if raw.hasPrefix("unix://") {
            return String(raw.dropFirst("unix://".count))
        }
        if raw.hasPrefix("unix:") {
            return String(raw.dropFirst("unix:".count))
        }
        return nil
    }

    public func setCustomSocketPath(_ path: String?) {
        customSocketPath = path
        if let path {
            UserDefaults.standard.set(path, forKey: "Dockscan.CustomSocketPath")
        } else {
            UserDefaults.standard.removeObject(forKey: "Dockscan.CustomSocketPath")
        }
        detectBackend()
    }

#if os(macOS)
    public func setCustomSocketURL(_ url: URL?) {
        if isAccessingSecurityScopedURL, let existing = securityScopedSocketURL {
            existing.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedURL = false
        }

        securityScopedSocketURL = url
        if let url {
            isAccessingSecurityScopedURL = url.startAccessingSecurityScopedResource()
            setCustomSocketPath(url.path)
        } else {
            setCustomSocketPath(nil)
        }
    }
#endif

    /// Determina quale backend è disponibile (Docker o Colima)
    public func detectBackend() {
        let fileManager = FileManager.default
        let home = Self.realUserHomeDirectory()

        func resolvedSocketIfAvailable(at path: String) -> String? {
            guard fileManager.fileExists(atPath: path) else { return nil }

            let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard fileManager.fileExists(atPath: resolvedPath) else { return nil }

            guard let attrs = try? fileManager.attributesOfItem(atPath: resolvedPath),
                  let type = attrs[.type] as? FileAttributeType else { return nil }

            if type == .typeSocket { return resolvedPath }
            return nil
        }

        func describeCandidate(_ backend: DockerBackend, _ path: String) -> String {
            if let resolved = resolvedSocketIfAvailable(at: path) {
                return "✓ [\(backend.displayName)] \(path) -> \(resolved)"
            }
            if fileManager.fileExists(atPath: path) {
                let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                let type = (try? fileManager.attributesOfItem(atPath: resolved)[.type] as? FileAttributeType) ?? nil
                return "• [\(backend.displayName)] \(path) (tipo: \(type?.rawValue ?? "sconosciuto"))"
            }
            return "✗ [\(backend.displayName)] \(path)"
        }

        func colimaProfileSockets() -> [String] {
            let root = "\(home)/.colima"
            guard let dirs = try? fileManager.contentsOfDirectory(atPath: root) else { return [] }
            return dirs.map { "\(root)/\($0)/docker.sock" }
        }

        var logLines: [String] = []
        logLines.append("HOME: \(home)")
        if let env = Self.dockerHostSocketPathFromEnv() {
            logLines.append("DOCKER_HOST: \(env)")
        }
        if let customSocketPath {
            logLines.append("Custom: \(customSocketPath)")
        }

        if let customSocketPath, let socket = resolvedSocketIfAvailable(at: customSocketPath) {
            backend = .custom
            resolvedSocketPath = socket
            socketPath = socket
            logLines.append("Selezionato: Custom -> \(socket)")
            detectionLog = logLines.joined(separator: "\n")
            return
        }

        if let env = Self.dockerHostSocketPathFromEnv(), let socket = resolvedSocketIfAvailable(at: env) {
            backend = .custom
            resolvedSocketPath = socket
            socketPath = socket
            logLines.append("Selezionato: DOCKER_HOST -> \(socket)")
            detectionLog = logLines.joined(separator: "\n")
            return
        }

        let candidates: [(DockerBackend, [String])] = {
            if let restricted = backendPreference.restrictedBackend {
                let paths = DockerBackend.candidateSocketPaths(home: home)
                    .first(where: { $0.0 == restricted })?
                    .1 ?? []
                if restricted == .colima {
                    return [(restricted, paths + colimaProfileSockets())]
                }
                return [(restricted, paths)]
            }
            return DockerBackend.candidateSocketPaths(home: home).map { backend, base in
                if backend == .colima { return (backend, base + colimaProfileSockets()) }
                return (backend, base)
            }
        }()

        for (candidateBackend, paths) in candidates {
            logLines.append(contentsOf: paths.map { describeCandidate(candidateBackend, $0) })
            if let socket = paths.compactMap(resolvedSocketIfAvailable).first {
                backend = candidateBackend
                resolvedSocketPath = socket
                socketPath = socket
                logLines.append("Selezionato: \(candidateBackend.displayName) -> \(socket)")
                detectionLog = logLines.joined(separator: "\n")
                return
            }
        }

        backend = .unavailable
        resolvedSocketPath = nil
        socketPath = nil
        logLines.append("Selezionato: Nessuno")
        detectionLog = logLines.joined(separator: "\n")
    }

    public func resolveBackend() async {
        let fileManager = FileManager.default
        let home = Self.realUserHomeDirectory()

        func resolvedSocketIfAvailable(at path: String) -> String? {
            guard fileManager.fileExists(atPath: path) else { return nil }
            let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard fileManager.fileExists(atPath: resolvedPath) else { return nil }
            guard let attrs = try? fileManager.attributesOfItem(atPath: resolvedPath),
                  let type = attrs[.type] as? FileAttributeType,
                  type == .typeSocket else { return nil }
            return resolvedPath
        }

        func colimaProfileSockets() -> [String] {
            let root = "\(home)/.colima"
            guard let dirs = try? fileManager.contentsOfDirectory(atPath: root) else { return [] }
            return dirs.map { "\(root)/\($0)/docker.sock" }
        }

        var candidates: [(DockerBackend, String)] = []
        if let customSocketPath { candidates.append((.custom, customSocketPath)) }
        if let env = Self.dockerHostSocketPathFromEnv() { candidates.append((.custom, env)) }

        let restricted = backendPreference.restrictedBackend
        if restricted == nil || restricted == .colima {
            candidates.append(contentsOf: [
                (.colima, "\(home)/.colima/default/docker.sock"),
                (.colima, "\(home)/.colima/docker.sock")
            ])
            candidates.append(contentsOf: colimaProfileSockets().map { (.colima, $0) })
        }
        if restricted == nil || restricted == .docker {
            candidates.append(contentsOf: [
                (.docker, "\(home)/.docker/run/docker.sock"),
                (.docker, "/var/run/docker.sock")
            ])
        }

        for (candidateBackend, candidatePath) in candidates {
            guard let socket = resolvedSocketIfAvailable(at: candidatePath) else { continue }
            do {
                let (data, status) = try await httpRequestViaUnixSocket(socket: socket, method: "GET", endpoint: "/_ping")
                let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if status > 0, status < 400, body.uppercased().contains("OK") {
                    backend = candidateBackend
                    resolvedSocketPath = socket
                    socketPath = socket
                    return
                }
            } catch {
                continue
            }
        }

        backend = .unavailable
        resolvedSocketPath = nil
        socketPath = nil
    }

    /// Esegue una chiamata HTTP via socket UNIX usando `curl` e restituisce body + status code.
    private func httpRequestViaUnixSocket(method: String, endpoint: String, body: Data? = nil) async throws -> (Data, Int) {
        guard let socket = resolvedSocketPath else {
            throw NSError(domain: "DockerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Socket non disponibile"])
        }
        return try await httpRequestViaUnixSocket(socket: socket, method: method, endpoint: endpoint, body: body)
    }

    private func httpRequestViaUnixSocket(socket: String, method: String, endpoint: String, body: Data? = nil) async throws -> (Data, Int) {
        try await Self.runCurlViaUnixSocket(socket: socket, method: method, endpoint: endpoint, body: body)
    }

    private static func runCurlViaUnixSocket(socket: String, method: String, endpoint: String, body: Data?) async throws -> (Data, Int) {
        let url = "http://localhost\(endpoint)"
        let statusMarker = "\n__HTTP_STATUS__:"

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

            var arguments: [String] = [
                "--silent",
                "--show-error",
                "--unix-socket", socket,
                "--connect-timeout", "2",
                "--max-time", "10",
                "-X", method
            ]

            var stdinPipe: Pipe?
            if body != nil {
                let pipe = Pipe()
                stdinPipe = pipe
                process.standardInput = pipe
                arguments += ["--data-binary", "@-"]
            }

            arguments += ["-H", "Content-Type: application/json", "-w", "\(statusMarker)%{http_code}", url]
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            var stdout = Data()
            var stderr = Data()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { stdout.append(chunk) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { stderr.append(chunk) }
            }

            try process.run()
            if let body, let stdinPipe {
                stdinPipe.fileHandleForWriting.write(body)
                try? stdinPipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()

            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            stdout.append(outPipe.fileHandleForReading.readDataToEndOfFile())
            stderr.append(errPipe.fileHandleForReading.readDataToEndOfFile())

            if process.terminationStatus != 0 {
                let errStr = String(data: stderr, encoding: .utf8) ?? "Errore sconosciuto"
                throw NSError(
                    domain: "DockerService",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errStr]
                )
            }

            guard let outStr = String(data: stdout, encoding: .utf8),
                  let markerRange = outStr.range(of: statusMarker, options: .backwards) else {
                return (stdout, 0)
            }

            let bodyStr = String(outStr[..<markerRange.lowerBound])
            let statusStr = String(outStr[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let statusCode = Int(statusStr) ?? 0
            return (Data(bodyStr.utf8), statusCode)
        }.value
    }

    private func decodeDockerErrorMessage(from data: Data) -> String? {
        guard let err = try? JSONDecoder().decode(DockerErrorResponse.self, from: data) else { return nil }
        return err.message
    }

    private func decodeContainerName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
    }

    private func parseEnv(_ env: [String]?) -> [DockerContainerDetails.EnvVar] {
        let items = env ?? []
        return items.compactMap { entry in
            if let idx = entry.firstIndex(of: "=") {
                let key = String(entry[..<idx])
                let value = String(entry[entry.index(after: idx)...])
                return DockerContainerDetails.EnvVar(key: key, value: value)
            } else {
                return DockerContainerDetails.EnvVar(key: entry, value: "")
            }
        }
        .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    private func decodeDockerLogStreamIfNeeded(_ data: Data) -> String {
        guard data.count >= 8 else { return String(data: data, encoding: .utf8) ?? "" }

        var index = 0
        var output = Data()

        func u32be(at offset: Int) -> Int {
            let b0 = Int(data[offset])
            let b1 = Int(data[offset + 1])
            let b2 = Int(data[offset + 2])
            let b3 = Int(data[offset + 3])
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }

        while index + 8 <= data.count {
            let streamType = data[index]
            let size = u32be(at: index + 4)
            let payloadStart = index + 8
            let payloadEnd = payloadStart + size
            guard payloadEnd <= data.count else { break }

            if streamType == 1 || streamType == 2 {
                output.append(data[payloadStart..<payloadEnd])
            } else {
                break
            }
            index = payloadEnd
        }

        if output.isEmpty {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return String(data: output, encoding: .utf8) ?? ""
    }

    private struct DockerLogStreamDecoder {
        private(set) var isMultiplexed: Bool? = nil
        private var buffer = Data()

        mutating func push(_ chunk: Data) -> String {
            guard !chunk.isEmpty else { return "" }
            buffer.append(chunk)

            if isMultiplexed == nil {
                isMultiplexed = detectMultiplexedPrefix(buffer)
            }

            if isMultiplexed == true {
                return decodeMultiplexed()
            } else {
                let text = String(data: buffer, encoding: .utf8) ?? ""
                buffer.removeAll(keepingCapacity: true)
                return text
            }
        }

        private func detectMultiplexedPrefix(_ data: Data) -> Bool {
            guard data.count >= 8 else { return false }
            let streamType = data[0]
            guard streamType == 0 || streamType == 1 || streamType == 2 else { return false }
            if data[1] != 0 || data[2] != 0 || data[3] != 0 { return false }
            let size = (Int(data[4]) << 24) | (Int(data[5]) << 16) | (Int(data[6]) << 8) | Int(data[7])
            if size < 0 || size > 8_388_608 { return false }
            return true
        }

        private mutating func decodeMultiplexed() -> String {
            var output = Data()

            func u32be(at offset: Int) -> Int {
                let b0 = Int(buffer[offset])
                let b1 = Int(buffer[offset + 1])
                let b2 = Int(buffer[offset + 2])
                let b3 = Int(buffer[offset + 3])
                return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
            }

            while buffer.count >= 8 {
                let streamType = buffer[0]
                let size = u32be(at: 4)
                let payloadStart = 8
                let payloadEnd = payloadStart + size

                guard payloadEnd <= buffer.count else { break }

                if streamType == 1 || streamType == 2 {
                    output.append(buffer[payloadStart..<payloadEnd])
                }
                buffer.removeSubrange(0..<payloadEnd)
            }

            return String(data: output, encoding: .utf8) ?? ""
        }
    }

    public func streamContainerLogs(id: String, tail: Int = 500, timestamps: Bool = true) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                await self.resolveBackend()
                guard let socket = self.resolvedSocketPath else {
                    continuation.finish(throwing: NSError(domain: "DockerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Socket non disponibile"]))
                    return
                }

                Task.detached(priority: .userInitiated) {
                    do {
                    var decoder = DockerLogStreamDecoder()

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

                    let url = "http://localhost/containers/\(id)/logs?stdout=true&stderr=true&follow=true&tail=\(tail)&timestamps=\(timestamps ? "true" : "false")"

                    process.arguments = [
                        "--silent",
                        "--show-error",
                        "--no-buffer",
                        "-N",
                        "--unix-socket", socket,
                        "--connect-timeout", "2",
                        url
                    ]

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe

                    var stderr = Data()

                    outPipe.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        guard !chunk.isEmpty else { return }
                        let text = decoder.push(chunk)
                        if !text.isEmpty {
                            continuation.yield(text)
                        }
                    }

                    errPipe.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        if !chunk.isEmpty { stderr.append(chunk) }
                    }

                    continuation.onTermination = { _ in
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        errPipe.fileHandleForReading.readabilityHandler = nil
                        if process.isRunning {
                            process.terminate()
                        }
                        try? outPipe.fileHandleForReading.close()
                        try? errPipe.fileHandleForReading.close()
                    }

                    try process.run()
                    process.waitUntilExit()

                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil

                    let status = process.terminationStatus
                    if status != 0 {
                        let message = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? "curl error \(status)"
                        throw NSError(domain: "DockerService", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
                    }

                    continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    private func ensureBackendOrFail() async -> Bool {
        await resolveBackend()
        if backend == .unavailable {
            self.errorMessage = "Nessun backend Docker/Colima disponibile"
            self.containers = []
            self.volumes = []
            self.images = []
            self.networks = []
            return false
        }
        return true
    }

    public func ping() async {
        await resolveBackend()
        guard resolvedSocketPath != nil else {
            lastPing = "Socket non disponibile"
            return
        }
        do {
            let (data, status) = try await httpRequestViaUnixSocket(method: "GET", endpoint: "/_ping")
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lastPing = "HTTP \(status) \(body.isEmpty ? "—" : body)"
        } catch {
            lastPing = (error as NSError).localizedDescription
        }
    }

    public struct DockerSocketInfo: Hashable {
        public let vmEngine: String
        public let memoryMaxBytes: Int64?
        public let memoryAllocatedBytes: Int64?
        public let arch: String?
        public let runtime: String?
        public let mountType: String?
        public let operatingSystem: String?
        public let serverVersion: String?
    }

    public func fetchSocketInfo() async {
        await resolveBackend()
        guard resolvedSocketPath != nil, backend != .unavailable else {
            await MainActor.run {
                socketInfo = nil
                isLoadingSocketInfo = false
            }
            return
        }

        await MainActor.run { isLoadingSocketInfo = true }
        defer { Task { @MainActor in isLoadingSocketInfo = false } }

        do {
            async let infoResult = httpRequestViaUnixSocket(method: "GET", endpoint: "/info")
            async let versionResult = httpRequestViaUnixSocket(method: "GET", endpoint: "/version")

            let (infoData, infoStatus) = try await infoResult
            let (versionData, versionStatus) = try await versionResult

            let decoder = JSONDecoder()
            let info: DockerInfoAPI? = (infoStatus < 400) ? (try? decoder.decode(DockerInfoAPI.self, from: infoData)) : nil
            let version: DockerVersionAPI? = (versionStatus < 400) ? (try? decoder.decode(DockerVersionAPI.self, from: versionData)) : nil

            var memAllocated = info?.MemTotal
            var memMax: Int64? = nil
            var vmEngine = Self.defaultVMEngineLabel(backend: backend, operatingSystem: info?.OperatingSystem, socketPath: socketPath)
            var arch: String? = info?.Architecture
            var runtime: String? = nil
            var mountType: String? = nil

#if os(macOS)
            if backend == .colima {
                if let colima = try? await fetchColimaStatus() {
                    if let vmType = colima.vmType, !vmType.isEmpty {
                        vmEngine = "Colima (\(vmType))"
                    } else {
                        vmEngine = "Colima"
                    }
                    if let memoryGiB = colima.memory {
                        memMax = Int64(memoryGiB) * 1024 * 1024 * 1024
                    }
                    if let colimaArch = colima.arch, !colimaArch.isEmpty {
                        arch = colimaArch
                    }
                    if let colimaRuntime = colima.runtime, !colimaRuntime.isEmpty {
                        runtime = colimaRuntime
                    }
                    if let colimaMountType = colima.mountType, !colimaMountType.isEmpty {
                        mountType = colimaMountType
                    }
                }
            }
#endif

            if runtime == nil {
                switch backend {
                case .unavailable:
                    runtime = nil
                default:
                    runtime = "docker"
                }
            }

            if memMax == nil { memMax = memAllocated }

            let value = DockerSocketInfo(
                vmEngine: vmEngine,
                memoryMaxBytes: memMax,
                memoryAllocatedBytes: memAllocated,
                arch: arch,
                runtime: runtime,
                mountType: mountType,
                operatingSystem: info?.OperatingSystem,
                serverVersion: version?.Version
            )

            await MainActor.run { socketInfo = value }
        } catch {
            await MainActor.run {
                socketInfo = nil
                setError(error)
            }
        }
    }

    private static func defaultVMEngineLabel(backend: DockerBackend, operatingSystem: String?, socketPath: String?) -> String {
        switch backend {
        case .colima:
            return "Colima"
        case .docker:
            if (operatingSystem ?? "").localizedCaseInsensitiveContains("Docker Desktop") { return "Docker Desktop" }
            return "Docker Engine"
        case .custom:
            if (operatingSystem ?? "").localizedCaseInsensitiveContains("Docker Desktop") { return "Docker Desktop" }
            return "Custom socket"
        case .unavailable:
            return "—"
        }
    }

    private struct DockerInfoAPI: Decodable {
        let MemTotal: Int64?
        let OperatingSystem: String?
        let KernelVersion: String?
        let Architecture: String?
    }

    private struct DockerVersionAPI: Decodable {
        let Version: String?
    }

#if os(macOS)
    private struct ColimaStatusAPI: Decodable {
        let vmType: String?
        let memory: Int?
        let arch: String?
        let runtime: String?
        let mountType: String?
    }

    private func fetchColimaStatus() async throws -> ColimaStatusAPI {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["colima", "status", "--json"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let decoder = JSONDecoder()
            return try decoder.decode(ColimaStatusAPI.self, from: data)
        }.value
    }
#endif

    public func fetchContainerDetails(id: String) async throws -> DockerContainerDetails {
        guard await ensureBackendOrFail() else {
            throw NSError(domain: "DockerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend non disponibile"])
        }

        let (data, status) = try await httpRequestViaUnixSocket(method: "GET", endpoint: "/containers/\(id)/json")
        if status >= 400 {
            let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
            throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DockerContainerInspectAPI.self, from: data)

        let name = decodeContainerName(decoded.Name)
        let image = decoded.Config?.Image ?? ""
        let createdAt = decoded.Created ?? ""
        let state = decoded.State?.Status ?? ""
        let workingDir = decoded.Config?.WorkingDir ?? ""
        let command = ([decoded.Path].compactMap { $0 } + (decoded.Args ?? [])).joined(separator: " ")

        let env = parseEnv(decoded.Config?.Env)

        let networks = (decoded.NetworkSettings?.Networks ?? [:]).map { name, net in
            DockerContainerDetails.NetworkAttachment(
                name: name,
                ipAddress: net.IPAddress ?? "",
                macAddress: net.MacAddress ?? "",
                gateway: net.Gateway ?? ""
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let mounts: [DockerContainerDetails.Mount] = (decoded.Mounts ?? []).map { mount in
            DockerContainerDetails.Mount(
                type: mount.type ?? "",
                name: mount.name ?? "",
                source: mount.source ?? "",
                destination: mount.destination ?? "",
                readOnly: !(mount.rw ?? true)
            )
        }
        .sorted { $0.destination.localizedCaseInsensitiveCompare($1.destination) == .orderedAscending }

        return DockerContainerDetails(
            id: decoded.Id,
            name: name.isEmpty ? decoded.Id : name,
            image: image,
            createdAt: createdAt,
            state: state,
            status: state,
            workingDir: workingDir,
            command: command,
            env: env,
            networks: networks,
            mounts: mounts
        )
    }

    public func fetchContainerLogs(id: String, tail: Int = 500) async throws -> String {
        guard await ensureBackendOrFail() else {
            throw NSError(domain: "DockerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend non disponibile"])
        }

        let endpoint = "/containers/\(id)/logs?stdout=true&stderr=true&timestamps=true&tail=\(tail)"
        let (data, status) = try await httpRequestViaUnixSocket(method: "GET", endpoint: endpoint)
        if status >= 400 {
            let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
            throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return decodeDockerLogStreamIfNeeded(data)
    }

    /// Fetch reale containers via Docker Engine API.
    public func fetchContainers() async {
        guard await ensureBackendOrFail() else { return }

        do {
            self.errorMessage = nil
            let (data, status) = try await httpRequestViaUnixSocket(method: "GET", endpoint: "/containers/json?all=true")
            if status >= 400 {
                let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
            }

            let decoded = try JSONDecoder().decode([DockerContainerAPI].self, from: data)
            self.containers = decoded.map { api in
                let rawName = api.Names?.first ?? api.Id
                let cleanedName = rawName.hasPrefix("/") ? String(rawName.dropFirst()) : rawName
                let ports: [DockerContainer.Port] = (api.Ports ?? []).compactMap { port in
                    guard let privatePort = port.privatePort else { return nil }
                    return DockerContainer.Port(
                        ip: port.ip,
                        privatePort: privatePort,
                        publicPort: port.publicPort,
                        type: port.type ?? ""
                    )
                }
                return DockerContainer(
                    id: api.Id,
                    name: cleanedName,
                    image: api.Image,
                    state: api.State ?? "",
                    status: api.Status ?? "",
                    createdAt: api.Created.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    ports: ports,
                    labels: api.Labels ?? [:]
                )
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
            self.containers = []
        }
    }

    /// Placeholder per fetch volumi (da implementare con socket HTTP)
    public func fetchVolumes() async {
        // Implementazione reale via Docker Engine API
        guard await ensureBackendOrFail() else { return }

        do {
            self.errorMessage = nil
            let (data, status) = try await httpRequestViaUnixSocket(method: "GET", endpoint: "/volumes")
            if status >= 400 {
                let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
            }

            let decoder = JSONDecoder()
            let response = try decoder.decode(DockerVolumesResponse.self, from: data)
            let items = response.Volumes ?? []

            let mapped: [DockerVolume] = items.map { item in
                DockerVolume(
                    id: item.Name, // usiamo il nome come id stabile
                    name: item.Name,
                    driver: item.Driver,
                    mountpoint: item.Mountpoint,
                    createdAt: item.CreatedAt ?? "",
                    refCount: item.UsageData?.RefCount,
                    sizeBytes: item.UsageData?.Size
                )
            }

            self.volumes = mapped
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
            self.volumes = []
        }
    }

    public func fetchImages() async {
        guard await ensureBackendOrFail() else { return }

        do {
            self.errorMessage = nil
            let (data, status) = try await httpRequestViaUnixSocket(method: "GET", endpoint: "/images/json")
            if status >= 400 {
                let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
            }

            let decoded = try JSONDecoder().decode([DockerImageAPI].self, from: data)
            self.images = decoded.map { api in
                let date: Date?
                if let created = api.Created {
                    date = Date(timeIntervalSince1970: TimeInterval(created))
                } else {
                    date = nil
                }
                return DockerImage(
                    id: api.Id,
                    tags: (api.RepoTags ?? []).filter { $0 != "<none>:<none>" },
                    sizeBytes: api.Size ?? 0,
                    createdAt: date
                )
            }.sorted { ($0.tags.first ?? $0.id).localizedCaseInsensitiveCompare(($1.tags.first ?? $1.id)) == .orderedAscending }
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
            self.images = []
        }
    }

    public func fetchNetworks() async {
        guard await ensureBackendOrFail() else { return }

        do {
            self.errorMessage = nil
            let (data, status) = try await httpRequestViaUnixSocket(method: "GET", endpoint: "/networks")
            if status >= 400 {
                let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
            }

            let decoded = try JSONDecoder().decode([DockerNetworkAPI].self, from: data)
            self.networks = decoded.map { api in
                DockerNetwork(
                    id: api.Id,
                    name: api.Name,
                    driver: api.Driver,
                    scope: api.Scope ?? "",
                    createdAt: DockerDateParser.parse(api.Created),
                    containerCount: api.Containers?.count
                )
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
            self.networks = []
        }
    }

    public func pruneVolumes() async {
        guard await ensureBackendOrFail() else { return }

        do {
            self.errorMessage = nil
            let (_, status) = try await httpRequestViaUnixSocket(method: "POST", endpoint: "/volumes/prune")
            if status >= 400 {
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: "Errore Docker (\(status))"])
            }
            await fetchVolumes()
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
        }
    }

    // MARK: - Actions

    public func startContainer(id: String) async { await containerAction(id: id, action: "start") }
    public func stopContainer(id: String) async { await containerAction(id: id, action: "stop") }
    public func restartContainer(id: String) async { await containerAction(id: id, action: "restart") }
    public func killContainer(id: String) async { await containerAction(id: id, action: "kill") }

    public func killAllRunningContainers() async {
        guard await ensureBackendOrFail() else { return }
        let running = containers.filter(\.isRunning)
        guard !running.isEmpty else { return }

        do {
            self.errorMessage = nil
            for container in running {
                let (_, status) = try await httpRequestViaUnixSocket(method: "POST", endpoint: "/containers/\(container.id)/kill")
                if status >= 400 {
                    throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: "Errore Docker (\(status)) durante kill"])
                }
            }
            await fetchContainers()
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
        }
    }

    private func containerAction(id: String, action: String) async {
        guard await ensureBackendOrFail() else { return }
        do {
            self.errorMessage = nil
            let (_, status) = try await httpRequestViaUnixSocket(method: "POST", endpoint: "/containers/\(id)/\(action)")
            if status >= 400 {
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: "Errore Docker (\(status)) durante \(action)"])
            }
            await fetchContainers()
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
        }
    }

    public func removeContainer(id: String, force: Bool = true) async {
        guard await ensureBackendOrFail() else { return }
        do {
            self.errorMessage = nil
            let (data, status) = try await httpRequestViaUnixSocket(method: "DELETE", endpoint: "/containers/\(id)?force=\(force ? "true" : "false")")
            if status >= 400 {
                let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            await fetchContainers()
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
        }
    }

    public func removeImage(id: String, force: Bool = false) async {
        guard await ensureBackendOrFail() else { return }
        do {
            self.errorMessage = nil
            let (data, status) = try await httpRequestViaUnixSocket(method: "DELETE", endpoint: "/images/\(id)?force=\(force ? "true" : "false")")
            if status >= 400 {
                let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            await fetchImages()
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
        }
    }

    public func removeVolume(name: String) async {
        guard await ensureBackendOrFail() else { return }
        do {
            self.errorMessage = nil
            let (data, status) = try await httpRequestViaUnixSocket(method: "DELETE", endpoint: "/volumes/\(name)")
            if status >= 400 {
                let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            await fetchVolumes()
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
        }
    }

    public func removeNetwork(id: String) async {
        guard await ensureBackendOrFail() else { return }
        do {
            self.errorMessage = nil
            let (data, status) = try await httpRequestViaUnixSocket(method: "DELETE", endpoint: "/networks/\(id)")
            if status >= 400 {
                let msg = decodeDockerErrorMessage(from: data) ?? "Errore Docker (\(status))"
                throw NSError(domain: "DockerService", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            await fetchNetworks()
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
        }
    }

#if os(macOS)
    @MainActor
    public func openContainerShellInTerminal(id: String) async {
        await resolveBackend()
        guard let socket = resolvedSocketPath else {
            setErrorMessage("Socket Docker non disponibile")
            return
        }

        let dockerHost = "unix://\(socket)"
        let safeID = id.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard !safeID.isEmpty else {
            setErrorMessage("ID container non valido")
            return
        }

        let script = """
        #!/bin/zsh
        export DOCKER_HOST="\(dockerHost)"
        export TERM="xterm-256color"

        if ! command -v docker >/dev/null 2>&1; then
          echo "docker CLI not found in PATH"
          echo "Install Docker Desktop or docker CLI, then retry."
          echo
          read -r -n 1 -s -p "Press any key to close..."
          echo
          exit 1
        fi

        docker exec -it \(safeID) /bin/bash || docker exec -it \(safeID) /bin/sh || docker exec -it \(safeID) sh
        """

        openTerminalScript(name: "shell-\(safeID.prefix(12))", script: script)
    }

    @MainActor
    public func openContainerAttachInTerminal(id: String) async {
        await resolveBackend()
        guard let socket = resolvedSocketPath else {
            setErrorMessage("Socket Docker non disponibile")
            return
        }

        let dockerHost = "unix://\(socket)"
        let safeID = id.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard !safeID.isEmpty else {
            setErrorMessage("ID container non valido")
            return
        }

        let script = """
        #!/bin/zsh
        export DOCKER_HOST="\(dockerHost)"
        export TERM="xterm-256color"

        if ! command -v docker >/dev/null 2>&1; then
          echo "docker CLI not found in PATH"
          echo "Install Docker Desktop or docker CLI, then retry."
          echo
          read -r -n 1 -s -p "Press any key to close..."
          echo
          exit 1
        fi

        echo "Attaching to container: \(safeID)"
        echo "Detach with: Ctrl-p Ctrl-q"
        echo
        docker attach \(safeID)
        """

        openTerminalScript(name: "attach-\(safeID.prefix(12))", script: script)
    }

    @MainActor
    private func openTerminalScript(name: String, script: String) {
        do {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let fileURL = tempDir.appendingPathComponent("dockscan-\(name).command")
            try script.write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fileURL.path)
            NSWorkspace.shared.open(fileURL)
        } catch {
            setErrorMessage("Apri terminale fallito: \((error as NSError).localizedDescription)")
        }
    }
#endif
}
