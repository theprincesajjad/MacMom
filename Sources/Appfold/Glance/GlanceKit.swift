import AppKit
import AppfoldCore

/// Dark glance palette and drawing pieces shared by the menu-bar panel.
/// Pages format measured `DashState` values. They do not sample or invent readings.
enum GlanceTheme {
    static let canvas = NSColor(srgbRed: 0.102, green: 0.110, blue: 0.129, alpha: 1)
    static let card = NSColor(srgbRed: 0.165, green: 0.173, blue: 0.196, alpha: 1)
    static let control = NSColor(srgbRed: 0.196, green: 0.204, blue: 0.231, alpha: 1)
    static let primary = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    static let secondary = NSColor(srgbRed: 0.62, green: 0.64, blue: 0.68, alpha: 1)
    static let tertiary = NSColor(srgbRed: 0.45, green: 0.47, blue: 0.51, alpha: 1)
    static let hairline = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
    static let track = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
    static let portFill = NSColor(srgbRed: 0.18, green: 0.36, blue: 0.26, alpha: 1)
    static let portText = NSColor(srgbRed: 0.45, green: 0.86, blue: 0.58, alpha: 1)
    static let normalFill = NSColor(srgbRed: 0.16, green: 0.36, blue: 0.24, alpha: 1)
    static let normalText = NSColor(srgbRed: 0.45, green: 0.86, blue: 0.55, alpha: 1)
    static let highText = NSColor(srgbRed: 0.95, green: 0.72, blue: 0.28, alpha: 1)

    static let cardRadius: CGFloat = 18
    static let panelRadius: CGFloat = 26
    static let inset: CGFloat = 14

    static func accent(_ tab: DashTab) -> NSColor {
        switch tab {
        case .overview, .cpu:
            return NSColor(srgbRed: 0.36, green: 0.58, blue: 0.98, alpha: 1)
        case .memory:
            return NSColor(srgbRed: 0.62, green: 0.55, blue: 0.95, alpha: 1)
        case .disk:
            return NSColor(srgbRed: 0.92, green: 0.67, blue: 0.22, alpha: 1)
        case .network:
            return NSColor(srgbRed: 0.29, green: 0.78, blue: 0.55, alpha: 1)
        case .gpu:
            return NSColor(srgbRed: 0.90, green: 0.38, blue: 0.58, alpha: 1)
        case .battery:
            return NSColor(srgbRed: 0.25, green: 0.78, blue: 0.40, alpha: 1)
        case .projects:
            return NSColor(srgbRed: 0.95, green: 0.48, blue: 0.22, alpha: 1)
        }
    }

    static func symbolName(_ tab: DashTab) -> String {
        switch tab {
        case .overview: return "circle.grid.2x2.fill"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "globe"
        case .gpu: return "square.stack.3d.up.fill"
        case .battery: return "battery.100"
        case .projects: return "folder.fill"
        }
    }

    static func symbol(_ name: String, pointSize: CGFloat, tint: NSColor) -> NSImage {
        DashTheme.symbol(name, pointSize: pointSize, tint: tint)
    }
}

enum GlanceMemoryLevel {
    case normal
    case high
    case critical

    static func level(used: UInt64, total: UInt64) -> GlanceMemoryLevel {
        guard total > 0 else { return .normal }
        let fraction = Double(used) / Double(total)
        if fraction < 0.80 { return .normal }
        if fraction < 0.92 { return .high }
        return .critical
    }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var textColor: NSColor {
        switch self {
        case .normal: return GlanceTheme.normalText
        case .high: return GlanceTheme.highText
        case .critical: return NSColor(srgbRed: 0.95, green: 0.42, blue: 0.42, alpha: 1)
        }
    }

    var fillColor: NSColor {
        switch self {
        case .normal: return GlanceTheme.normalFill
        case .high: return NSColor(srgbRed: 0.40, green: 0.30, blue: 0.12, alpha: 1)
        case .critical: return NSColor(srgbRed: 0.42, green: 0.16, blue: 0.16, alpha: 1)
        }
    }
}

enum GlanceHost {
    /// Marketing name such as "Apple M2 Max", or an empty string when the OS does not publish one.
    static let modelName: String = {
        let brand = sysctlString("machdep.cpu.brand_string")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if brand.isEmpty { return "" }
        if brand.localizedCaseInsensitiveContains("apple processor") { return "" }
        return brand
    }()

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}

enum GlanceFormat {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func percentHero(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if abs(value) >= 10 { return decimal(value, digits: 0) }
        return decimal(value, digits: 1)
    }

    static func percentApp(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return decimal(value, digits: 1) + "%"
    }

    static func percentWhole(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return decimal(value, digits: 0) + "%"
    }

    static func load(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return decimal(value, digits: 2)
    }

