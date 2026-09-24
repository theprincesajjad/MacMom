import AppfoldCore
import XCTest

final class HistoryAlertTests: XCTestCase {
    func testHistoryRanksRangesAndDropsSamplesOlderThanThirtyDays() throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("appfold-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.jsonl")

        let store = HistoryStore(fileURL: file, clock: { clock.now })
        let now = clock.now
        store.record([
            sample("recent", "Recent", now.addingTimeInterval(-2 * 3600), cpu: 4),
            sample("recent", "Recent", now.addingTimeInterval(-1 * 3600), cpu: 6),
            sample("other", "Other", now.addingTimeInterval(-30 * 60), cpu: 9),
            sample("day", "Day", now.addingTimeInterval(-18 * 3600), cpu: 50),
            sample("week", "Week", now.addingTimeInterval(-3 * 24 * 3600), cpu: 80),
            sample("month", "Month", now.addingTimeInterval(-20 * 24 * 3600), cpu: 100),
            sample("boundary", "Boundary", now.addingTimeInterval(-HistoryRetention.seconds), cpu: 1),
            sample("ancient", "Ancient", now.addingTimeInterval(-(HistoryRetention.seconds + 1)), cpu: 999)
        ])

        let reopened = HistoryStore(fileURL: file, clock: { clock.now })
        let kept = Set(reopened.storedSamples().map(\.appName))
        XCTAssertFalse(kept.contains("Ancient"))
        XCTAssertTrue(kept.contains("Boundary"))
        XCTAssertTrue(kept.contains("Recent"))
        XCTAssertEqual(reopened.topApps(in: .last12Hours).first?.appName, "Recent")
        XCTAssertEqual(reopened.topApps(in: .last12Hours).map(\.appName).first, "Recent")
        XCTAssertEqual(reopened.topApps(in: .last24Hours).first?.appName, "Day")
        XCTAssertEqual(reopened.topApps(in: .last7Days).first?.appName, "Week")
        XCTAssertEqual(reopened.topApps(in: .last30Days).first?.appName, "Month")
        XCTAssertFalse(reopened.topApps(in: .last30Days, limit: 20).map(\.appName).contains("Ancient"))
        let recent = try XCTUnwrap(reopened.topApps(in: .last12Hours).first { $0.appID == "recent" })
        XCTAssertEqual(recent.cpu, 10, accuracy: 0.000_001)

