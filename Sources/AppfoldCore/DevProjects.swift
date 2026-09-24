import CLibProc
import Foundation

@_silgen_name("appfold_process_cwd")
private func appfold_process_cwd(
    _ pid: Int32,
    _ buffer: UnsafeMutablePointer<CChar>,
    _ length: Int32
) -> Int32

@_silgen_name("appfold_listening_ports")
private func appfold_listening_ports(
    _ pid: Int32,
    _ ports: UnsafeMutablePointer<Int32>,
    _ capacity: Int32
) -> Int32

public struct DevProcess: Equatable {
    public var pid: Int32
    public var name: String
    public var cwd: String
    public var ports: [Int]
    public var memoryBytes: UInt64
    public var cpuPercent: Double
    public var startedAt: Date?

    public init(
        pid: Int32,
        name: String,
        cwd: String,
        ports: [Int],
        memoryBytes: UInt64,
        cpuPercent: Double,
        startedAt: Date?
    ) {
        self.pid = pid
        self.name = name
        self.cwd = cwd
        self.ports = ports
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.startedAt = startedAt
    }
}

public struct ProjectGroup: Equatable {
    public var name: String
    public var directory: String
    public var runtime: String
    public var pids: [Int32]
    public var ports: [Int]
    public var memoryBytes: UInt64
    public var cpuPercent: Double
    public var oldestStart: Date?

    public init(
        name: String,
        directory: String,
        runtime: String,
        pids: [Int32],
        ports: [Int],
        memoryBytes: UInt64,
        cpuPercent: Double,
        oldestStart: Date?
    ) {
        self.name = name
        self.directory = directory
        self.runtime = runtime
        self.pids = pids
        self.ports = ports
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.oldestStart = oldestStart
    }
}

public enum DevProjects {
    /// Pure. Drops processes that are not dev servers. Groups the rest by project directory.
    public static func group(_ processes: [DevProcess]) -> [ProjectGroup] {
        var buckets: [String: [DevProcess]] = [:]
        var names: [String: String] = [:]
        var seen = Set<Int32>()

        for process in processes where seen.insert(process.pid).inserted {
            guard isDevServer(process) else { continue }
            guard let anchor = projectAnchor(cwd: process.cwd, hasListeningPort: hasListeningPort(process)) else {
                continue
            }
            buckets[anchor.directory, default: []].append(process)
            names[anchor.directory] = anchor.name
        }

        var groups: [ProjectGroup] = []
        groups.reserveCapacity(buckets.count)
        for (directory, members) in buckets {
            let starts = members.compactMap(\.startedAt)
            groups.append(ProjectGroup(
                name: names[directory] ?? lastComponent(directory),
                directory: directory,
                runtime: runtimeLabel(for: members),
                pids: members.map(\.pid).sorted(),
                ports: uniquePorts(in: members),
                memoryBytes: members.reduce(0) { $0 + $1.memoryBytes },
                cpuPercent: members.reduce(0) { $0 + $1.cpuPercent },
                oldestStart: starts.min()
            ))
        }

        groups.sort { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.directory < rhs.directory
        }
        return groups
    }

    /// Live scan. Callers must not run this on the hidden 5-second menu-bar timer.
    public static func scan(
        processes: [(pid: Int32, name: String, memoryBytes: UInt64, cpuPercent: Double, startedAt: Date?)]
    ) -> [ProjectGroup] {
        var rows: [DevProcess] = []
        rows.reserveCapacity(processes.count)
        var seen = Set<Int32>()
        for process in processes where process.pid > 0 && seen.insert(process.pid).inserted {
            guard shouldProbe(name: process.name) else { continue }
            rows.append(DevProcess(
                pid: process.pid,
                name: process.name,
                cwd: currentDirectory(pid: process.pid),
                ports: listeningPorts(pid: process.pid),
                memoryBytes: process.memoryBytes,
                cpuPercent: process.cpuPercent,
                startedAt: process.startedAt
            ))
        }
        return group(rows)
    }

    private static let devServerNames: Set<String> = [
        "node", "nodejs", "python", "python3", "ruby", "php", "java", "go", "bun", "deno", "cargo"
    ]