    /// Number and unit for a byte count. Gigabytes use two decimals. Megabytes are whole numbers.
    static func bytePair(_ bytes: UInt64) -> (number: String, unit: String) {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return (decimal(gb, digits: 2), "GB")
        }
        let mb = Double(bytes) / 1_048_576
        if mb >= 10 {
            return (decimal(mb, digits: 0), "MB")
        }
        if mb >= 1 {
            return (decimal(mb, digits: 1), "MB")
        }
        let kb = Double(bytes) / 1024
        if kb >= 1 {
            return (decimal(kb, digits: 0), "kB")
        }
        return ("0", "MB")
    }

    static func byteText(_ bytes: UInt64) -> String {
        let pair = bytePair(bytes)
        return pair.number + " " + pair.unit
    }

    static func diskNumber(_ bytes: UInt64) -> String {
        decimal(Double(bytes) / 1_073_741_824, digits: 2)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
        let kb = bytesPerSecond / 1024
        if kb < 1024 {
            if kb < 10 { return decimal(kb, digits: 1) + " kB/s" }
            return decimal(kb, digits: 0) + " kB/s"
        }
        let mb = kb / 1024
        if mb < 100 { return decimal(mb, digits: 1) + " MB/s" }
        return decimal(mb, digits: 0) + " MB/s"
    }

    static func sessionAmount(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return decimal(gb, digits: 1) + " GB" }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return decimal(mb, digits: 0) + " MB" }
        return "0 MB"
    }

    static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value < 1 { return decimal(value * 1000, digits: 0) + " mW" }
        return decimal(value, digits: 1) + " W"
    }

    /// "2h 06m left". Nil when the OS did not publish a time.
    static func remaining(_ minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return "—" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return String(format: "%dh %02dm left", hours, mins)
        }
        return "\(mins)m left"
    }

    /// "3d 4h", "4h 12m", or "12m". Caller adds the "Up " prefix.
    static func uptime(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "—" }
        let seconds = Int(interval)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func fraction(_ part: UInt64, of total: UInt64) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(1, Double(part) / Double(total)))
    }

    private static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: posix, value)
    }
}

func glanceColumn(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    for view in views {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    return stack
}

func glanceRow(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
    let row = NSStackView(views: views)
    row.orientation = .horizontal
    row.distribution = .fillEqually
    row.alignment = .top
    row.spacing = spacing
    row.translatesAutoresizingMaskIntoConstraints = false
    return row
}

func glanceLabel(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: string)
    field.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    field.maximumNumberOfLines = 1
    field.cell?.truncatesLastVisibleLine = true
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
}

func glanceEyebrow(_ text: String) -> NSTextField {
    let field = NSTextField(labelWithString: "")
    field.attributedStringValue = glanceTracked(text.uppercased(), size: 12, weight: .semibold, color: GlanceTheme.secondary, kern: 1.3)
    field.lineBreakMode = .byTruncatingTail
    field.maximumNumberOfLines = 1
    return field
}

func glanceTracked(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: kern
    ])
}

func glanceHairline() -> NSView {
    let line = NSView()
    line.wantsLayer = true
    line.layer?.backgroundColor = GlanceTheme.hairline.cgColor
    line.translatesAutoresizingMaskIntoConstraints = false
    line.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return line
}

final class GlanceCard: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = GlanceTheme.card.cgColor
        layer?.cornerRadius = GlanceTheme.cardRadius
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = GlanceTheme.card.cgColor
    }
}

/// Area chart scaled to the series maximum. No grid. Empty or flat series still draw a calm line.
final class GlanceAreaChart: NSView {
    var color: NSColor = GlanceTheme.accent(.cpu) { didSet { needsDisplay = true } }
    var values: [Double] = [] { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let plot = bounds.insetBy(dx: 1, dy: 2)
        guard plot.width > 2, plot.height > 2 else { return }
        let samples = Array(values.suffix(60))
        let peak = samples.reduce(0.0) { partial, sample in
            sample.isFinite && sample > partial ? sample : partial
        }
        let scale = peak > 0 ? peak : 1
        let points = linePoints(samples, in: plot, scale: scale)
        fill(points, in: plot)
        stroke(points)
    }

    private func linePoints(_ samples: [Double], in plot: NSRect, scale: Double) -> [NSPoint] {
        if samples.count <= 1 {
            let sample = samples.first ?? 0
            let y = plot.minY + plot.height * CGFloat(magnitude(sample) / scale)
            return [NSPoint(x: plot.minX, y: y), NSPoint(x: plot.maxX, y: y)]
        }
        let last = CGFloat(samples.count - 1)
        return samples.enumerated().map { offset, sample in
            NSPoint(
                x: plot.minX + plot.width * CGFloat(offset) / last,
                y: plot.minY + plot.height * CGFloat(magnitude(sample) / scale)
            )
        }
    }

    private func magnitude(_ sample: Double) -> Double {
        sample.isFinite && sample > 0 ? sample : 0
    }

