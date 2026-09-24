import Foundation

/// How often the app may take a usage sample.
/// The menu-bar app uses this same type: closed windows wait `closedInterval`.
public struct SampleSchedule {
    public static let closedInterval: TimeInterval = 5
    public static let openInterval: TimeInterval = 1

    public var windowVisible: Bool
    private var lastSample: Date?

    public init(windowVisible: Bool, lastSample: Date? = nil) {
        self.windowVisible = windowVisible
        self.lastSample = lastSample
    }

    public var interval: TimeInterval {
        windowVisible ? Self.openInterval : Self.closedInterval
    }

    public mutating func shouldSample(at now: Date) -> Bool {
        if let lastSample, now.timeIntervalSince(lastSample) < interval {
            return false
        }
        lastSample = now
        return true
    }

    public mutating func markSampled(at now: Date) {
        lastSample = now
    }
}

public enum CPUDelta {
    /// Percent of one core from two CPU-time readings in nanoseconds.
    public static func percent(previousNS: UInt64?, currentNS: UInt64, elapsed: TimeInterval) -> Double {
        guard let previousNS, elapsed > 0, currentNS >= previousNS else { return 0 }
        let seconds = Double(currentNS - previousNS) / 1_000_000_000
        return seconds / elapsed * 100
    }
}

public struct HostCPUTicks: Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public var busy: UInt64 { user + system + nice }
    public var total: UInt64 { busy + idle }
}

public enum HostCPU {
    public static func percent(previous: HostCPUTicks?, current: HostCPUTicks) -> Double {
        guard let previous else { return 0 }
        let total = wrappedDelta(current.total, previous.total)
        let busy = wrappedDelta(current.busy, previous.busy)
        guard total > 0 else { return 0 }
        return Double(busy) / Double(total) * 100
    }

    /// Host tick counters are 32-bit and wrap after a long uptime.
    static func wrappedDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        if current >= previous { return current - previous }
        let mask: UInt64 = 1 << 32
        let current32 = current % mask
        let previous32 = previous % mask
        if current32 >= previous32 { return current32 - previous32 }
        return (mask - previous32) + current32
    }
}

public enum CounterDelta {
    public static func bytes(previous: UInt64?, current: UInt64) -> UInt64 {
        guard let previous, current >= previous else { return 0 }
        return current - previous
    }

    public static func perSecond(bytes: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        return Double(bytes) / elapsed
    }
}