        let names12 = reopened.topApps(in: .last12Hours, limit: 10).map(\.appName)
        XCTAssertEqual(names12.first, "Recent")
        XCTAssertFalse(names12.contains("Day"))
        XCTAssertFalse(names12.contains("Week"))
        XCTAssertFalse(names12.contains("Month"))
    }

    func testRetentionFollowsTheInjectedClock() throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("appfold-clock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.jsonl")

        let store = HistoryStore(fileURL: file, clock: { clock.now })
        store.record([
            sample("almost", "Almost", clock.now.addingTimeInterval(-(29 * 24 * 3600)), cpu: 3)
        ])
        XCTAssertTrue(store.storedSamples().map(\.appName).contains("Almost"))

        clock.now = clock.now.addingTimeInterval(2 * 24 * 3600)
        let later = HistoryStore(fileURL: file, clock: { clock.now })
        XCTAssertFalse(later.storedSamples().map(\.appName).contains("Almost"))
        let third = HistoryStore(fileURL: file, clock: { clock.now })
        XCTAssertFalse(third.storedSamples().map(\.appName).contains("Almost"))
    }

    func testHotSeriesAlertsAndQuietSeriesDoesNot() {
        let policy = AlertPolicy.standard
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let hot = hotSeries(policy: policy, start: start)
        let alerts = AlertRules.evaluate(series: hot, policy: policy)
        XCTAssertTrue(alerts.contains { if case .sustainedHighCPU = $0 { return $0.appName == "Hot" }; return false })
        XCTAssertTrue(alerts.contains { if case .sustainedMemoryClimb = $0 { return $0.appName == "Hot" }; return false })
        XCTAssertTrue(alerts.contains { if case .heavyDisk = $0 { return $0.appName == "Hot" }; return false })
        XCTAssertTrue(alerts.contains { if case .heavyNetwork = $0 { return $0.appName == "Hot" }; return false })

        let quiet = quietSeries(policy: policy, start: start)
        XCTAssertEqual(AlertRules.evaluate(series: quiet, policy: policy), [])

        let mixed = AlertRules.evaluate(series: hot + quiet, policy: policy)
        XCTAssertTrue(mixed.allSatisfy { $0.appName == "Hot" })
        XCTAssertFalse(mixed.contains { $0.appName == "Quiet" })
    }

    func testHistoryWriterRecordsOneSamplePerAppPerHour() throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("appfold-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(fileURL: directory.appendingPathComponent("history.jsonl"), clock: { clock.now })
        var writer = HistoryWriter(bucketSeconds: 3600)
        let first = snapshot(at: clock.now, cpu: 2)
        writer.write(snapshot: first, store: store)
        writer.write(snapshot: first, store: store)
        XCTAssertEqual(store.storedSamples().count, 1)
        let nextHour = snapshot(at: clock.now.addingTimeInterval(3600), cpu: 4)
        writer.write(snapshot: nextHour, store: store)
        XCTAssertEqual(store.storedSamples().count, 2)
        XCTAssertEqual(store.storedSamples().map(\.cpu), [2, 4])
    }

    func testSingleCPUSpikeDoesNotAlert() {
        let policy = AlertPolicy.standard
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [UsageSample] = []
        for index in 0..<5 {
            let cpu = index == 2 ? policy.highCPUPercent + 10 : 1
            samples.append(UsageSample(
                at: start.addingTimeInterval(Double(index)),
                appID: "spike",
                appName: "Spike",
                cpu: cpu,
                memory: 1_000_000,
                disk: 0,
                network: 0,
                energy: 0
            ))
        }
        XCTAssertEqual(AlertRules.evaluate(series: samples, policy: policy), [])
    }

    func testANewAlertIsAnnouncedOnce() {
        let policy = AlertPolicy.standard
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let alerts = AlertRules.evaluate(series: hotSeries(policy: policy, start: start), policy: policy)
        let first = AlertFeed.fresh(previous: [], alerts: alerts)
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(first.contains { $0.title == "MacMom" && $0.body == "Hot is using high CPU" })
        let again = AlertFeed.fresh(previous: AlertFeed.ids(alerts), alerts: alerts)
        XCTAssertEqual(again, [])
        let cpuOnly = alerts.filter { if case .sustainedHighCPU = $0 { return true }; return false }
        let rest = AlertFeed.fresh(previous: AlertFeed.ids(cpuOnly), alerts: alerts)
        XCTAssertFalse(rest.contains { $0.id.hasPrefix("cpu:") })
        XCTAssertTrue(rest.contains { $0.id.hasPrefix("memory:") })
    }

    func testSmallMemoryClimbDoesNotAlert() {
        let policy = AlertPolicy.standard
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [UsageSample] = []
        for index in 0..<8 {
            samples.append(UsageSample(
                at: start.addingTimeInterval(Double(index) * 2),
                appID: "browser",
                appName: "Browser",
                cpu: 4,
                memory: 800_000_000 + UInt64(index) * 20 * 1024 * 1024,
                disk: 8 * 1024 * 1024,
                network: 0,
                energy: 0
            ))
        }
        XCTAssertEqual(AlertRules.evaluate(series: samples, policy: policy), [])
    }

    func testNotificationCooldownBlocksARepeat() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(AlertFeed.shouldAnnounce(last: now.addingTimeInterval(-10), now: now, cooldown: AlertPolicy.notificationCooldown))
        XCTAssertTrue(AlertFeed.shouldAnnounce(last: now.addingTimeInterval(-31 * 60), now: now, cooldown: AlertPolicy.notificationCooldown))
        XCTAssertTrue(AlertFeed.shouldAnnounce(last: nil, now: now, cooldown: AlertPolicy.notificationCooldown))
    }

    private func hotSeries(policy: AlertPolicy, start: Date) -> [UsageSample] {
        let count = max(policy.sustainedHighCPUCount, policy.sustainedMemoryCount)
        let steps = max(count - 1, 1)
        let climbStep = policy.memoryClimbBytes / UInt64(steps) + 1
        var samples: [UsageSample] = []
        for index in 0..<count {
            samples.append(UsageSample(
                at: start.addingTimeInterval(Double(index)),
                appID: "hot",
                appName: "Hot",
                cpu: policy.highCPUPercent,
                memory: 1_000_000 + climbStep * UInt64(index),
                disk: policy.heavyDiskBytes,
                network: policy.heavyNetworkBytes,
                energy: 1
            ))
        }
        return samples
    }

    private func quietSeries(policy: AlertPolicy, start: Date) -> [UsageSample] {
        let count = max(policy.sustainedHighCPUCount, policy.sustainedMemoryCount)
        var samples: [UsageSample] = []
        for index in 0..<count {
            samples.append(UsageSample(
                at: start.addingTimeInterval(Double(index)),
                appID: "quiet",
                appName: "Quiet",
                cpu: max(0, policy.highCPUPercent - 1),
                memory: 1_000_000,
                disk: policy.heavyDiskBytes > 0 ? policy.heavyDiskBytes - 1 : 0,
                network: policy.heavyNetworkBytes > 0 ? policy.heavyNetworkBytes - 1 : 0,
                energy: 0
            ))
        }
        return samples
    }

    private func snapshot(at: Date, cpu: Double) -> SystemSnapshot {
        let row = AppRow(
            id: "bundle:/Applications/Fixture.app",
            name: "Fixture",
            bundlePath: "/Applications/Fixture.app",
            members: [],
            memoryBytes: 10,
            cpuPercent: cpu,
            energy: 0,
            diskBytes: 3,
            networkBytes: 4
        )
        return SystemSnapshot(
            sampledAt: at,
            systemCPUPercent: cpu,
            systemMemoryUsedBytes: 10,
            systemMemoryTotalBytes: 20,
            systemDiskBytesPerSecond: 0,
            systemNetworkBytesPerSecond: 0,
            apps: [row],
            processCount: 1
        )
    }

    private func sample(_ id: String, _ name: String, _ at: Date, cpu: Double) -> UsageSample {
        UsageSample(at: at, appID: id, appName: name, cpu: cpu, memory: 10, disk: 1, network: 1, energy: 0)
    }
}

final class TestClock {
    var now: Date
    init(now: Date) { self.now = now }
}
