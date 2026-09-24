import AppKit
import AppfoldCore

private let chartSampleLimit = 80

private func chartPeak(_ samples: ArraySlice<Double>) -> Double {
    var peak = 0.0
    for sample in samples where sample.isFinite && sample > peak {
        peak = sample
    }
    return peak
}

private func chartMagnitude(_ sample: Double) -> Double {
    sample.isFinite && sample > 0 ? sample : 0
}

/// Area chart for the CPU, Memory, Disk, Network, GPU, and Battery pages.
final class AreaChartView: NSView {
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }
    /// Fixed top of the plot. 100 for percents, 1 for a fraction of RAM. Nil scales to the series peak.
    var ceiling: Double? { didSet { needsDisplay = true } }
    /// Raw samples, oldest first. Empty draws a calm baseline.
    var values: [Double] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let plot = bounds.insetBy(dx: 4, dy: 4)
        guard plot.width > 2, plot.height > 2 else { return }

        let samples = Array(values.suffix(chartSampleLimit))
        let scale = ChartCeiling.scale(samples: samples, upper: ceiling)
        let points = linePoints(samples, in: plot, scale: scale)

        if samples.contains(where: { $0.isFinite && $0 > 0 }) {
            fillUnderLine(points, in: plot)
        }
        strokeGrid(in: plot)
        strokeLine(points)
    }

    private func linePoints(_ samples: [Double], in plot: NSRect, scale: Double) -> [NSPoint] {
        if samples.count <= 1 {
            let sample = samples.first ?? 0
            let y = plot.minY + plot.height * CGFloat(min(chartMagnitude(sample), scale) / scale)
            return [NSPoint(x: plot.minX, y: y), NSPoint(x: plot.maxX, y: y)]
        }

        var points: [NSPoint] = []
        points.reserveCapacity(samples.count)
        let last = CGFloat(samples.count - 1)
        for (offset, sample) in samples.enumerated() {
            let x = plot.minX + plot.width * CGFloat(offset) / last
            let y = plot.minY + plot.height * CGFloat(min(chartMagnitude(sample), scale) / scale)
            points.append(NSPoint(x: x, y: y))
        }
        return points
    }

    private func fillUnderLine(_ points: [NSPoint], in plot: NSRect) {
        guard let first = points.first, let last = points.last else { return }
        guard let gradient = NSGradient(colors: [
            color.withAlphaComponent(0.05),
            color.withAlphaComponent(0.40)
        ]) else { return }

        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: first.x, y: plot.minY))
        for point in points {
            fill.line(to: point)
        }
        fill.line(to: NSPoint(x: last.x, y: plot.minY))
        fill.close()

        NSGraphicsContext.saveGraphicsState()
        fill.addClip()
        // The series max is the top of the plot, so the wash is ~0.28 there and ~0.02 on the baseline.
        gradient.draw(
            from: NSPoint(x: plot.midX, y: plot.minY),
            to: NSPoint(x: plot.midX, y: plot.maxY),
            options: []
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func strokeGrid(in plot: NSRect) {
        let grid = NSBezierPath()
        grid.lineWidth = 1
        for index in 0..<4 {
            let y = plot.minY + plot.height * CGFloat(index) / 3
            grid.move(to: NSPoint(x: plot.minX, y: y))
            grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        NSColor.black.withAlphaComponent(0.06).setStroke()
        grid.stroke()
    }

    private func strokeLine(_ points: [NSPoint]) {
        guard let first = points.first else { return }
        let line = NSBezierPath()
        line.lineWidth = 2
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        line.move(to: first)
        for point in points.dropFirst() {
            line.line(to: point)
        }
        color.setStroke()
        line.stroke()
    }
}

/// Overview mini bars (CPU, Memory, Disk, Network, Battery). Not an area chart.
final class SparkBarsView: NSView {
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }
    /// Fixed top of the band. 100 for percents, 1 for a fraction of RAM. Nil scales to the series peak.
    var ceiling: Double? { didSet { needsDisplay = true } }
    /// Vertical bars like the Overview cards. Oldest first.
    var values: [Double] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let band = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        color.withAlphaComponent(0.13).setFill()
        band.fill()

        let rect = bounds.insetBy(dx: 6, dy: 6)
        let samples = Array(values.suffix(chartSampleLimit))
        let count = samples.count
        guard count > 0, rect.width > 2, rect.height > 2 else { return }

        let gap: CGFloat = 2
        let barWidth = (rect.width - gap * CGFloat(max(count - 1, 0))) / CGFloat(count)
        guard barWidth > 0.6 else { return }

        let scale = ChartCeiling.scale(samples: samples, upper: ceiling)
        var x = rect.minX
        let bars = NSBezierPath()
        for sample in samples {
            let height = max(2, rect.height * CGFloat(min(chartMagnitude(sample), scale) / scale))
            let bar = NSRect(x: x, y: rect.minY, width: barWidth, height: min(height, rect.height))
            bars.appendRoundedRect(bar, xRadius: min(1.5, barWidth / 2), yRadius: min(1.5, barWidth / 2))
            x += barWidth + gap
        }
        color.withAlphaComponent(0.92).setFill()
        bars.fill()
    }
}

