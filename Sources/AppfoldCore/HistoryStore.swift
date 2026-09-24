import Foundation

public enum HistoryRetention {
    public static let seconds: TimeInterval = 30 * 24 * 60 * 60
}

public enum HistoryRange: String, CaseIterable, Equatable {
    case last12Hours
    case last24Hours
    case last7Days
    case last30Days

    public var seconds: TimeInterval {
        switch self {
        case .last12Hours: return 12 * 60 * 60
        case .last24Hours: return 24 * 60 * 60
        case .last7Days: return 7 * 24 * 60 * 60
        case .last30Days: return HistoryRetention.seconds
        }
    }

    public var title: String {
        switch self {
        case .last12Hours: return "12h"
        case .last24Hours: return "24h"
        case .last7Days: return "7d"
        case .last30Days: return "30d"
        }
    }

    public func cutoff(now: Date) -> Date {
        now.addingTimeInterval(-seconds)
    }
}

public enum UsageMetric: String, Equatable {
    case cpu
    case memory
    case disk
    case network
}

public struct UsageSample: Codable, Equatable {
    public var at: Date
    public var appID: String
    public var appName: String
    public var cpu: Double
    public var memory: UInt64
    public var disk: UInt64
    public var network: UInt64
    public var energy: UInt64

    public init(
        at: Date,
        appID: String,
        appName: String,
        cpu: Double,
        memory: UInt64,
        disk: UInt64,
        network: UInt64,
        energy: UInt64
    ) {
        self.at = at
        self.appID = appID
        self.appName = appName
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.energy = energy
    }
}

public struct AppUsageRank: Equatable {
    public var appID: String
    public var appName: String
    public var cpu: Double
    public var memory: UInt64
    public var disk: UInt64
    public var network: UInt64
    public var energy: UInt64

    public init(appID: String, appName: String, cpu: Double, memory: UInt64, disk: UInt64, network: UInt64, energy: UInt64) {
        self.appID = appID
        self.appName = appName
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.energy = energy
    }
}

/// Local usage history. Nothing here leaves the Mac.
public final class HistoryStore {
    public let fileURL: URL
    private let clock: () -> Date
    private var stored: [UsageSample] = []
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, clock: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.clock = clock
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
        let parent = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        load()
    }

    public func record(_ samples: [UsageSample]) {
        stored.append(contentsOf: samples)
        prune()
        rewrite()
    }

    public func storedSamples() -> [UsageSample] {
        stored
    }

    public func topApps(in range: HistoryRange, metric: UsageMetric = .cpu, limit: Int = 10) -> [AppUsageRank] {
        let now = clock()
        let cutoff = range.cutoff(now: now)
        var totals: [String: AppUsageRank] = [:]
        for sample in stored where sample.at >= cutoff && sample.at <= now {
            var rank = totals[sample.appID] ?? AppUsageRank(
                appID: sample.appID,
                appName: sample.appName,
                cpu: 0,
                memory: 0,
                disk: 0,
                network: 0,
                energy: 0
            )
            rank.appName = sample.appName
            rank.cpu += sample.cpu
            rank.memory += sample.memory
            rank.disk += sample.disk
            rank.network += sample.network
            rank.energy += sample.energy
            totals[sample.appID] = rank
        }

        let sorted = totals.values.sorted { lhs, rhs in
            switch metric {
            case .cpu:
                if lhs.cpu != rhs.cpu { return lhs.cpu > rhs.cpu }
            case .memory:
                if lhs.memory != rhs.memory { return lhs.memory > rhs.memory }
            case .disk:
                if lhs.disk != rhs.disk { return lhs.disk > rhs.disk }
            case .network:
                if lhs.network != rhs.network { return lhs.network > rhs.network }
            }
            if lhs.appName != rhs.appName { return lhs.appName < rhs.appName }
            return lhs.appID < rhs.appID
        }
        if limit <= 0 { return [] }
        return Array(sorted.prefix(limit))
    }

    private func isExpired(_ sample: UsageSample, now: Date) -> Bool {
        sample.at < now.addingTimeInterval(-HistoryRetention.seconds)
    }

    private func prune() {
        let now = clock()
        stored.removeAll { isExpired($0, now: now) }
        stored.sort { lhs, rhs in
            if lhs.at != rhs.at { return lhs.at < rhs.at }
            return lhs.appID < rhs.appID
        }
    }

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            stored = []
            return
        }
        stored = text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? decoder.decode(UsageSample.self, from: data)
        }
        let before = stored.count
        prune()
        if stored.count != before {
            rewrite()
        }
    }

    private func rewrite() {
        var lines: [String] = []
        lines.reserveCapacity(stored.count)
        for sample in stored {
            guard let data = try? encoder.encode(sample), let line = String(data: data, encoding: .utf8) else {
                continue
            }
            lines.append(line)
        }
        let body = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? body.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }
}

/// Writes at most one history sample per app per hour so a month of history stays small.
public struct HistoryWriter {
    public var bucketSeconds: TimeInterval
    private var writtenBucket: [String: Int] = [:]

    public init(bucketSeconds: TimeInterval = 3600) {
        self.bucketSeconds = bucketSeconds
    }

    public mutating func write(snapshot: SystemSnapshot, store: HistoryStore) {
        guard bucketSeconds > 0 else { return }
        let bucket = Int(snapshot.sampledAt.timeIntervalSince1970 / bucketSeconds)
        let seen = Set(snapshot.apps.map(\.id))
        for key in writtenBucket.keys where !seen.contains(key) {
            writtenBucket[key] = nil
        }
        var batch: [UsageSample] = []
        for app in snapshot.apps {
            if writtenBucket[app.id] == bucket { continue }
            writtenBucket[app.id] = bucket
            batch.append(UsageSample(
                at: snapshot.sampledAt,
                appID: app.id,
                appName: app.name,
                cpu: app.cpuPercent,
                memory: app.memoryBytes,
                disk: app.diskBytes,
                network: app.networkBytes,
                energy: app.energy
            ))
        }
        if !batch.isEmpty {
            store.record(batch)
        }
    }
}
