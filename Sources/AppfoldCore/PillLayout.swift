import CoreGraphics

/// Sizing for the dashboard tab pill. Drawing uses these widths and never allots less than the measured title.
public enum PillLayout {
    public static let titles = ["Overview", "CPU", "Memory", "Disk", "Network", "GPU", "Battery", "Projects"]
    public static let titlePointSize: CGFloat = 13
    public static let iconSide: CGFloat = 14
    public static let iconGap: CGFloat = 5
    public static let itemInsetX: CGFloat = 10
    public static let textSlack: CGFloat = 6
    public static let spacing: CGFloat = 2
    public static let padX: CGFloat = 6
    public static let minimumContentWidth: CGFloat = 1080

    /// Width of one tab, including its icon and padding. `textWidth` is the measured title string.
    public static func itemWidth(textWidth: CGFloat) -> CGFloat {
        itemInsetX + iconSide + iconGap + ceil(max(textWidth, 0)) + textSlack + itemInsetX
    }

    /// Text width given to each title. Always at least the measured string, at any content width.
    public static func allottedTextWidths(textWidths: [CGFloat], contentWidth: CGFloat) -> [CGFloat] {
        _ = contentWidth
        return textWidths.map { ceil(max($0, 0)) }
    }

    public static func barWidth(textWidths: [CGFloat]) -> CGFloat {
        let allotted = allottedTextWidths(textWidths: textWidths, contentWidth: .greatestFiniteMagnitude)
        let items = allotted.reduce(CGFloat(0)) { $0 + itemWidth(textWidth: $1) }
        let gaps = spacing * CGFloat(max(allotted.count - 1, 0))
        return items + gaps + padX * 2
    }

    /// Window content width that keeps every title on one line. Narrower content is refused.
    public static func windowMinimumWidth(textWidths: [CGFloat]) -> CGFloat {
        max(minimumContentWidth, barWidth(textWidths: textWidths) + 48)
    }
}
