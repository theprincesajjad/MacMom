import CLibProc
import Foundation

public struct BatteryStatus: Equatable {
    public var hasBattery: Bool
    public var onACPower: Bool
    public var percent: Double?
    public var minutesRemaining: Int?
    public var cycleCount: Int?
    public var healthPercent: Double?
    public var watts: Double?
    public var temperatureC: Double?

    public init(
        hasBattery: Bool,
        onACPower: Bool,
        percent: Double?,
        minutesRemaining: Int?,
        cycleCount: Int?,
        healthPercent: Double?,
        watts: Double?,
        temperatureC: Double?
    ) {
        self.hasBattery = hasBattery
        self.onACPower = onACPower
        self.percent = percent
        self.minutesRemaining = minutesRemaining
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.watts = watts
        self.temperatureC = temperatureC
    }
}

public struct VolumeInfo: Equatable {
    public var name: String
    public var freeBytes: UInt64
    public var totalBytes: UInt64

    public init(name: String, freeBytes: UInt64, totalBytes: UInt64) {
        self.name = name
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }
}

public struct MemoryBreakdown: Equatable {
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var cachedBytes: UInt64
    public var freeBytes: UInt64
    public var swapBytes: UInt64
    public var totalBytes: UInt64

    public init(
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        cachedBytes: UInt64,
        freeBytes: UInt64,
        swapBytes: UInt64,
        totalBytes: UInt64
    ) {
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.freeBytes = freeBytes
        self.swapBytes = swapBytes
        self.totalBytes = totalBytes
    }
}

public struct InterfaceInfo: Equatable {
    public var bsdName: String
    public var kind: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64

    public init(bsdName: String, kind: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.bsdName = bsdName
        self.kind = kind
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

public struct GPUStatus: Equatable {
    public var name: String
    public var utilizationPercent: Double?
    public var memoryBytes: UInt64?

    public init(name: String, utilizationPercent: Double?, memoryBytes: UInt64?) {
        self.name = name
        self.utilizationPercent = utilizationPercent
        self.memoryBytes = memoryBytes
    }
}

public enum HostExtras {
    public static func battery() -> BatteryStatus {
        var raw = appfold_battery()
        guard appfold_read_battery(&raw) == 0 else {
            return BatteryStatus(
                hasBattery: false,
                onACPower: true,
                percent: nil,
                minutesRemaining: nil,
                cycleCount: nil,
                healthPercent: nil,
                watts: nil,
                temperatureC: nil
            )
        }
        return BatteryStatus(
            hasBattery: raw.has_battery != 0,
            onACPower: raw.on_ac_power != 0,
            percent: raw.has_percent != 0 ? raw.percent : nil,
            minutesRemaining: raw.has_minutes != 0 ? Int(raw.minutes_remaining) : nil,
            cycleCount: raw.has_cycle_count != 0 ? Int(raw.cycle_count) : nil,
            healthPercent: raw.has_health != 0 ? raw.health_percent : nil,
            watts: raw.has_watts != 0 ? raw.watts : nil,
            temperatureC: raw.has_temperature != 0 ? raw.temperature_c : nil
        )
    }

    public static func volumes() -> [VolumeInfo] {
        let capacity = 128
        var buffer = [appfold_volume](repeating: appfold_volume(), count: capacity)
        let count = buffer.withUnsafeMutableBufferPointer { pointer in
            Int(appfold_read_volumes(pointer.baseAddress, Int32(capacity)))
        }
        guard count > 0 else { return [] }
        return (0..<min(count, capacity)).map { index in
            let item = buffer[index]
            return VolumeInfo(
                name: cString(item.name),
                freeBytes: item.free_bytes,
                totalBytes: item.total_bytes
            )
        }
    }

    public static func memory() -> MemoryBreakdown {
        var raw = appfold_memory()
        guard appfold_read_memory(&raw) == 0 else {
            return MemoryBreakdown(
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                freeBytes: 0,
                swapBytes: 0,
                totalBytes: 0
            )
        }
        return MemoryBreakdown(
            wiredBytes: raw.wired_bytes,
            compressedBytes: raw.compressed_bytes,
            cachedBytes: raw.cached_bytes,
            freeBytes: raw.free_bytes,
            swapBytes: raw.swap_bytes,
            totalBytes: raw.total_bytes
        )
    }

    public static func primaryInterface() -> InterfaceInfo {
        var raw = appfold_interface()
        guard appfold_read_primary_interface(&raw) == 0 else {
            return InterfaceInfo(bsdName: "", kind: "", bytesIn: 0, bytesOut: 0)
        }
        return InterfaceInfo(
            bsdName: cString(raw.bsd_name),
            kind: cString(raw.kind),
            bytesIn: raw.bytes_in,
            bytesOut: raw.bytes_out
        )
    }

    public static func gpu() -> GPUStatus {
        var raw = appfold_gpu()
        guard appfold_read_gpu(&raw) == 0 else {
            return GPUStatus(name: "", utilizationPercent: nil, memoryBytes: nil)
        }
        return GPUStatus(
            name: cString(raw.name),
            utilizationPercent: raw.has_utilization != 0 ? raw.utilization_percent : nil,
            memoryBytes: raw.has_memory != 0 ? raw.memory_bytes : nil
        )
    }

    private static func cString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
    }
}
