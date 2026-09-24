import AppfoldCore
import XCTest

final class HostMemoryTests: XCTestCase {
    func testProcessFootprintAboveRAMDoesNotBecomeTheAppFigure() {
        let footprint: UInt64 = 40_000_000_000
        let parts = HostMemory.breakdown(
            internalBytes: 4_000_000_000,
            wiredBytes: 2_000_000_000,
            compressedBytes: 1_000_000_000,
            externalBytes: 3_000_000_000,
            freeBytes: 6_000_000_000,
            swapBytes: 100,
            totalBytes: 16_000_000_000,
            processFootprintSum: footprint
        )
        XCTAssertEqual(parts.appBytes, 4_000_000_000)
        XCTAssertLessThanOrEqual(parts.appBytes, parts.totalBytes)
        XCTAssertNotEqual(parts.appBytes, footprint)
        XCTAssertEqual(parts.inUseBytes, parts.appBytes + parts.wiredBytes + parts.compressedBytes)
        XCTAssertEqual(parts.cachedBytes, 3_000_000_000)
        XCTAssertEqual(parts.freeBytes, 6_000_000_000)
    }

    func testPercentChartsUseAFixedCeilingAndShortSeriesStayShort() {
        XCTAssertEqual(ChartCeiling.scale(samples: [56, 56], upper: 100), 100)
        XCTAssertEqual(ChartCeiling.scale(samples: [0.7], upper: 1), 1)
        XCTAssertEqual(ChartCeiling.scale(samples: [10, 40], upper: nil), 40)
        XCTAssertEqual(SeriesWindow.window([1, 2]), [1, 2])
    }

    func testQuietServerStillHasAStatus() {
        XCTAssertEqual(ProjectStatus.resolve(cpuPercent: 0.4, idleMinutes: nil, uptime: nil), .quiet)
        XCTAssertEqual(ProjectStatus.resolve(cpuPercent: 9, idleMinutes: nil, uptime: 10), .working)
        XCTAssertEqual(ProjectStatus.resolve(cpuPercent: 0.2, idleMinutes: 45, uptime: 3_600), .idle(minutes: 45))
        XCTAssertEqual(ProjectStatus.resolve(cpuPercent: 0.2, idleMinutes: nil, uptime: 7_200), .uptime(seconds: 7_200))
    }
}