    private static let markers = [
        "package.json", "go.mod", "pyproject.toml", "Cargo.toml", "Gemfile", ".git"
    ]

    /// cwd counts as the first of six directories.
    private static let maxDirectoryWalk = 6

    private static func isDevServer(_ process: DevProcess) -> Bool {
        isDevServerName(process.name) || hasListeningPort(process)
    }

    private static func isDevServerName(_ name: String) -> Bool {
        devServerNames.contains(name.lowercased())
    }

    private static func hasListeningPort(_ process: DevProcess) -> Bool {
        process.ports.contains { $0 > 0 && $0 <= 65535 }
    }

    /// Dev runtimes, plus names containing "python" or "node". Other pids are not probed.
    private static func shouldProbe(name: String) -> Bool {
        let lower = name.lowercased()
        if devServerNames.contains(lower) { return true }
        return lower.contains("python") || lower.contains("node")
    }

    private static func projectAnchor(cwd raw: String, hasListeningPort: Bool) -> (name: String, directory: String)? {
        let cwd = normalize(raw)
        guard !cwd.isEmpty else { return nil }

        var current = cwd
        for _ in 0..<maxDirectoryWalk {
            if directoryHasMarker(current) {
                let name = lastComponent(current)
                if !name.isEmpty {
                    return (name, current)
                }
            }
            let parent = parentPath(current)
            if parent == current { break }
            current = parent
        }

        guard hasListeningPort else { return nil }
        let name = lastComponent(cwd)
        guard !name.isEmpty else { return nil }
        return (name, cwd)
    }

    private static func directoryHasMarker(_ directory: String) -> Bool {
        let fileManager = FileManager.default
        for marker in markers {
            let path = directory == "/" ? "/\(marker)" : "\(directory)/\(marker)"
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }

    private static func uniquePorts(in members: [DevProcess]) -> [Int] {
        var ports = Set<Int>()
        for member in members {
            for port in member.ports where port > 0 && port <= 65535 {
                ports.insert(port)
            }
        }
        return ports.sorted()
    }

    private static func runtimeLabel(for members: [DevProcess]) -> String {
        let labels = Set(members.map { runtimeLabel(forName: $0.name) }.filter { !$0.isEmpty })
        return labels.sorted().joined(separator: "+")
    }

    private static func runtimeLabel(forName name: String) -> String {
        switch name.lowercased() {
        case "node", "nodejs":
            return "node"
        case "python", "python3":
            return "python"
        case "ruby", "php", "java", "go", "bun", "deno", "cargo":
            return name.lowercased()
        default:
            return name.lowercased()
        }
    }

    private static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        if path == "/" { return "/" }
        var path = path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func parentPath(_ path: String) -> String {
        guard path != "/" else { return "/" }
        guard let slash = path.lastIndex(of: "/") else { return "/" }
        if slash == path.startIndex { return "/" }
        return String(path[..<slash])
    }

    private static func lastComponent(_ path: String) -> String {
        guard path != "/" else { return "" }
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    private static func currentDirectory(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        let wrote = buffer.withUnsafeMutableBufferPointer { raw -> Int32 in
            guard let base = raw.baseAddress else { return 0 }
            return appfold_process_cwd(pid, base, Int32(raw.count))
        }
        guard wrote > 0 else { return "" }
        let count = min(Int(wrote), buffer.count)
        let bytes = buffer.prefix(count).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func listeningPorts(pid: Int32) -> [Int] {
        var ports = [Int32](repeating: 0, count: 64)
        let wrote = ports.withUnsafeMutableBufferPointer { raw -> Int32 in
            guard let base = raw.baseAddress else { return 0 }
            return appfold_listening_ports(pid, base, Int32(raw.count))
        }
        guard wrote > 0 else { return [] }
        let limit = min(Int(wrote), ports.count)
        var unique = Set<Int>()
        for index in 0..<limit {
            let port = Int(ports[index])
            if port > 0 && port <= 65535 {
                unique.insert(port)
            }
        }
        return unique.sorted()
    }
}
