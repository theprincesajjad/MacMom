import AppfoldCore
import AppKit
import XCTest

final class PillLayoutTests: XCTestCase {
    func testReferenceTitlesKeepTheirFullWidthAtTheDefaultWindowAndWhenNarrower() {
        let font = NSFont.systemFont(ofSize: PillLayout.titlePointSize, weight: .medium)
        let textWidths = PillLayout.titles.map { title in
            (title as NSString).size(withAttributes: [.font: font]).width
        }
        XCTAssertEqual(PillLayout.titles, ["Overview", "CPU", "Memory", "Disk", "Network", "GPU", "Battery", "Projects"])

        let atDefault = PillLayout.allottedTextWidths(textWidths: textWidths, contentWidth: 1080)
        XCTAssertEqual(atDefault.count, textWidths.count)
        for (title, allotted, textWidth) in zip3(PillLayout.titles, atDefault, textWidths) {
            XCTAssertGreaterThanOrEqual(allotted, ceil(textWidth), title)
            XCTAssertGreaterThanOrEqual(PillLayout.itemWidth(textWidth: allotted), PillLayout.itemWidth(textWidth: textWidth), title)
        }

        let narrow = PillLayout.allottedTextWidths(textWidths: textWidths, contentWidth: 720)
        for (allotted, textWidth) in zip(narrow, textWidths) {
            XCTAssertGreaterThanOrEqual(allotted, ceil(textWidth))
        }
        XCTAssertGreaterThanOrEqual(
            PillLayout.windowMinimumWidth(textWidths: textWidths),
            PillLayout.barWidth(textWidths: textWidths)
        )
        XCTAssertGreaterThanOrEqual(PillLayout.windowMinimumWidth(textWidths: textWidths), 1080)
    }
}

private func zip3<A, B, C>(_ a: [A], _ b: [B], _ c: [C]) -> [(A, B, C)] {
    zip(a, zip(b, c)).map { ($0, $1.0, $1.1) }
}