/// Ring chart for the Overview breakdown cards.
final class DonutChartView: NSView {
    struct Slice {
        var fraction: CGFloat // 0...1, slices should sum to about 1
        var color: NSColor
    }

    var slices: [Slice] = [] { didSet { needsDisplay = true } }
    var centerTitle: String = "" { didSet { needsDisplay = true } }
    var centerSubtitle: String = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let thickness: CGFloat = 12
        guard side > thickness + 4 else { return }

        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = side / 2 - thickness / 2 - 0.5
        drawRing(center: center, radius: radius, thickness: thickness)
        drawCenterText(around: center, maxWidth: max(0, (radius - thickness / 2) * 2 - 4))
    }

    private func drawRing(center: NSPoint, radius: CGFloat, thickness: CGFloat) {
        var parts: [(NSColor, CGFloat)] = []
        parts.reserveCapacity(slices.count)
        for slice in slices where slice.fraction.isFinite && slice.fraction > 0 {
            parts.append((slice.color, min(slice.fraction, 1) * 360))
        }
        guard !parts.isEmpty else {
            strokeArc(center: center, radius: radius, thickness: thickness, start: 0, sweep: 360, color: NSColor.systemGray.withAlphaComponent(0.28), rounded: false)
            return
        }

        // 2pt gap. Round caps stick out by half the stroke, so the unstroked
        // arc is longer than 2pt when caps are on. The card shows through.
        let separate = parts.count > 1
        let gapDegrees = separate ? (2 / radius) * 180 / .pi : 0
        let capDegrees = (thickness / radius) * 180 / .pi
        var cursor: CGFloat = 90

        for (color, sweep) in parts {
            let rounded = separate && sweep > gapDegrees + capDegrees + 1
            let pad: CGFloat
            if !separate {
                pad = 0
            } else if rounded {
                pad = gapDegrees + capDegrees
            } else {
                pad = min(gapDegrees, max(0, sweep - 0.4))
            }
            let drawSweep = sweep - pad
            if drawSweep > 0.2 {
                let roundCaps = drawSweep < 359.5 && (!separate || rounded)
                strokeArc(
                    center: center,
                    radius: radius,
                    thickness: thickness,
                    start: cursor - pad / 2,
                    sweep: drawSweep,
                    color: color,
                    rounded: roundCaps
                )
            }
            cursor -= sweep
        }
    }

    private func strokeArc(center: NSPoint, radius: CGFloat, thickness: CGFloat, start: CGFloat, sweep: CGFloat, color: NSColor, rounded: Bool) {
        let path = NSBezierPath()
        path.lineWidth = thickness
        path.lineCapStyle = rounded ? .round : .butt
        if sweep >= 359.9 {
            path.appendOval(in: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        } else {
            path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
        }
        color.setStroke()
        path.stroke()
    }

    private func drawCenterText(around center: NSPoint, maxWidth: CGFloat) {
        if centerTitle.isEmpty && centerSubtitle.isEmpty { return }
        guard maxWidth > 4 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        let titleHeight = centerTitle.isEmpty ? 0 : ceil((centerTitle as NSString).size(withAttributes: titleAttrs).height)
        let subtitleHeight = centerSubtitle.isEmpty ? 0 : ceil((centerSubtitle as NSString).size(withAttributes: subtitleAttrs).height)
        let gap: CGFloat = titleHeight > 0 && subtitleHeight > 0 ? 1 : 0
        var y = center.y - (titleHeight + gap + subtitleHeight) / 2

        if subtitleHeight > 0 {
            let rect = NSRect(x: center.x - maxWidth / 2, y: y, width: maxWidth, height: subtitleHeight)
            (centerSubtitle as NSString).draw(in: rect, withAttributes: subtitleAttrs)
            y += subtitleHeight + gap
        }
        if titleHeight > 0 {
            let rect = NSRect(x: center.x - maxWidth / 2, y: y, width: maxWidth, height: titleHeight)
            (centerTitle as NSString).draw(in: rect, withAttributes: titleAttrs)
        }
    }
}

/// Thin capsule meter. Callers set the view height (~4pt); the bar fills that height.
final class MeterBar: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } } // 0...1
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        color.withAlphaComponent(0.15).setFill()
        capsule(in: bounds).fill()

        let raw = fraction.isFinite ? fraction : 0
        let clamped = min(max(raw, 0), 1)
        let fillWidth = bounds.width * clamped
        guard fillWidth > 0 else { return }

        let fillRect = NSRect(x: bounds.minX, y: bounds.minY, width: fillWidth, height: bounds.height)
        color.setFill()
        capsule(in: fillRect).fill()
    }

    private func capsule(in rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}
