import Foundation

/// Host memory categories from one `vm_statistics64` read.
/// App is internal pages. A sum of process footprints is never substituted for it.
public struct HostMemoryParts: Equatable {
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var cachedBytes: UInt64
    public var freeBytes: UInt64
    public var swapBytes: UInt64
    public var totalBytes: UInt64

    public var inUseBytes: UInt64 {
        appBytes &+ wiredBytes &+ compressedBytes
    }
}

public enum HostMemory {
    public static func breakdown(
        internalBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        externalBytes: UInt64,
        freeBytes: UInt64,
        swapBytes: UInt64,
        totalBytes: UInt64,
        processFootprintSum: UInt64
    ) -> HostMemoryParts {
        _ = processFootprintSum
        let app = totalBytes > 0 ? min(internalBytes, totalBytes) : internalBytes
        return HostMemoryParts(
            appBytes: app,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedBytes: externalBytes,
            freeBytes: freeBytes,
            swapBytes: swapBytes,
            totalBytes: totalBytes
        )
    }
}

/// Chart ceiling. Percent series use 100, memory-used uses 1 (a fraction of RAM).
/// Nil keeps the old peak scale for rates that have no natural top.
public enum ChartCeiling {
    public static func scale(samples: [Double], upper: Double?) -> Double {
        if let upper, upper.isFinite, upper > 0 {
            return upper
        }
        var peak = 0.0
        for sample in samples where sample.isFinite && sample > peak {
            peak = sample
        }
        return peak > 0 ? peak : 1
    }
}

/// Keeps the samples that were actually recorded. Does not repeat the newest one.
public enum SeriesWindow {
    public static func window(_ samples: [Double], limit: Int = 48) -> [Double] {
        guard limit > 0 else { return [] }
        if samples.count <= limit { return samples }
        return Array(samples.suffix(limit))
    }
}

public enum ProjectStatus: Equatable {
    case working
    case idle(minutes: Int)
    case uptime(seconds: TimeInterval)
    case quiet

    public static func resolve(cpuPercent: Double, idleMinutes: Int?, uptime: TimeInterval?) -> ProjectStatus {
        if cpuPercent >= 2 { return .working }
        if let idleMinutes, idleMinutes > 0 { return .idle(minutes: idleMinutes) }
        if let uptime, uptime.isFinite, uptime >= 0 { return .uptime(seconds: uptime) }
        return .quiet
    }
}