    private func fill(_ points: [NSPoint], in plot: NSRect) {
        guard let first = points.first, let last = points.last else { return }
        guard let gradient = NSGradient(colors: [
            color.withAlphaComponent(0.05),
            color.withAlphaComponent(0.55)
        ]) else { return }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: first.x, y: plot.minY))
        for point in points { path.line(to: point) }
        path.line(to: NSPoint(x: last.x, y: plot.minY))
        path.close()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        gradient.draw(from: NSPoint(x: plot.midX, y: plot.minY), to: NSPoint(x: plot.midX, y: plot.maxY), options: [])
        NSGraphicsContext.restoreGraphicsState()
    }

    private func stroke(_ points: [NSPoint]) {
        guard let first = points.first else { return }
        let line = NSBezierPath()
        line.lineWidth = 1.6
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        line.move(to: first)
        for point in points.dropFirst() { line.line(to: point) }
        color.setStroke()
        line.stroke()
    }
}

/// Single capsule meter. `fraction` is 0...1.
final class GlanceMeter: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var fillColor: NSColor = GlanceTheme.accent(.cpu) { didSet { needsDisplay = true } }
    var trackColor: NSColor = GlanceTheme.track { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        trackColor.setFill()
        track.fill()
        let width = max(bounds.height, bounds.width * min(max(fraction, 0), 1))
        let fillRect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        fillColor.setFill()
        fill.fill()
    }
}

/// Capsule split into colored segments. Fractions should sum to at most 1. The remainder is the track.
final class GlanceSegments: NSView {
    var parts: [(CGFloat, NSColor)] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSGraphicsContext.saveGraphicsState()
        capsule.addClip()
        GlanceTheme.track.setFill()
        bounds.fill()
        var x: CGFloat = 0
        for (fraction, color) in parts {
            let width = bounds.width * min(max(fraction, 0), 1)
            color.setFill()
            NSRect(x: x, y: 0, width: width, height: bounds.height).fill()
            x += width
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class GlanceAppRow: NSView {
    private let iconView = NSImageView()
    private let nameField = glanceLabel("", size: 14, weight: .medium, color: GlanceTheme.primary)
    private let valueField = glanceLabel("—", size: 13, weight: .medium, color: GlanceTheme.primary)
    private let meter = GlanceMeter()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 5
        iconView.layer?.masksToBounds = true
        meter.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameField.translatesAutoresizingMaskIntoConstraints = false
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.alignment = .right
        valueField.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueField.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(iconView)
        addSubview(nameField)
        addSubview(meter)
        addSubview(valueField)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            meter.leadingAnchor.constraint(greaterThanOrEqualTo: nameField.trailingAnchor, constant: 8),
            meter.centerYAnchor.constraint(equalTo: centerYAnchor),
            meter.widthAnchor.constraint(equalToConstant: 92),
            meter.heightAnchor.constraint(equalToConstant: 6),
            valueField.leadingAnchor.constraint(equalTo: meter.trailingAnchor, constant: 10),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.widthAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(icon: NSImage?, name: String, value: String, fraction: CGFloat, tint: NSColor) {
        nameField.stringValue = name
        valueField.stringValue = value
        meter.fraction = fraction
        meter.fillColor = tint
        if let icon {
            iconView.image = icon
            iconView.isHidden = false
        } else {
            iconView.image = GlanceTheme.symbol("app", pointSize: 12, tint: GlanceTheme.secondary)
            iconView.isHidden = false
        }
    }
}

/// Rounded footer control. `circular` is the gear. Otherwise a wide label button.
final class GlanceButton: NSView {
    var onClick: (() -> Void)?
    private let titleField = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var armed = false
    private let circular: Bool

    init(title: String, symbol: String, circular: Bool = false) {
        self.circular = circular
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = GlanceTheme.control.cgColor
        layer?.cornerRadius = circular ? 22 : 14
        iconView.image = GlanceTheme.symbol(symbol, pointSize: circular ? 16 : 14, tint: GlanceTheme.primary)
        iconView.imageScaling = .scaleProportionallyDown
        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: 15, weight: .medium)
        titleField.textColor = GlanceTheme.primary
        titleField.alignment = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleField.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: circular ? 18 : 16).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: circular ? 18 : 16).isActive = true
        if circular {
            addSubview(iconView)
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: 44),
                heightAnchor.constraint(equalToConstant: 44),
                iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            return
        }
        let row = NSStackView(views: [iconView, titleField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        if circular {
            layer?.cornerRadius = bounds.height / 2
        }
    }

    override func mouseDown(with event: NSEvent) {
        armed = bounds.contains(convert(event.locationInWindow, from: nil))
        layer?.backgroundColor = GlanceTheme.card.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = GlanceTheme.control.cgColor
        if armed, bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
        armed = false
    }
}

final class GlanceClick: NSClickGestureRecognizer {
    var handler: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
    }

    convenience init(handler: @escaping () -> Void) {
        self.init(target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(fire)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func fire() {
        handler?()
    }
}
