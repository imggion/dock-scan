import Foundation

struct DockerStackGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let kindLabel: String?
    let containers: [DockerContainer]

    var runningCount: Int { containers.filter(\.isRunning).count }
    var errorCount: Int { containers.filter(\.isError).count }
}

extension Collection where Element == DockerContainer {
    func groupedByStack() -> [DockerStackGroup] {
        let grouped = Dictionary(
            grouping: self.compactMap { container -> (String, DockerContainer)? in
                guard let stack = container.stackName, !stack.isEmpty else { return nil }
                return (stack, container)
            },
            by: { $0.0 }
        )

        return grouped
            .map { (stackName, pairs) in
                let containers = pairs.map(\.1).sorted { lhs, rhs in
                    let l = lhs.stackServiceName ?? lhs.name
                    let r = rhs.stackServiceName ?? rhs.name
                    let cmp = l.localizedCaseInsensitiveCompare(r)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                let kind = containers.first?.stackKindLabel
                return DockerStackGroup(id: stackName, name: stackName, kindLabel: kind, containers: containers)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

