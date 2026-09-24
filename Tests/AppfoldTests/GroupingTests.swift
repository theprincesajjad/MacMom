import AppfoldCore
import XCTest

final class GroupingTests: XCTestCase {
    func testAppsFoldHelpersAndKeepUnownedProcesses() throws {
        let processes = [
            fact(100, 1, "Safari", "/Applications/Safari.app/Contents/MacOS/Safari", 1000, 10, 5, 50, 7),
            fact(101, 100, "Safari Helper", "/Applications/Safari.app/Contents/XPCServices/Helper.xpc/Contents/MacOS/Helper", 200, 2, 1, 20, 3),
            fact(102, 101, "gpu-helper", "/usr/local/bin/gpu-helper", 50, 1, 1, 5, 1),
            fact(103, 1, "Safari Web Content", "/Applications/Safari.app/Contents/MacOS/com.apple.WebKit.WebContent", 25, 4, 1, 2, 0),
            fact(200, 1, "Mail", "/Applications/Mail.app/Contents/MacOS/Mail", 400, 3, 2, 9, 4),
            fact(201, 100, "Preview", "/Applications/Preview.app/Contents/MacOS/Preview", 80, 1, 1, 1, 1),
            fact(300, 1, "ssh", "/usr/bin/ssh", 10, 1, 0, 0, 8),
            fact(301, 300, "sleep", "/bin/sleep", 4, 0, 0, 0, 0)
        ]

        let rows = AppGrouper.group(processes)
        let names = Set(rows.map(\.name))
        XCTAssertEqual(names, ["Safari", "Mail", "Preview", "ssh", "sleep"])
        XCTAssertNil(rows.first { $0.name == "Safari Helper" || $0.name == "gpu-helper" || $0.name == "Safari Web Content" })

        let safari = try XCTUnwrap(rows.first { $0.name == "Safari" })
        XCTAssertEqual(Set(safari.members.map(\.pid)), [100, 101, 102, 103])
        XCTAssertEqual(safari.memoryBytes, 1275)
        XCTAssertEqual(safari.cpuPercent, 17, accuracy: 0.000_001)
        XCTAssertEqual(safari.energy, 8)
        XCTAssertEqual(safari.diskBytes, 77)
        XCTAssertEqual(safari.networkBytes, 11)
        XCTAssertEqual(safari.bundlePath, "/Applications/Safari.app")

        let mail = try XCTUnwrap(rows.first { $0.name == "Mail" })
        XCTAssertEqual(mail.members.map(\.pid), [200])
        XCTAssertEqual(mail.memoryBytes, 400)
        XCTAssertEqual(mail.cpuPercent, 3, accuracy: 0.000_001)
        XCTAssertEqual(mail.energy, 2)
        XCTAssertEqual(mail.diskBytes, 9)
        XCTAssertEqual(mail.networkBytes, 4)

        let preview = try XCTUnwrap(rows.first { $0.name == "Preview" })
        XCTAssertEqual(preview.members.map(\.pid), [201])
        XCTAssertNotEqual(preview.id, safari.id)

        let ssh = try XCTUnwrap(rows.first { $0.id == "pid:300" })
        XCTAssertEqual(ssh.name, "ssh")
        XCTAssertEqual(ssh.members.map(\.pid), [300])
        XCTAssertNil(ssh.bundlePath)

        let sleep = try XCTUnwrap(rows.first { $0.id == "pid:301" })
        XCTAssertEqual(sleep.members.map(\.pid), [301])

        var seen = Set<Int32>()
        for row in rows {
            XCTAssertEqual(row.memoryBytes, row.members.reduce(0) { $0 + $1.memoryBytes })
            XCTAssertEqual(row.cpuPercent, row.members.reduce(0) { $0 + $1.cpuPercent }, accuracy: 0.000_001)
            XCTAssertEqual(row.energy, row.members.reduce(0) { $0 + $1.energy })
            XCTAssertEqual(row.diskBytes, row.members.reduce(0) { $0 + $1.diskBytes })
            XCTAssertEqual(row.networkBytes, row.members.reduce(0) { $0 + $1.networkBytes })
            for member in row.members {
                XCTAssertTrue(seen.insert(member.pid).inserted)
            }
        }
        XCTAssertEqual(seen, Set(processes.map(\.pid)))
        XCTAssertLessThan(rows.count, processes.count)
    }

    func testCycleOfUnownedProcessesDoesNotCollapseOrHang() {
        let processes = [
            fact(400, 401, "a", "/tmp/a", 1, 0, 0, 0, 0),
            fact(401, 400, "b", "/tmp/b", 1, 0, 0, 0, 0)
        ]
        let rows = AppGrouper.group(processes)
        XCTAssertEqual(Set(rows.map(\.id)), ["pid:400", "pid:401"])
    }

    func testLiveSnapshotPutsEachProcessInOneApp() {
        let snapshot = SystemSampler().takeSnapshot()
        XCTAssertGreaterThan(snapshot.processCount, 1)
        var pids: [Int32] = []
        for app in snapshot.apps {
            XCTAssertFalse(app.members.isEmpty)
            XCTAssertEqual(app.memoryBytes, app.members.reduce(0) { $0 + $1.memoryBytes })
            XCTAssertEqual(app.cpuPercent, app.members.reduce(0) { $0 + $1.cpuPercent }, accuracy: 0.000_001)
            XCTAssertEqual(app.energy, app.members.reduce(0) { $0 + $1.energy })
            XCTAssertEqual(app.diskBytes, app.members.reduce(0) { $0 + $1.diskBytes })
            XCTAssertEqual(app.networkBytes, app.members.reduce(0) { $0 + $1.networkBytes })
            pids.append(contentsOf: app.members.map(\.pid))
        }
        XCTAssertEqual(pids.count, Set(pids).count)
        XCTAssertEqual(pids.count, snapshot.processCount)
        XCTAssertGreaterThan(snapshot.processCount, 100)
        XCTAssertTrue(snapshot.apps.contains { $0.members.count > 1 })
        XCTAssertLessThan(snapshot.apps.count, snapshot.processCount)
    }

    private func fact(
        _ pid: Int32,
        _ parent: Int32,
        _ name: String,
        _ path: String,
        _ memory: UInt64,
        _ cpu: Double,
        _ energy: UInt64,
        _ disk: UInt64,
        _ network: UInt64
    ) -> ProcessFact {
        ProcessFact(
            pid: pid,
            parentPID: parent,
            name: name,
            executablePath: path,
            bundlePath: nil,
            memoryBytes: memory,
            cpuPercent: cpu,
            energy: energy,
            diskBytes: disk,
            networkBytes: network
        )
    }
}
