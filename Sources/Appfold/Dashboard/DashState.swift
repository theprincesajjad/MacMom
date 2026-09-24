import AppKit

/// Display model for the dashboard. Values are already measured; views only format them.
struct DashApp: Equatable {
    var id: String
    var name: String
    var processCount: Int
    var bundlePath: String?
    var cpuPercent: Double
    var memoryBytes: UInt64
    var diskBytesPerSecond: Double
    var networkBytesPerSecond: Double
    var energy: UInt64
    var powerWatts: Double?
    var gpuPercent: Double?
    var icon: NSImage?
}

struct DashMember: Equatable {
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var memoryBytes: UInt64
}

struct DashProject: Equatable {
    var name: String
    var runtime: String
    var directory: String
    var processCount: Int
    var ports: [Int]
    var memoryBytes: UInt64
    var cpuPercent: Double
    var pids: [Int32]
    var uptime: TimeInterval?
    /// Minutes since this project last used noticeable CPU. Nil when it is busy now.
    var idleMinutes: Int?
}

struct DashState: Equatable {
    var cpuNow: Double = 0
    var cpuUserShare: Double = 0
    var cpuSystemShare: Double = 0
    var cpuAverage: Double = 0
    var cpuLoad: Double = 0
    var cpuCores: Int = 0
    var performanceCores: Int = 0
    var efficiencyCores: Int = 0
    var cpuSeries: [Double] = []

    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var memoryApp: UInt64 = 0
    var memoryWired: UInt64 = 0
    var memoryCompressed: UInt64 = 0
    var memoryCached: UInt64 = 0
    var memoryFree: UInt64 = 0
    var memorySwap: UInt64 = 0
    var memorySeries: [Double] = []

    var diskFree: UInt64 = 0
    var diskUsed: UInt64 = 0
    var diskReadPerSecond: Double = 0
    var diskWritePerSecond: Double = 0
    var diskWrittenToday: UInt64 = 0
    var diskSeries: [Double] = []
    var volumeNames: [String] = []

    var netDownPerSecond: Double = 0
    var netUpPerSecond: Double = 0
    var netToday: UInt64 = 0
    var netLast7Days: UInt64 = 0
    var netLast30Days: UInt64 = 0
    var netInterfaceName: String = ""
    var netInterfaceKind: String = ""
    var netSeries: [Double] = []

    var gpuName: String = ""
    var gpuPercent: Double?
    var gpuMemoryBytes: UInt64?
    var gpuAverage: Double?
    var gpuPeak: Double?
    var gpuSeries: [Double] = []

    var hasBattery: Bool = false
    var onBattery: Bool = false
    var batteryPercent: Double?
    var batteryMinutesRemaining: Int?
    var batteryCycles: Int?
    var batteryWatts: Double?
    var batteryHealthPercent: Double?
    var batteryTemperatureC: Double?
    var batterySeries: [Double] = []

    var apps: [DashApp] = []
    var selectedAppID: String?
    var members: [DashMember] = []

    var projects: [DashProject] = []
    var projectsScanned: Bool = false
    var alerts: [String] = []
}

enum DashTab: Int, CaseIterable {
    case overview
    case cpu
    case memory
    case disk
    case network
    case gpu
    case battery
    case projects

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .gpu: return "GPU"
        case .battery: return "Battery"
        case .projects: return "Projects"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .gpu: return "cube.transparent"
        case .battery: return "battery.100percent"
        case .projects: return "folder"
        }
    }
}
