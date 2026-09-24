import AppfoldCore
import XCTest

final class DevProjectTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("appfold-dev-projects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testNodeProcessesUnderOneProjectFoldTogetherAndLeaveOtherProjectsAlone() throws {
        let storefront = try makeDirectory("storefront", marker: "package.json")
        let web = try makeDirectory("storefront/web")
        let worker = try makeDirectory("storefront/worker")
        let billing = try makeDirectory("billing", marker: "pyproject.toml")
        let loose = try makeDirectory("n0/n1/n2/n3/n4/loose")
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_003_600)

        let processes = [
            dev(20, "node", web.path, [4321, 3000, 3000], 1_000, 1.5, later),
            dev(10, "nodejs", worker.path, [3000], 400, 2.25, earlier),
            dev(30, "python3", billing.path, [8000], 200, 1, earlier),
            dev(40, "esbuild", web.path, [], 9_999, 50, nil),
            dev(50, "ssh", "/", [], 10, 0.1, nil),
            dev(60, "caddy", loose.path, [7777], 50, 0.5, nil),
            dev(70, "node", loose.path, [], 80, 4, nil)
        ]

        let groups = DevProjects.group(processes)
        XCTAssertEqual(Set(groups.map(\.name)), ["storefront", "billing", "loose"])
        XCTAssertNil(groups.first { $0.pids.contains(40) || $0.pids.contains(50) || $0.pids.contains(70) })
        XCTAssertNil(groups.first { $0.name == "ssh" || $0.name == "esbuild" })

        let folded = try XCTUnwrap(groups.first { $0.directory == storefront.path })
        XCTAssertEqual(folded, ProjectGroup(
            name: "storefront",
            directory: storefront.path,
            runtime: "node",
            pids: [10, 20],
            ports: [3000, 4321],
            memoryBytes: 1_400,
            cpuPercent: 3.75,
            oldestStart: earlier
        ))

        let python = try XCTUnwrap(groups.first { $0.directory == billing.path })
        XCTAssertEqual(python.name, "billing")
        XCTAssertEqual(python.runtime, "python")
        XCTAssertEqual(python.pids, [30])
        XCTAssertEqual(python.ports, [8000])
        XCTAssertEqual(python.memoryBytes, 200)
        XCTAssertNotEqual(python.directory, folded.directory)

        let listener = try XCTUnwrap(groups.first { $0.directory == loose.path })
        XCTAssertEqual(listener.name, "loose")
        XCTAssertEqual(listener.pids, [60])
        XCTAssertEqual(listener.ports, [7777])
        XCTAssertEqual(listener.memoryBytes, 50)
        XCTAssertNil(listener.oldestStart)
    }

    func testEachProjectMarkerAnchorsTheNearestDirectory() throws {
        let expectations: [(folder: String, marker: String, directoryMarker: Bool, name: String, runtime: String)] = [
            ("pack", "package.json", false, "nodejs", "node"),
            ("goproj", "go.mod", false, "go", "go"),
            ("pyproj", "pyproject.toml", false, "python", "python"),
            ("rustproj", "Cargo.toml", false, "cargo", "cargo"),
            ("gemproj", "Gemfile", false, "ruby", "ruby"),
            ("gitproj", ".git", true, "bun", "bun")
        ]
        var processes: [DevProcess] = []
        var directories: [String: String] = [:]
        for (index, item) in expectations.enumerated() {
            let directory = try makeDirectory(item.folder, marker: item.marker, markerIsDirectory: item.directoryMarker)
            let source = try makeDirectory("\(item.folder)/src")
            directories[item.folder] = directory.path
            processes.append(dev(Int32(100 + index), item.name, source.path, [4000 + index], 10, 1, nil))
        }

        let outer = try makeDirectory("outer", marker: "package.json")
        let inner = try makeDirectory("outer/inner", marker: "Cargo.toml")
        let nested = try makeDirectory("outer/inner/src")
        processes.append(dev(200, "cargo", nested.path, [], 5, 0.25, nil))

        let groups = DevProjects.group(processes)
        for item in expectations {
            let directory = try XCTUnwrap(directories[item.folder])
            let group = try XCTUnwrap(groups.first { $0.directory == directory })
            XCTAssertEqual(group.name, item.folder)
            XCTAssertEqual(group.runtime, item.runtime)
        }

        let cargo = try XCTUnwrap(groups.first { $0.pids == [200] })
        XCTAssertEqual(cargo.name, "inner")
        XCTAssertEqual(cargo.directory, inner.path)
        XCTAssertNotEqual(cargo.directory, outer.path)
    }

    func testWalkStopsAfterSixDirectories() throws {
        let leaf = try makeDirectory("d0/d1/d2/d3/d4/d5/d6")
        let within = directory("d0/d1")
        try Data("marker".utf8).write(to: within.appendingPathComponent("package.json"))
        let tooFar = directory("d0")
        try FileManager.default.createDirectory(
            at: tooFar.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )

        let found = DevProjects.group([
            dev(1, "node", leaf.path, [], 10, 1, nil)
        ])
        XCTAssertEqual(found.map(\.name), ["d1"])
        XCTAssertEqual(found.map(\.directory), [within.path])

        try FileManager.default.removeItem(at: within.appendingPathComponent("package.json"))
        let withPort = DevProjects.group([
            dev(2, "deno", leaf.path, [5555], 8, 0.5, nil)
        ])
        XCTAssertEqual(withPort.map(\.name), ["d6"])
        XCTAssertEqual(withPort.map(\.directory), [leaf.path])
        XCTAssertEqual(withPort.map(\.ports), [[5555]])

        let dropped = DevProjects.group([
            dev(3, "php", leaf.path, [], 8, 0.5, nil)
        ])
        XCTAssertTrue(dropped.isEmpty)
    }

    private func dev(
        _ pid: Int32,
        _ name: String,
        _ cwd: String,
        _ ports: [Int],
        _ memory: UInt64,
        _ cpu: Double,
        _ started: Date?
    ) -> DevProcess {
        DevProcess(
            pid: pid,
            name: name,
            cwd: cwd,
            ports: ports,
            memoryBytes: memory,
            cpuPercent: cpu,
            startedAt: started
        )
    }

    @discardableResult
    private func makeDirectory(_ relative: String, marker: String? = nil, markerIsDirectory: Bool = false) throws -> URL {
        let directory = self.directory(relative)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let marker {
            let markerURL = directory.appendingPathComponent(marker)
            if markerIsDirectory {
                try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: true)
            } else {
                try Data("marker".utf8).write(to: markerURL)
            }
        }
        return directory
    }

    private func directory(_ relative: String) -> URL {
        var directory = root!
        for part in relative.split(separator: "/") where !part.isEmpty {
            directory = directory.appendingPathComponent(String(part), isDirectory: true)
        }
        return directory
    }
}
