import CLibProc
import Foundation

public final class SystemSampler {
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousDisk: [Int32: UInt64] = [:]
    private var previousDiskRead: UInt64?
    private var previousDiskWrite: UInt64?
    public private(set) var userCPUPercent: Double = 0
    public private(set) var systemCPUShare: Double = 0
    public private(set) var diskReadBytesPerSecond: Double = 0
    public private(set) var diskWriteBytesPerSecond: Double = 0
    public private(set) var lastElapsed: TimeInterval = 0
    private var previousHost: HostCPUTicks?
    private var previousNetwork: UInt64?
    private var previousEnergy: [Int32: UInt64] = [:]
    private var latestWatts: [Int32: Double] = [:]
    private var listBuffer: [appfold_proc] = []
    private var previousAt: Date?

    public init() {}

    /// Watts since the previous sample for one process. Nil until a second reading exists.
    public func watts(for pid: Int32) -> Double? {
        latestWatts[pid]
    }

    /// Snapshot the menu bar and the main window both display.
    public func takeSnapshot(now: Date = Date()) -> SystemSnapshot {
        let host = readHost()
        let elapsed = previousAt.map { now.timeIntervalSince($0) } ?? 0
        let usable = elapsed > 0 ? elapsed : 0
        let systemCPU = HostCPU.percent(previous: previousHost, current: host.ticks)
        if let previous = previousHost {
            let total = HostCPU.wrappedDelta(host.ticks.total, previous.total)
            if total > 0 {
                let user = HostCPU.wrappedDelta(host.ticks.user, previous.user) + HostCPU.wrappedDelta(host.ticks.nice, previous.nice)
                let system = HostCPU.wrappedDelta(host.ticks.system, previous.system)
                userCPUPercent = Double(user) / Double(total) * 100
                systemCPUShare = Double(system) / Double(total) * 100
            }
        } else {
            userCPUPercent = 0
            systemCPUShare = 0
        }
        let networkBytes = CounterDelta.bytes(previous: previousNetwork, current: host.networkBytes)
        let networkRate = CounterDelta.perSecond(bytes: networkBytes, elapsed: usable)

        let listed = listProcesses()
        var facts: [ProcessFact] = []
        facts.reserveCapacity(listed.count)
        var seen = Set<Int32>()
        var readTotal: UInt64 = 0
        var writeTotal: UInt64 = 0
        for proc in listed {
            if proc.pid <= 0 || !seen.insert(proc.pid).inserted { continue }
            let cpu = CPUDelta.percent(previousNS: previousCPU[proc.pid], currentNS: proc.cpuTimeNS, elapsed: usable)
            let disk = CounterDelta.bytes(previous: previousDisk[proc.pid], current: proc.diskBytes)
            readTotal += proc.diskReadBytes
            writeTotal += proc.diskWriteBytes
            previousCPU[proc.pid] = proc.cpuTimeNS
            previousDisk[proc.pid] = proc.diskBytes
            if let watts = EnergyRate.watts(previousNanojoules: previousEnergy[proc.pid], currentNanojoules: proc.energy, elapsed: usable) {
                latestWatts[proc.pid] = watts
            }
            previousEnergy[proc.pid] = proc.energy
            let name = proc.name.isEmpty ? "Process \(proc.pid)" : proc.name
            facts.append(ProcessFact(
                pid: proc.pid,
                parentPID: proc.parentPID,
                name: name,
                executablePath: proc.path,
                bundlePath: BundlePath.outermostApp(in: proc.path),
                memoryBytes: proc.memoryBytes,
                cpuPercent: cpu,
                energy: proc.energy,
                diskBytes: disk,
                networkBytes: 0,
                startedAt: proc.startUnix > 0 ? Date(timeIntervalSince1970: TimeInterval(proc.startUnix)) : nil
            ))
        }
        previousCPU = previousCPU.filter { seen.contains($0.key) }
        previousDisk = previousDisk.filter { seen.contains($0.key) }
        previousEnergy = previousEnergy.filter { seen.contains($0.key) }
        latestWatts = latestWatts.filter { seen.contains($0.key) }

        let diskSum = facts.reduce(UInt64(0)) { $0 + $1.diskBytes }
        let readDelta = CounterDelta.bytes(previous: previousDiskRead, current: readTotal)
        let writeDelta = CounterDelta.bytes(previous: previousDiskWrite, current: writeTotal)
        lastElapsed = usable
        diskReadBytesPerSecond = CounterDelta.perSecond(bytes: readDelta, elapsed: usable)
        diskWriteBytesPerSecond = CounterDelta.perSecond(bytes: writeDelta, elapsed: usable)
        previousDiskRead = readTotal
        previousDiskWrite = writeTotal
        let apps = AppGrouper.group(facts)
        previousHost = host.ticks
        previousNetwork = host.networkBytes
        previousAt = now

        return SystemSnapshot(
            sampledAt: now,
            systemCPUPercent: systemCPU,
            systemMemoryUsedBytes: host.memoryUsed,
            systemMemoryTotalBytes: host.memoryTotal,
            systemDiskBytesPerSecond: CounterDelta.perSecond(bytes: diskSum, elapsed: usable),
            systemNetworkBytesPerSecond: networkRate,
            apps: apps,
            processCount: facts.count
        )
    }

    private struct ListedProcess {
        var pid: Int32
        var parentPID: Int32
        var name: String
        var path: String
        var memoryBytes: UInt64
        var cpuTimeNS: UInt64
        var diskBytes: UInt64
        var diskReadBytes: UInt64
        var diskWriteBytes: UInt64
        var energy: UInt64
        var startUnix: Int64
    }

    private struct HostReading {
        var ticks: HostCPUTicks
        var memoryUsed: UInt64
        var memoryTotal: UInt64
        var networkBytes: UInt64
    }

    private func listProcesses() -> [ListedProcess] {
        let suggested = Int(appfold_suggested_capacity())
        let capacity = min(max(suggested, 1), 4096)
        if listBuffer.count < capacity {
            listBuffer = [appfold_proc](repeating: appfold_proc(), count: capacity)
        }
        let count = listBuffer.withUnsafeMutableBufferPointer { pointer -> Int in
            Int(appfold_list_processes(pointer.baseAddress, Int32(capacity)))
        }
        guard count > 0 else { return [] }
        var rows: [ListedProcess] = []
        rows.reserveCapacity(count)
        for index in 0..<min(count, capacity) {
            let item = listBuffer[index]
            rows.append(ListedProcess(
                pid: item.pid,
                parentPID: item.ppid,
                name: Self.cString(item.name),
                path: Self.cString(item.path),
                memoryBytes: item.memory_bytes,
                cpuTimeNS: item.cpu_time_ns,
                diskBytes: item.disk_bytes,
                diskReadBytes: item.disk_read_bytes,
                diskWriteBytes: item.disk_write_bytes,
                energy: item.energy,
                startUnix: item.start_unix
            ))
        }
        return rows
    }

    private func readHost() -> HostReading {
        var host = appfold_host()
        guard appfold_read_host(&host) == 0 else {
            return HostReading(
                ticks: HostCPUTicks(user: 0, system: 0, idle: 0, nice: 0),
                memoryUsed: 0,
                memoryTotal: 0,
                networkBytes: 0
            )
        }
        return HostReading(
            ticks: HostCPUTicks(
                user: host.cpu_user,
                system: host.cpu_system,
                idle: host.cpu_idle,
                nice: host.cpu_nice
            ),
            memoryUsed: host.memory_used,
            memoryTotal: host.memory_total,
            networkBytes: host.network_bytes
        )
    }

    private static func cString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
    }
}
