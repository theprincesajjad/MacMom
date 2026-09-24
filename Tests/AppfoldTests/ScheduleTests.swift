import AppfoldCore
import XCTest

final class ScheduleTests: XCTestCase {
    func testClosedWindowSamplesAtLeastFiveSecondsApartAcrossTwentySeconds() {
        var schedule = SampleSchedule(windowVisible: false)
        let start = Date(timeIntervalSince1970: 10_000)
        var fired: [Date] = []
        for step in 0...40 {
            let now = start.addingTimeInterval(Double(step) * 0.5)
            if schedule.shouldSample(at: now) {
                fired.append(now)
            }
        }
        XCTAssertGreaterThanOrEqual(Double(40) * 0.5, 20)
        XCTAssertGreaterThanOrEqual(SampleSchedule.closedInterval, 5)
        XCTAssertGreaterThanOrEqual(fired.count, 4)
        for pair in zip(fired, fired.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.timeIntervalSince(pair.0), 5 - 0.001)
        }
        XCTAssertEqual(fired.first, start)
        XCTAssertTrue(fired.contains(start.addingTimeInterval(5)))
        XCTAssertFalse(fired.contains(start.addingTimeInterval(2.5)))
        XCTAssertFalse(fired.contains(start.addingTimeInterval(4.5)))
    }

    func testOpenWindowMaySampleMoreOftenThanTheClosedInterval() {
        var schedule = SampleSchedule(windowVisible: true)
        let start = Date(timeIntervalSince1970: 20_000)
        var fired: [Date] = []
        for step in 0...40 {
            let now = start.addingTimeInterval(Double(step) * 0.5)
            if schedule.shouldSample(at: now) {
                fired.append(now)
            }
        }
        XCTAssertLessThan(SampleSchedule.openInterval, SampleSchedule.closedInterval)
        XCTAssertGreaterThanOrEqual(fired.count, 2)
        var sawShorterThanClosed = false
        for pair in zip(fired, fired.dropFirst()) {
            let gap = pair.1.timeIntervalSince(pair.0)
            XCTAssertGreaterThanOrEqual(gap, SampleSchedule.openInterval - 0.001)
            if gap < SampleSchedule.closedInterval {
                sawShorterThanClosed = true
            }
        }
        XCTAssertTrue(sawShorterThanClosed)
        XCTAssertGreaterThanOrEqual(fired.last!.timeIntervalSince(start), 20)
    }

    func testOpeningTheWindowUsesTheShorterInterval() {
        var schedule = SampleSchedule(windowVisible: false)
        let start = Date(timeIntervalSince1970: 30_000)
        XCTAssertTrue(schedule.shouldSample(at: start))
        XCTAssertFalse(schedule.shouldSample(at: start.addingTimeInterval(2)))
        schedule.windowVisible = true
        XCTAssertTrue(schedule.shouldSample(at: start.addingTimeInterval(2)))
    }

    func testCPUAndHostDeltasMatchTheCountersTheyWereGiven() {
        XCTAssertEqual(CPUDelta.percent(previousNS: 0, currentNS: 1_000_000_000, elapsed: 1), 100, accuracy: 0.001)
        XCTAssertEqual(CPUDelta.percent(previousNS: nil, currentNS: 1_000_000_000, elapsed: 1), 0)
        XCTAssertEqual(CPUDelta.percent(previousNS: 10, currentNS: 10, elapsed: 1), 0)
        XCTAssertEqual(CounterDelta.bytes(previous: 5, current: 8), 3)
        XCTAssertEqual(CounterDelta.bytes(previous: nil, current: 8), 0)

        let previous = HostCPUTicks(user: 10, system: 5, idle: 85, nice: 0)
        let current = HostCPUTicks(user: 20, system: 10, idle: 165, nice: 5)
        // busy delta 20, total delta 100
        XCTAssertEqual(HostCPU.percent(previous: previous, current: current), 20, accuracy: 0.001)
        XCTAssertEqual(HostCPU.percent(previous: nil, current: current), 0)
    }
}
