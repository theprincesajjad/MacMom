import AppfoldCore
import Darwin
import Foundation
import XCTest

final class QuitTests: XCTestCase {
    func testUnconfirmedQuitLeavesTheChildAliveAndSendsNothing() throws {
        let child = try spawnSleep()
        defer { reap(child) }
        let bystander = try spawnSleep()
        defer { reap(bystander) }

        var calls: [(Int32, Int32)] = []
        let service = QuitService { pid, signal in
            calls.append((pid, signal))
            return Darwin.kill(pid, signal)
        }

        let outcome = service.perform(pids: [child.processIdentifier], action: .quit, confirmed: false)
        XCTAssertFalse(outcome.confirmed)
        XCTAssertTrue(outcome.signals.isEmpty)
        XCTAssertTrue(calls.isEmpty)

        let stillAlive = expectation(description: "child stays alive")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            XCTAssertTrue(child.isRunning)
            XCTAssertTrue(bystander.isRunning)
            stillAlive.fulfill()
        }
        wait(for: [stillAlive], timeout: 2)
    }

    func testConfirmedQuitDeliversTerminateOnlyToThatChild() throws {
        let child = try spawnSleep()
        defer { reap(child) }
        let bystander = try spawnSleep()
        defer { reap(bystander) }

        var calls: [(Int32, Int32)] = []
        let service = QuitService { pid, signal in
            calls.append((pid, signal))
            return Darwin.kill(pid, signal)
        }
        let exited = expectExit(of: child)
        let outcome = service.perform(pids: [child.processIdentifier], action: .quit, confirmed: true)
        wait(for: [exited], timeout: 3)

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, child.processIdentifier)
        XCTAssertEqual(calls[0].1, SIGTERM)
        XCTAssertEqual(outcome.signals.map(\.pid), [child.processIdentifier])
        XCTAssertEqual(outcome.signals.map(\.signal), [SIGTERM])
        XCTAssertFalse(child.isRunning)
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGTERM)
        XCTAssertTrue(bystander.isRunning)
    }

    func testConfirmedForceQuitDeliversImmediateKillOnlyToThatChild() throws {
        let child = try spawnSleep()
        defer { reap(child) }
        let bystander = try spawnSleep()
        defer { reap(bystander) }

        var calls: [(Int32, Int32)] = []
        let service = QuitService { pid, signal in
            calls.append((pid, signal))
            return Darwin.kill(pid, signal)
        }
        let exited = expectExit(of: child)
        let outcome = service.perform(pids: [child.processIdentifier], action: .forceQuit, confirmed: true)
        wait(for: [exited], timeout: 3)

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, child.processIdentifier)
        XCTAssertEqual(calls[0].1, SIGKILL)
        XCTAssertEqual(outcome.signals.map(\.signal), [SIGKILL])
        XCTAssertEqual(outcome.signals.map(\.pid), [child.processIdentifier])
        XCTAssertFalse(child.isRunning)
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGKILL)
        XCTAssertTrue(bystander.isRunning)
        XCTAssertFalse(calls.contains { $0.0 == bystander.processIdentifier })
    }

    func testConfirmedAppQuitSignalsEachMemberAndLeavesTheBystander() throws {
        let first = try spawnSleep()
        defer { reap(first) }
        let second = try spawnSleep()
        defer { reap(second) }
        let bystander = try spawnSleep()
        defer { reap(bystander) }

        let app = AppRow(
            id: "bundle:/tmp/Fixture.app",
            name: "Fixture",
            bundlePath: "/tmp/Fixture.app",
            members: [
                member(first.processIdentifier, "Fixture"),
                member(second.processIdentifier, "Fixture Helper")
            ],
            memoryBytes: 2,
            cpuPercent: 0,
            energy: 0,
            diskBytes: 0,
            networkBytes: 0
        )

        var calls: [(Int32, Int32)] = []
        let service = QuitService { pid, signal in
            calls.append((pid, signal))
            return Darwin.kill(pid, signal)
        }
        let firstExit = expectExit(of: first)
        let secondExit = expectExit(of: second)
        let outcome = service.perform(app: app, action: .quit, confirmed: true)
        wait(for: [firstExit, secondExit], timeout: 3)

        XCTAssertEqual(Set(calls.map(\.0)), [first.processIdentifier, second.processIdentifier])
        XCTAssertTrue(calls.allSatisfy { $0.1 == SIGTERM })
        XCTAssertEqual(Set(outcome.signals.map(\.pid)), [first.processIdentifier, second.processIdentifier])
        XCTAssertTrue(outcome.signals.allSatisfy { $0.signal == SIGTERM })
        XCTAssertFalse(first.isRunning)
        XCTAssertFalse(second.isRunning)
        XCTAssertTrue(bystander.isRunning)
    }

    func testQuitPromptNamesTheAppAndHowManyProcessesClose() {
        let prompt = QuitCopy.application(name: "Google Chrome", processCount: 96, force: false)
        XCTAssertEqual(prompt.title, "Quit Google Chrome?")
        XCTAssertEqual(prompt.message, "96 processes will close.")
        XCTAssertEqual(prompt.confirmTitle, "Quit")

        let one = QuitCopy.application(name: "Notes", processCount: 1, force: false)
        XCTAssertEqual(one.message, "1 process will close.")

        let forced = QuitCopy.application(name: "Google Chrome", processCount: 96, force: true)
        XCTAssertEqual(forced.title, "Force Quit Google Chrome?")
        XCTAssertEqual(forced.message, "96 processes will end immediately.")
        XCTAssertEqual(forced.confirmTitle, "Force Quit")

        let process = QuitCopy.process(name: "node", force: false)
        XCTAssertEqual(process.title, "Quit node?")
        XCTAssertEqual(process.message, "This process will close.")
    }

    func testMacAppQuitAsksTheAppAndForceQuitSignalsEveryMember() {
        let members: [Int32] = [400, 401, 402]
        XCTAssertEqual(
            AppQuitPlanner.plan(memberPIDs: members, runningApplicationPID: 400, force: false),
            .askApplication(pid: 400)
        )
        XCTAssertEqual(
            AppQuitPlanner.plan(memberPIDs: members, runningApplicationPID: 400, force: true),
            .signal(pids: members, action: .forceQuit)
        )
        XCTAssertEqual(
            AppQuitPlanner.plan(memberPIDs: members, runningApplicationPID: nil, force: false),
            .signal(pids: members, action: .quit)
        )
        XCTAssertEqual(
            AppQuitPlanner.plan(memberPIDs: [0, 1, 50], runningApplicationPID: 1, force: false),
            .signal(pids: [50], action: .quit)
        )
    }

    func testRefusesToSignalPidZeroOrOne() {
        var calls: [Int32] = []
        let service = QuitService { pid, signal in
            calls.append(pid)
            return 0
        }
        let outcome = service.perform(pids: [0, 1], action: .forceQuit, confirmed: true)
        XCTAssertTrue(outcome.confirmed)
        XCTAssertTrue(outcome.signals.isEmpty)
        XCTAssertTrue(calls.isEmpty)
    }

    private func spawnSleep() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        return process
    }

    private func expectExit(of process: Process) -> XCTestExpectation {
        let expectation = expectation(description: "process \(process.processIdentifier) exits")
        process.terminationHandler = { _ in
            expectation.fulfill()
        }
        return expectation
    }

    private func reap(_ process: Process) {
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }

    private func member(_ pid: Int32, _ name: String) -> ProcessFact {
        ProcessFact(
            pid: pid,
            parentPID: 1,
            name: name,
            executablePath: "/tmp/Fixture.app/Contents/MacOS/\(name)",
            bundlePath: "/tmp/Fixture.app",
            memoryBytes: 1,
            cpuPercent: 0,
            energy: 0,
            diskBytes: 0,
            networkBytes: 0
        )
    }
}
