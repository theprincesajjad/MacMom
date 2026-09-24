import Foundation

public struct ProcessFact: Codable, Equatable {
    public var pid: Int32
    public var parentPID: Int32
    public var name: String
    public var executablePath: String
    public var bundlePath: String?
    public var memoryBytes: UInt64
    public var cpuPercent: Double
    public var energy: UInt64
    public var diskBytes: UInt64
    public var networkBytes: UInt64
    public var startedAt: Date?

    public init(
        pid: Int32,
        parentPID: Int32,
        name: String,
        executablePath: String,
        bundlePath: String?,
        memoryBytes: UInt64,
        cpuPercent: Double,
        energy: UInt64,
        diskBytes: UInt64,
        networkBytes: UInt64,
        startedAt: Date? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.executablePath = executablePath
        self.bundlePath = bundlePath
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.energy = energy
        self.diskBytes = diskBytes
        self.networkBytes = networkBytes
        self.startedAt = startedAt
    }
}

public struct AppRow: Codable, Equatable {
    public var id: String
    public var name: String
    public var bundlePath: String?
    public var members: [ProcessFact]
    public var memoryBytes: UInt64
    public var cpuPercent: Double
    public var energy: UInt64
    public var diskBytes: UInt64
    public var networkBytes: UInt64

    public init(
        id: String,
        name: String,
        bundlePath: String?,
        members: [ProcessFact],
        memoryBytes: UInt64,
        cpuPercent: Double,
        energy: UInt64,
        diskBytes: UInt64,
        networkBytes: UInt64
    ) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.members = members
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.energy = energy
        self.diskBytes = diskBytes
        self.networkBytes = networkBytes
    }
}

public struct SystemSnapshot: Codable, Equatable {
    public var sampledAt: Date
    public var systemCPUPercent: Double
    public var systemMemoryUsedBytes: UInt64
    public var systemMemoryTotalBytes: UInt64
    public var systemDiskBytesPerSecond: Double
    public var systemNetworkBytesPerSecond: Double
    public var apps: [AppRow]
    public var processCount: Int

    public init(
        sampledAt: Date,
        systemCPUPercent: Double,
        systemMemoryUsedBytes: UInt64,
        systemMemoryTotalBytes: UInt64,
        systemDiskBytesPerSecond: Double,
        systemNetworkBytesPerSecond: Double,
        apps: [AppRow],
        processCount: Int
    ) {
        self.sampledAt = sampledAt
        self.systemCPUPercent = systemCPUPercent
        self.systemMemoryUsedBytes = systemMemoryUsedBytes
        self.systemMemoryTotalBytes = systemMemoryTotalBytes
        self.systemDiskBytesPerSecond = systemDiskBytesPerSecond
        self.systemNetworkBytesPerSecond = systemNetworkBytesPerSecond
        self.apps = apps
        self.processCount = processCount
    }
}

public enum BundlePath {
    /// Outermost `Something.app` directory in an executable path.
    public static func outermostApp(in path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") && $0.count > 4 }) else {
            return nil
        }
        let joined = parts[...index].joined(separator: "/")
        return joined.isEmpty ? nil : joined
    }
}
