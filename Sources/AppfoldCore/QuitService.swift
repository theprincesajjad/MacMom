import Darwin
import Foundation

public enum QuitAction: Equatable {
    /// Ask the process to exit.
    case quit
    /// End the process immediately.
    case forceQuit

    public var signal: Int32 {
        switch self {
        case .quit: return SIGTERM
        case .forceQuit: return SIGKILL
        }
    }
}

public struct DeliveredSignal: Equatable {
    public var pid: Int32
    public var signal: Int32
    public var result: Int32

    public init(pid: Int32, signal: Int32, result: Int32) {
        self.pid = pid
        self.signal = signal
        self.result = result
    }
}

public struct QuitOutcome: Equatable {
    public var confirmed: Bool
    public var signals: [DeliveredSignal]

    public init(confirmed: Bool, signals: [DeliveredSignal]) {
        self.confirmed = confirmed
        self.signals = signals
    }
}

/// Sends a terminate or kill only after the caller has confirmed it.
public struct QuitService {
    public var send: (_ pid: Int32, _ signal: Int32) -> Int32

    public init(send: @escaping (_ pid: Int32, _ signal: Int32) -> Int32) {
        self.send = send
    }

    public static func live() -> QuitService {
        QuitService { pid, signal in
            Darwin.kill(pid, signal)
        }
    }

    public func perform(pids: [Int32], action: QuitAction, confirmed: Bool) -> QuitOutcome {
        guard confirmed else {
            return QuitOutcome(confirmed: false, signals: [])
        }
        let signal = action.signal
        let selfPID = Darwin.getpid()
        var delivered: [DeliveredSignal] = []
        var seen = Set<Int32>()
        for pid in pids {
            if pid <= 1 || pid == selfPID || !seen.insert(pid).inserted {
                continue
            }
            let result = send(pid, signal)
            delivered.append(DeliveredSignal(pid: pid, signal: signal, result: result))
        }
        return QuitOutcome(confirmed: true, signals: delivered)
    }

    public func perform(app: AppRow, action: QuitAction, confirmed: Bool) -> QuitOutcome {
        perform(pids: app.members.map(\.pid), action: action, confirmed: confirmed)
    }
}

/// Words on the confirm step. Nothing is signaled until the user accepts.
public struct QuitPrompt: Equatable {
    public var title: String
    public var message: String
    public var confirmTitle: String

    public init(title: String, message: String, confirmTitle: String) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
    }
}

public enum QuitCopy {
    public static func application(name: String, processCount: Int, force: Bool) -> QuitPrompt {
        let count = max(processCount, 0)
        let noun = count == 1 ? "process" : "processes"
        return QuitPrompt(
            title: force ? "Force Quit \(name)?" : "Quit \(name)?",
            message: force ? "\(count) \(noun) will end immediately." : "\(count) \(noun) will close.",
            confirmTitle: force ? "Force Quit" : "Quit"
        )
    }

    public static func process(name: String, force: Bool) -> QuitPrompt {
        QuitPrompt(
            title: force ? "Force Quit \(name)?" : "Quit \(name)?",
            message: force ? "This process will end immediately." : "This process will close.",
            confirmTitle: force ? "Force Quit" : "Quit"
        )
    }
}

/// How a confirmed quit is delivered.
/// A Mac app is asked to exit. Force quit, and anything that is not a Mac app, is a signal to those pids.
public enum AppQuitPlan: Equatable {
    case askApplication(pid: Int32)
    case signal(pids: [Int32], action: QuitAction)
}

public enum AppQuitPlanner {
    public static func plan(memberPIDs: [Int32], runningApplicationPID: Int32?, force: Bool) -> AppQuitPlan {
        let pids = memberPIDs.filter { $0 > 1 }
        if force {
            return .signal(pids: pids, action: .forceQuit)
        }
        if let runningApplicationPID, runningApplicationPID > 1, pids.contains(runningApplicationPID) {
            return .askApplication(pid: runningApplicationPID)
        }
        return .signal(pids: pids, action: .quit)
    }
}
