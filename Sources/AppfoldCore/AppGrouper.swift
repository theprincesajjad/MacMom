import Foundation

public enum AppGrouper {
    /// Fold processes into the app that owns them.
    ///
    /// A process belongs to the outermost `.app` that contains its executable.
    /// A process launched by that app, including a helper that lives outside the
    /// bundle, belongs to the same app. A different app bundle stays separate
    /// even when this app started it. A process with no app anywhere in its
    /// parent chain is kept as its own row.
    public static func group(_ processes: [ProcessFact]) -> [AppRow] {
        var unique: [ProcessFact] = []
        var seen = Set<Int32>()
        unique.reserveCapacity(processes.count)
        for process in processes where process.pid > 0 && seen.insert(process.pid).inserted {
            var copy = process
            copy.bundlePath = ownBundle(of: process)
            unique.append(copy)
        }

        let index = Dictionary(uniqueKeysWithValues: unique.map { ($0.pid, $0) })
        var memo: [Int32: String] = [:]
        var buckets: [String: [ProcessFact]] = [:]

        for process in unique {
            var stack = Set<Int32>()
            let owner = ownerID(of: process.pid, index: index, memo: &memo, stack: &stack)
            buckets[owner, default: []].append(process)
        }

        var rows: [AppRow] = []
        rows.reserveCapacity(buckets.count)
        for (id, members) in buckets {
            let ordered = members.sorted { $0.pid < $1.pid }
            let bundle = id.hasPrefix("bundle:") ? String(id.dropFirst("bundle:".count)) : nil
            let name = displayName(bundle: bundle, members: ordered)
            rows.append(AppRow(
                id: id,
                name: name,
                bundlePath: bundle,
                members: ordered,
                memoryBytes: ordered.reduce(0) { $0 + $1.memoryBytes },
                cpuPercent: ordered.reduce(0) { $0 + $1.cpuPercent },
                energy: ordered.reduce(0) { $0 + $1.energy },
                diskBytes: ordered.reduce(0) { $0 + $1.diskBytes },
                networkBytes: ordered.reduce(0) { $0 + $1.networkBytes }
            ))
        }

        rows.sort { lhs, rhs in
            if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id < rhs.id
        }
        return rows
    }

    private static func ownBundle(of process: ProcessFact) -> String? {
        if let bundle = process.bundlePath, !bundle.isEmpty {
            return bundle
        }
        return BundlePath.outermostApp(in: process.executablePath)
    }

    private static func displayName(bundle: String?, members: [ProcessFact]) -> String {
        if let bundle {
            let base = URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent
            if !base.isEmpty { return base }
        }
        if let member = members.first {
            return member.name.isEmpty ? "Process \(member.pid)" : member.name
        }
        return "Process"
    }

    private static func ownerID(
        of pid: Int32,
        index: [Int32: ProcessFact],
        memo: inout [Int32: String],
        stack: inout Set<Int32>
    ) -> String {
        if let cached = memo[pid] {
            return cached
        }
        guard let process = index[pid] else {
            return "pid:\(pid)"
        }
        if let bundle = process.bundlePath, !bundle.isEmpty {
            let id = "bundle:\(bundle)"
            memo[pid] = id
            return id
        }
        if stack.contains(pid) {
            return "pid:\(pid)"
        }
        stack.insert(pid)
        defer { stack.remove(pid) }

        if process.parentPID > 0, process.parentPID != pid, index[process.parentPID] != nil {
            let parentOwner = ownerID(of: process.parentPID, index: index, memo: &memo, stack: &stack)
            if parentOwner.hasPrefix("bundle:") {
                memo[pid] = parentOwner
                return parentOwner
            }
        }

        let id = "pid:\(pid)"
        memo[pid] = id
        return id
    }
}
