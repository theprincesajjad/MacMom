import Foundation

public struct AlertPolicy: Equatable {
    public var highCPUPercent: Double
    public var sustainedHighCPUCount: Int
    public var memoryClimbBytes: UInt64
    public var sustainedMemoryCount: Int
    public var heavyDiskBytes: UInt64
    public var heavyNetworkBytes: UInt64

    public init(
        highCPUPercent: Double,
        sustainedHighCPUCount: Int,
        memoryClimbBytes: UInt64,
        sustainedMemoryCount: Int,
        heavyDiskBytes: UInt64,
        heavyNetworkBytes: UInt64
    ) {
        self.highCPUPercent = highCPUPercent
        self.sustainedHighCPUCount = sustainedHighCPUCount
        self.memoryClimbBytes = memoryClimbBytes
        self.sustainedMemoryCount = sustainedMemoryCount
        self.heavyDiskBytes = heavyDiskBytes
        self.heavyNetworkBytes = heavyNetworkBytes
    }

    public static let standard = AlertPolicy(
        highCPUPercent: 80,
        sustainedHighCPUCount: 3,
        memoryClimbBytes: 256 * 1024 * 1024,
        sustainedMemoryCount: 3,
        heavyDiskBytes: 64 * 1024 * 1024,
        heavyNetworkBytes: 64 * 1024 * 1024
    )
}

public enum UsageAlert: Equatable {
    case sustainedHighCPU(appID: String, appName: String)
    case sustainedMemoryClimb(appID: String, appName: String)
    case heavyDisk(appID: String, appName: String)
    case heavyNetwork(appID: String, appName: String)

    public var appID: String {
        switch self {
        case .sustainedHighCPU(let appID, _),
             .sustainedMemoryClimb(let appID, _),
             .heavyDisk(let appID, _),
             .heavyNetwork(let appID, _):
            return appID
        }
    }

    public var appName: String {
        switch self {
        case .sustainedHighCPU(_, let appName),
             .sustainedMemoryClimb(_, let appName),
             .heavyDisk(_, let appName),
             .heavyNetwork(_, let appName):
            return appName
        }
    }

    public var message: String {
        switch self {
        case .sustainedHighCPU(_, let appName):
            return "\(appName) is using high CPU"
        case .sustainedMemoryClimb(_, let appName):
            return "\(appName) memory is climbing"
        case .heavyDisk(_, let appName):
            return "\(appName) is using the disk heavily"
        case .heavyNetwork(_, let appName):
            return "\(appName) is using the network heavily"
        }
    }
}

public enum AlertRules {
    /// Local decision only. A quiet series produces an empty list.
    public static func evaluate(series: [UsageSample], policy: AlertPolicy) -> [UsageAlert] {
        let grouped = Dictionary(grouping: series, by: \.appID)
        var alerts: [UsageAlert] = []
        for appID in grouped.keys.sorted() {
            guard let samples = grouped[appID], !samples.isEmpty else { continue }
            let ordered = samples.sorted { lhs, rhs in
                if lhs.at != rhs.at { return lhs.at < rhs.at }
                return lhs.appName < rhs.appName
            }
            let name = ordered.last?.appName ?? appID
            if sustainedHighCPU(ordered, policy: policy) {
                alerts.append(.sustainedHighCPU(appID: appID, appName: name))
            }
            if sustainedMemoryClimb(ordered, policy: policy) {
                alerts.append(.sustainedMemoryClimb(appID: appID, appName: name))
            }
            if ordered.contains(where: { $0.disk >= policy.heavyDiskBytes }) {
                alerts.append(.heavyDisk(appID: appID, appName: name))
            }
            if ordered.contains(where: { $0.network >= policy.heavyNetworkBytes }) {
                alerts.append(.heavyNetwork(appID: appID, appName: name))
            }
        }
        return alerts
    }

    private static func sustainedHighCPU(_ samples: [UsageSample], policy: AlertPolicy) -> Bool {
        let need = max(policy.sustainedHighCPUCount, 1)
        var run = 0
        for sample in samples {
            if sample.cpu >= policy.highCPUPercent {
                run += 1
                if run >= need { return true }
            } else {
                run = 0
            }
        }
        return false
    }

    private static func sustainedMemoryClimb(_ samples: [UsageSample], policy: AlertPolicy) -> Bool {
        let need = max(policy.sustainedMemoryCount, 2)
        guard samples.count >= need else { return false }
        for start in 0...(samples.count - need) {
            let end = start + need
            var strictlyRising = true
            for index in (start + 1)..<end where samples[index].memory <= samples[index - 1].memory {
                strictlyRising = false
                break
            }
            if !strictlyRising { continue }
            let climb = samples[end - 1].memory - samples[start].memory
            if climb >= policy.memoryClimbBytes {
                return true
            }
        }
        return false
    }
}

public struct AlertRing {
    public var limit: Int
    private var samples: [String: [UsageSample]] = [:]

    public init(limit: Int = 12) {
        self.limit = limit
    }

    public mutating func add(from snapshot: SystemSnapshot) {
        let seen = Set(snapshot.apps.map(\.id))
        for app in snapshot.apps {
            var list = samples[app.id] ?? []
            list.append(UsageSample(
                at: snapshot.sampledAt,
                appID: app.id,
                appName: app.name,
                cpu: app.cpuPercent,
                memory: app.memoryBytes,
                disk: app.diskBytes,
                network: app.networkBytes,
                energy: app.energy
            ))
            if limit > 0, list.count > limit {
                list.removeFirst(list.count - limit)
            }
            samples[app.id] = list
        }
        for key in samples.keys where !seen.contains(key) {
            samples[key] = nil
        }
    }

    public func series() -> [UsageSample] {
        samples.values.flatMap { $0 }
    }
}
