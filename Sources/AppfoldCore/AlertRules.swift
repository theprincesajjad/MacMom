import Foundation

public struct AlertPolicy: Equatable {
    public var highCPUPercent: Double
    public var sustainedHighCPUCount: Int
    public var memoryClimbBytes: UInt64
    public var sustainedMemoryCount: Int
    /// An app already this large can alert when it is still growing.
    public var heavyMemoryBytes: UInt64
    public var heavyDiskBytes: UInt64
    public var heavyNetworkBytes: UInt64

    public init(
        highCPUPercent: Double,
        sustainedHighCPUCount: Int,
        memoryClimbBytes: UInt64,
        sustainedMemoryCount: Int,
        heavyMemoryBytes: UInt64,
        heavyDiskBytes: UInt64,
        heavyNetworkBytes: UInt64
    ) {
        self.highCPUPercent = highCPUPercent
        self.sustainedHighCPUCount = sustainedHighCPUCount
        self.memoryClimbBytes = memoryClimbBytes
        self.sustainedMemoryCount = sustainedMemoryCount
        self.heavyMemoryBytes = heavyMemoryBytes
        self.heavyDiskBytes = heavyDiskBytes
        self.heavyNetworkBytes = heavyNetworkBytes
    }

    public static let standard = AlertPolicy(
        highCPUPercent: 80,
        sustainedHighCPUCount: 6,
        memoryClimbBytes: 1536 * 1024 * 1024,
        sustainedMemoryCount: 6,
        heavyMemoryBytes: 6 * 1024 * 1024 * 1024,
        heavyDiskBytes: 1024 * 1024 * 1024,
        heavyNetworkBytes: 1024 * 1024 * 1024
    )

    /// Same app and reason stays quiet this long, even if the reading dips and climbs again.
    public static let notificationCooldown: TimeInterval = 30 * 60
}

public enum UsageAlert: Equatable {
    case sustainedHighCPU(appID: String, appName: String)
    case sustainedMemoryClimb(appID: String, appName: String, usedBytes: UInt64, climbedBytes: UInt64)
    case heavyDisk(appID: String, appName: String)
    case heavyNetwork(appID: String, appName: String)

    public var appID: String {
        switch self {
        case .sustainedHighCPU(let appID, _),
             .sustainedMemoryClimb(let appID, _, _, _),
             .heavyDisk(let appID, _),
             .heavyNetwork(let appID, _):
            return appID
        }
    }

    public var appName: String {
        switch self {
        case .sustainedHighCPU(_, let appName),
             .sustainedMemoryClimb(_, let appName, _, _),
             .heavyDisk(_, let appName),
             .heavyNetwork(_, let appName):
            return appName
        }
    }

    public var message: String {
        switch self {
        case .sustainedHighCPU(_, let appName):
            return "\(appName) is using high CPU"
        case .sustainedMemoryClimb(_, let appName, let usedBytes, let climbedBytes):
            if climbedBytes > 0 {
                return "\(appName) climbed \(Self.memoryText(climbedBytes)) and is using \(Self.memoryText(usedBytes))"
            }
            return "\(appName) is using \(Self.memoryText(usedBytes))"
        case .heavyDisk(_, let appName):
            return "\(appName) is using the disk heavily"
        case .heavyNetwork(_, let appName):
            return "\(appName) is using the network heavily"
        }
    }

    static func memoryText(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", locale: Locale(identifier: "en_US_POSIX"), gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", locale: Locale(identifier: "en_US_POSIX"), mb)
    }

    /// Stable id for one app and one kind of alert. Used to post a notification once.
    public var noteID: String {
        switch self {
        case .sustainedHighCPU(let appID, _):
            return "cpu:\(appID)"
        case .sustainedMemoryClimb(let appID, _, _, _):
            return "memory:\(appID)"
        case .heavyDisk(let appID, _):
            return "disk:\(appID)"
        case .heavyNetwork(let appID, _):
            return "network:\(appID)"
        }
    }
}

public struct AlertNote: Equatable {
    public var id: String
    public var title: String
    public var body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

public enum AlertFeed {
    public static func ids(_ alerts: [UsageAlert]) -> Set<String> {
        Set(alerts.map(\.noteID))
    }

    /// Alerts that were not already announced. The same set posted again produces nothing.
    public static func fresh(previous: Set<String>, alerts: [UsageAlert]) -> [AlertNote] {
        alerts.compactMap { alert in
            guard !previous.contains(alert.noteID) else { return nil }
            return AlertNote(id: alert.noteID, title: "MacMom", body: alert.message)
        }
    }

    /// False when this app and reason was announced recently. Stops a dip-and-climb from notifying again.
    public static func shouldAnnounce(last: Date?, now: Date, cooldown: TimeInterval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= cooldown
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
            if let memory = sustainedMemoryClimb(ordered, policy: policy) {
                alerts.append(.sustainedMemoryClimb(
                    appID: appID,
                    appName: name,
                    usedBytes: memory.used,
                    climbedBytes: memory.climbed
                ))
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

    /// A large climb, or an already huge app that is still growing. A few megabytes of jitter does not qualify.
    private static func sustainedMemoryClimb(_ samples: [UsageSample], policy: AlertPolicy) -> (used: UInt64, climbed: UInt64)? {
        let need = max(policy.sustainedMemoryCount, 2)
        guard samples.count >= need else { return nil }
        let window = samples.suffix(need)
        guard let first = window.first, let last = window.last, last.memory >= first.memory else { return nil }
        let climbed = last.memory - first.memory
        let used = last.memory
        if climbed >= policy.memoryClimbBytes {
            return (used, climbed)
        }
        if used >= policy.heavyMemoryBytes, climbed >= policy.memoryClimbBytes / 2 {
            return (used, climbed)
        }
        return nil
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
