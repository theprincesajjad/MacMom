import AppKit
import AppfoldCore

private let dash = "—"

final class DashboardRoot: NSView {
    var onSelectTab: ((DashTab) -> Void)?
    var onSelectApp: ((String) -> Void)?
    var onStopProjects: (([Int32]) -> Void)?
    /// App id and whether the quit is forced. The window asks before anything is signaled.
    var onQuitApp: ((String, Bool) -> Void)?
    /// One process from a list, and whether the quit is forced.
    var onQuitProcess: ((Int32, Bool) -> Void)?
    /// Project name, its pids, and whether the quit is forced.
    var onQuitProject: ((String, [Int32], Bool) -> Void)?

    private let pill = PillBar(frame: .zero)
    private let alertStrip = DashAlertStrip()
    private let scroll = NSScrollView(frame: .zero)
    private var documentWidth: NSLayoutConstraint?
    private var lastState: DashState?
    private var builtKey: String?
    private var shown: Shown?

    var selectedTab: DashTab = .overview {
        didSet {
            guard oldValue != selectedTab else { return }
            if pill.selected != selectedTab {
                pill.selected = selectedTab
            }
            if let lastState {
                render(lastState)
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DashTheme.canvas.cgColor

        let clip = TopClipView()
        clip.drawsBackground = false
        scroll.contentView = clip
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.setContentHuggingPriority(.required, for: .vertical)
        pill.setContentCompressionResistancePriority(.required, for: .vertical)
        pill.onChange = { [weak self] tab in
            guard let self, tab != self.selectedTab else { return }
            self.selectedTab = tab
            self.onSelectTab?(tab)
        }

        alertStrip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)
        addSubview(alertStrip)
        addSubview(scroll)

        let pillWidth = pill.widthAnchor.constraint(equalToConstant: PillBar.barWidth())
        pillWidth.priority = .required
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.heightAnchor.constraint(equalToConstant: 40),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 78),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            pillWidth,
            alertStrip.topAnchor.constraint(equalTo: pill.bottomAnchor, constant: 8),
            alertStrip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            alertStrip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: alertStrip.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = DashTheme.canvas.cgColor
    }

    func render(_ state: DashState) {
        lastState = state
        if pill.selected != selectedTab {
            pill.selected = selectedTab
        }
        let key = pageKey(selectedTab, state)
        if key != builtKey || shown == nil {
            builtKey = key
            install(page(for: selectedTab, state: state))
        }
        alertStrip.set(state.alerts)
        shown?.update(state)
    }

    private func pageKey(_ tab: DashTab, _ state: DashState) -> String {
        switch tab {
        case .memory:
            return "memory-\(state.memoryTotal)"
        case .gpu:
            return "gpu-\(state.gpuName)"
        case .battery:
            return "battery-\(state.hasBattery)-\(state.onBattery)"
        default:
            return "tab-\(tab.rawValue)"
        }
    }

    private func page(for tab: DashTab, state: DashState) -> Shown {
        switch tab {
        case .overview:
            let page = OverviewPage()
            page.onOpen = { [weak self] next in
                guard let self, next != self.selectedTab else { return }
                self.selectedTab = next
                self.onSelectTab?(next)
            }
            return .overview(page)
        case .projects:
            let page = ProjectsPage()
            page.onStop = { [weak self, weak page] in
                self?.onStopProjects?(page?.idlePIDs ?? [])
            }
            page.onQuitProject = { [weak self] name, pids, force in
                self?.onQuitProject?(name, pids, force)
            }
            return .projects(page)
        default:
            let page = MetricPage(tab: tab, state: state)
            page.owner = self
            return .metric(page)
        }
    }

    private func install(_ shown: Shown) {
        self.shown = shown
        let document = PageCanvas()
        let content = shown.view
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16),
        ])
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        documentWidth?.isActive = false
        // Clip width, not the document's intrinsic width, so cards stretch with the window.
        let width = document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        width.isActive = true
        documentWidth = width
        scroll.contentView.scroll(to: NSPoint.zero)
    }
}

private final class DashAlertStrip: NSView {
    private let stack = NSStackView()
    private var heightLock: NSLayoutConstraint?
    private var body: [NSLayoutConstraint] = []
    private var shown: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10).cgColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let lock = heightAnchor.constraint(equalToConstant: 0)
        lock.isActive = true
        heightLock = lock
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(_ messages: [String]) {
        if messages == shown { return }
        shown = messages
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        NSLayoutConstraint.deactivate(body)
        body = []
        guard !messages.isEmpty else {
            isHidden = true
            heightLock?.isActive = true
            return
        }
        heightLock?.isActive = false
        isHidden = false
        let visible = messages.prefix(4)
        for message in visible {
            let label = textLabel(message, size: 13, weight: .medium, color: NSColor.systemRed)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -28).isActive = true
        }
        if messages.count > visible.count {
            let more = textLabel("+\(messages.count - visible.count) more", size: 12, weight: .medium, color: DashTheme.secondaryText)
            stack.addArrangedSubview(more)
        }
        body = [
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        NSLayoutConstraint.activate(body)
    }
}

private extension DashboardRoot {
    enum Shown {
        case overview(OverviewPage)
        case metric(MetricPage)
        case projects(ProjectsPage)

        var view: NSView {
            switch self {
            case .overview(let page): return page.view
            case .metric(let page): return page.view
            case .projects(let page): return page.view
            }
        }

        func update(_ state: DashState) {
            switch self {
            case .overview(let page): page.update(state)
            case .metric(let page): page.update(state)
            case .projects(let page): page.update(state)
            }
        }
    }
}

private final class TopClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class PageCanvas: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Format

private enum Format {
    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return dash }
        if abs(value) > 10 {
            return decimal(value, digits: 0) + "%"
        }
        return decimal(value, digits: 1) + "%"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return dash }
        return percent(value)
    }

    static func bytes(_ value: Double) -> String {
        guard value.isFinite else { return dash }
        let sign = value < 0 ? "-" : ""
        var magnitude = abs(value)
        if magnitude < 1024 {
            return sign + decimal(magnitude, digits: 0) + " B"
        }
        magnitude /= 1024
        if magnitude < 1024 {
            return sign + decimal(magnitude, digits: 1) + " KB"
        }
        magnitude /= 1024
        if magnitude < 1024 {
            return sign + decimal(magnitude, digits: 1) + " MB"
        }
        magnitude /= 1024
        return sign + decimal(magnitude, digits: 1) + " GB"
    }

    static func bytes(_ value: UInt64) -> String {
        bytes(Double(value))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return dash }
        return bytes(bytesPerSecond) + "/s"
    }

    /// Disk heroes stay in GB with two decimals. Memory under 100 GB uses one.
    static func diskGB(_ value: UInt64) -> String {
        decimal(Double(value) / 1_073_741_824, digits: 2) + " GB"
    }

    static func memoryGB(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        let digits = gb < 100 ? 1 : 0
        return decimal(gb, digits: digits) + " GB"
    }

    /// One-decimal gigabytes that add up. The hero is the sum of the rounded parts.
    static func memoryTrio(app: UInt64, wired: UInt64, compressed: UInt64) -> (hero: String, app: String, wired: String, compressed: String) {
        func tenth(_ bytes: UInt64) -> Double {
            (Double(bytes) / 1_073_741_824 * 10).rounded() / 10
        }
        let appGB = tenth(app)
        let wiredGB = tenth(wired)
        let compressedGB = tenth(compressed)
        return (
            hero: decimal(appGB + wiredGB + compressedGB, digits: 1) + " GB",
            app: decimal(appGB, digits: 1) + " GB",
            wired: decimal(wiredGB, digits: 1) + " GB",
            compressed: decimal(compressedGB, digits: 1) + " GB"
        )
    }

    static func memoryAmount(_ value: UInt64) -> String {
        value >= 1_073_741_824 ? memoryGB(value) : bytes(value)
    }

    static func watts(_ value: Double) -> String {
        guard value.isFinite else { return dash }
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        if magnitude == 0 { return "0 W" }
        if magnitude < 1 {
            return sign + decimal(magnitude * 1000, digits: 0) + " mW"
        }
        return sign + decimal(magnitude, digits: 1) + " W"
    }

    static func watts(_ value: Double?) -> String {
        guard let value else { return dash }
        return watts(value)
    }

    static func temperature(_ value: Double) -> String {
        guard value.isFinite else { return dash }
        let digits = abs(value) > 10 ? 0 : 1
        return decimal(value, digits: digits) + "°"
    }

    static func temperature(_ value: Double?) -> String {
        guard let value else { return dash }
        return temperature(value)
    }

    static func load(_ value: Double) -> String {
        guard value.isFinite else { return dash }
        return decimal(value, digits: 2)
    }

    static func remaining(_ minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return dash }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    static func compact(minutes: Int) -> String {
        let minutes = max(0, minutes)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    static func compact(interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0m" }
        return compact(minutes: Int(interval / 60))
    }

    private static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

// MARK: - Layout

private func column(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
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

private func equalRow(_ views: [NSView]) -> NSStackView {
    let row = NSStackView(views: views)
    row.orientation = .horizontal
    row.distribution = .fillEqually
    row.alignment = .top
    row.spacing = 12
    row.translatesAutoresizingMaskIntoConstraints = false
    return row
}

private func symbolView(_ name: String, pointSize: CGFloat, tint: NSColor, side: CGFloat) -> NSImageView {
    let icon = NSImageView()
    icon.image = DashTheme.symbol(name, pointSize: pointSize, tint: tint)
    icon.imageScaling = .scaleProportionallyDown
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.widthAnchor.constraint(equalToConstant: side).isActive = true
    icon.heightAnchor.constraint(equalToConstant: side).isActive = true
    return icon
}

private func textLabel(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: string)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    field.maximumNumberOfLines = 1
    field.cell?.truncatesLastVisibleLine = true
    return field
}

private func processDetail(_ count: Int) -> String {
    count == 1 ? "1 process" : "\(count) processes"
}

private func volumeTitle(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "/" {
        return bootVolumeName
    }
    return trimmed
}

private let bootVolumeName: String = {
    let name = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName
    if let name, !name.isEmpty { return name }
    return "Boot"
}()

private func diskEyebrow(_ state: DashState) -> String {
    let total = state.diskFree + state.diskUsed
    guard total > 0 else { return "Free" }
    return "Free of \(Format.diskGB(total))"
}

private func cardInset(_ content: NSView, inset: CGFloat = 16) -> CardView {
    let card = CardView()
    card.fillColor = DashTheme.card
    card.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
        content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
        content.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
        content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset),
    ])
    return card
}

private func topApp(_ apps: [DashApp], metric: (DashApp) -> Double) -> DashApp? {
    apps.max { metric($0) < metric($1) }
}

/// `floor` is 1 for CPU so a sub-1% leader does not paint a full bar. Other metrics use 0.
private func share(_ value: Double, top: Double, floor: Double = 0) -> CGFloat {
    guard value.isFinite, top.isFinite else { return 0 }
    let denom = max(top, floor)
    guard denom > 0 else { return 0 }
    let raw = value / denom
    if raw <= 0 { return 0 }
    if raw >= 1 { return 1 }
    return CGFloat(raw)
}

// MARK: - Overview

private final class OverviewPage: NSObject {
    let view: NSView
    var onOpen: ((DashTab) -> Void)?

    private let cpuTile: StatTile
    private let memoryTile: StatTile
    private let gpuTile: StatTile
    private let diskTile: StatTile
    private let networkTile: StatTile
    private let batteryTile: StatTile
    private let cpuSpark = SparkBarsView(frame: .zero)
    private let memorySpark = SparkBarsView(frame: .zero)
    private let gpuSpark = SparkBarsView(frame: .zero)
    private let diskSpark = SparkBarsView(frame: .zero)
    private let networkSpark = SparkBarsView(frame: .zero)
    private let batterySpark = SparkBarsView(frame: .zero)
    private let typeDonut = DonutChartView(frame: .zero)
    private let appDonut = DonutChartView(frame: .zero)
    private let powerDonut = DonutChartView(frame: .zero)
    private let typeLegend = LegendColumn()
    private let appLegend = LegendColumn()
    private let powerLegend = LegendColumn()

    override init() {
        cpuTile = StatTile(symbol: DashTab.cpu.symbolName, title: "CPU", tint: DashTheme.accent(.cpu))
        memoryTile = StatTile(symbol: DashTab.memory.symbolName, title: "Memory", tint: DashTheme.accent(.memory))
        gpuTile = StatTile(symbol: DashTab.gpu.symbolName, title: "GPU", tint: DashTheme.accent(.gpu))
        diskTile = StatTile(symbol: DashTab.disk.symbolName, title: "Disk", tint: DashTheme.accent(.disk))
        networkTile = StatTile(symbol: DashTab.network.symbolName, title: "Network", tint: DashTheme.accent(.network))
        batteryTile = StatTile(symbol: DashTab.battery.symbolName, title: "Battery", tint: DashTheme.accent(.battery))

        let sparks = [cpuSpark, memorySpark, gpuSpark, diskSpark, networkSpark, batterySpark]
        let tabs: [DashTab] = [.cpu, .memory, .gpu, .disk, .network, .battery]
        let ceilings: [Double?] = [100, 1, 100, nil, nil, 100]
        for (spark, tab) in zip(sparks, tabs) {
            spark.color = DashTheme.accent(tab)
            spark.translatesAutoresizingMaskIntoConstraints = false
        }
        for (spark, ceiling) in zip(sparks, ceilings) {
            spark.ceiling = ceiling
        }
        cpuTile.embedChart(cpuSpark, height: 42)
        memoryTile.embedChart(memorySpark, height: 42)
        gpuTile.embedChart(gpuSpark, height: 42)
        diskTile.embedChart(diskSpark, height: 42)
        networkTile.embedChart(networkSpark, height: 42)
        batteryTile.embedChart(batterySpark, height: 42)

        let typeCard = Self.donutCard(
            symbol: DashTab.memory.symbolName,
            title: "Memory by Type",
            tint: DashTheme.accent(.memory),
            donut: typeDonut,
            legend: typeLegend
        )
        let appCard = Self.donutCard(
            symbol: "square.grid.2x2",
            title: "Memory by App",
            tint: DashTheme.accent(.memory),
            donut: appDonut,
            legend: appLegend
        )
        let powerCard = Self.donutCard(
            symbol: "bolt.fill",
            title: "Power by App",
            tint: DashTheme.accent(.battery),
            donut: powerDonut,
            legend: powerLegend
        )
        view = column([
            equalRow([cpuTile, memoryTile, gpuTile]),
            equalRow([diskTile, networkTile, batteryTile]),
            equalRow([typeCard, appCard, powerCard]),
        ])
        super.init()
        bind(cpuTile, .cpu)
        bind(memoryTile, .memory)
        bind(gpuTile, .gpu)
        bind(diskTile, .disk)
        bind(networkTile, .network)
        bind(batteryTile, .battery)
    }

    func update(_ state: DashState) {
        cpuTile.setEyebrow("Now")
        cpuTile.setValue(Format.percent(state.cpuNow), caption: nil)
        cpuTile.setFacts([
            (label: "User", value: Format.percent(state.cpuUserShare)),
            (label: "System", value: Format.percent(state.cpuSystemShare)),
            (label: "Average", value: Format.percent(state.cpuAverage)),
        ])
        cpuSpark.values = state.cpuSeries

        let memory = Format.memoryTrio(app: state.memoryApp, wired: state.memoryWired, compressed: state.memoryCompressed)
        memoryTile.setEyebrow(state.memoryTotal > 0 ? "In use of \(Format.memoryGB(state.memoryTotal))" : "In use")
        memoryTile.setValue(memory.hero, caption: nil)
        memoryTile.setFacts([
            (label: "App", value: memory.app),
            (label: "Wired", value: memory.wired),
            (label: "Compressed", value: memory.compressed),
        ])
        memorySpark.values = state.memorySeries

        gpuTile.setEyebrow(state.gpuName.isEmpty ? "GPU" : state.gpuName)
        gpuTile.setValue(Format.percent(state.gpuPercent), caption: nil)
        gpuTile.setFacts([
            (label: "Memory", value: state.gpuMemoryBytes.map(Format.bytes) ?? dash),
            (label: "Average", value: Format.percent(state.gpuAverage)),
            (label: "Peak", value: Format.percent(state.gpuPeak)),
        ])
        gpuSpark.values = state.gpuSeries

        diskTile.setEyebrow(diskEyebrow(state))
        diskTile.setValue(Format.diskGB(state.diskFree), caption: nil)
        diskTile.setFacts([
            (label: "Reading", value: Format.rate(state.diskReadPerSecond)),
            (label: "Writing", value: Format.rate(state.diskWritePerSecond)),
            (label: "Session", value: Format.bytes(state.diskWrittenToday)),
        ])
        diskSpark.values = state.diskSeries

        networkTile.setEyebrow("Downloading")
        networkTile.setValue(Format.rate(state.netDownPerSecond), caption: nil)
        networkTile.setFacts([
            (label: "Uploading", value: Format.rate(state.netUpPerSecond)),
            (label: "Session", value: Format.bytes(state.netToday)),
            (label: "7 days", value: dash),
        ])
        networkSpark.values = state.netSeries

        let onBattery = state.hasBattery && state.onBattery
        batteryTile.setEyebrow(state.hasBattery ? (onBattery ? "On battery" : "Power adapter") : "No battery")
        batteryTile.setValue(state.hasBattery ? Format.percent(state.batteryPercent) : dash, caption: nil)
        batteryTile.setFacts([
            (label: "Remaining", value: Format.remaining(state.batteryMinutesRemaining)),
            (label: "Power", value: Format.watts(state.batteryWatts)),
            (label: "Health", value: Format.percent(state.batteryHealthPercent)),
        ])
        batterySpark.values = state.batterySeries

        updateTypeDonut(state)
        updateAppDonut(state)
        updatePowerDonut(state)
    }

    private func updateTypeDonut(_ state: DashState) {
        let memory = Format.memoryTrio(app: state.memoryApp, wired: state.memoryWired, compressed: state.memoryCompressed)
        let labeled: [(String, UInt64, NSColor, String)] = [
            ("App", state.memoryApp, SlicePalette.app, memory.app),
            ("Wired", state.memoryWired, SlicePalette.wired, memory.wired),
            ("Compressed", state.memoryCompressed, SlicePalette.compressed, memory.compressed),
            ("Cached", state.memoryCached, SlicePalette.cached, Format.bytes(state.memoryCached)),
            ("Free", state.memoryFree, SlicePalette.free, Format.bytes(state.memoryFree)),
        ].filter { $0.1 > 0 }
        let sum = labeled.reduce(UInt64(0)) { $0 + $1.1 }
        typeDonut.slices = labeled.map { part in
            DonutChartView.Slice(fraction: sum > 0 ? CGFloat(Double(part.1) / Double(sum)) : 0, color: part.2)
        }
        if state.memoryTotal > 0 {
            let pct = Double(state.memoryUsed) / Double(state.memoryTotal) * 100
            typeDonut.centerTitle = Format.percent(pct)
        } else {
            typeDonut.centerTitle = dash
        }
        typeDonut.centerSubtitle = "in use"
        typeLegend.setEntries(labeled.map { ($0.2, nil, $0.0, $0.3) })
    }

    private func updateAppDonut(_ state: DashState) {
        let ranked = state.apps
            .map { (name: $0.name, amount: Double($0.memoryBytes), icon: $0.icon) }
            .sorted { $0.amount > $1.amount }
        var parts = topParts(ranked, limit: 4, palette: SlicePalette.apps) { Format.memoryAmount(UInt64($0)) }
        let shown = parts.reduce(0) { $0 + $1.amount }
        let full = Double(state.allAppsMemoryBytes)
        if full > shown + 0.5 {
            let extra = full - shown
            if let index = parts.lastIndex(where: { $0.name == "Other" }) {
                parts[index].amount += extra
                parts[index].valueText = Format.memoryAmount(UInt64(parts[index].amount.rounded()))
            } else {
                parts.append(SlicePart(color: SlicePalette.other, icon: nil, name: "Other", amount: extra, valueText: Format.memoryAmount(UInt64(extra.rounded()))))
            }
        }
        apply(parts, to: appDonut, legend: appLegend)
        let center = state.allAppsMemoryBytes > 0 ? state.allAppsMemoryBytes : UInt64(shown.rounded())
        appDonut.centerTitle = center > 0 ? Format.memoryAmount(center) : dash
        appDonut.centerSubtitle = "all apps"
    }

    private func updatePowerDonut(_ state: DashState) {
        let ranked = state.apps.compactMap { app -> (name: String, amount: Double, icon: NSImage?)? in
            guard let watts = app.powerWatts else { return nil }
            return (app.name, watts, app.icon)
        }.sorted { $0.amount > $1.amount }
        guard !ranked.isEmpty else {
            powerDonut.slices = []
            powerDonut.centerTitle = dash
            powerDonut.centerSubtitle = "not provided"
            powerLegend.setEntries([])
            return
        }
        let parts = topParts(ranked, limit: 4, palette: SlicePalette.power) { Format.watts($0) }
        apply(parts, to: powerDonut, legend: powerLegend)
        let sum = ranked.reduce(0) { $0 + $1.amount }
        powerDonut.centerTitle = Format.watts(sum)
        powerDonut.centerSubtitle = "all apps"
    }

    private func bind(_ tile: NSView, _ tab: DashTab) {
        let click = TabClick(target: self, action: #selector(openTab(_:)))
        click.tab = tab
        click.delaysPrimaryMouseButtonEvents = false
        tile.addGestureRecognizer(click)
    }

    @objc private func openTab(_ sender: Any?) {
        guard let click = sender as? TabClick else { return }
        onOpen?(click.tab)
    }

    private static func donutCard(symbol: String, title: String, tint: NSColor, donut: DonutChartView, legend: LegendColumn) -> NSView {
        let headerIcon = symbolView(symbol, pointSize: 13, tint: tint, side: 16)
        let headerText = textLabel(title, size: 14, weight: .semibold, color: tint)
        let header = NSStackView(views: [headerIcon, headerText])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        donut.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            donut.widthAnchor.constraint(equalToConstant: 132),
            donut.heightAnchor.constraint(equalToConstant: 132),
        ])
        let body = NSStackView(views: [donut, legend])
        body.orientation = .horizontal
        body.distribution = .fill
        body.alignment = .centerY
        body.spacing = 12
        legend.setContentHuggingPriority(.defaultLow, for: .horizontal)
        legend.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let content = NSStackView(views: [header, body])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        body.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        return cardInset(content)
    }
}

private final class TabClick: NSClickGestureRecognizer {
    var tab: DashTab = .overview
}

private enum SlicePalette {
    static let app = NSColor(calibratedRed: 0.27, green: 0.48, blue: 0.96, alpha: 1)
    static let wired = NSColor(calibratedRed: 0.93, green: 0.52, blue: 0.24, alpha: 1)
    static let compressed = NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.42, alpha: 1)
    static let cached = NSColor(calibratedRed: 0.56, green: 0.58, blue: 0.62, alpha: 1)
    static let free = NSColor(calibratedRed: 0.78, green: 0.79, blue: 0.82, alpha: 1)
    static let other = NSColor(calibratedWhite: 0.76, alpha: 1)
    static let apps: [NSColor] = [
        NSColor(calibratedRed: 0.33, green: 0.42, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.49, green: 0.36, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.27, green: 0.28, blue: 0.32, alpha: 1),
        NSColor(calibratedRed: 0.24, green: 0.56, blue: 0.95, alpha: 1),
    ]
    static let power: [NSColor] = [
        NSColor(calibratedRed: 0.16, green: 0.68, blue: 0.38, alpha: 1),
        NSColor(calibratedRed: 0.24, green: 0.50, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.62, blue: 0.78, alpha: 1),
        NSColor(calibratedRed: 0.28, green: 0.29, blue: 0.33, alpha: 1),
    ]
}

private struct SlicePart {
    var color: NSColor
    var icon: NSImage?
    var name: String
    var amount: Double
    var valueText: String
}

private func topParts(
    _ ranked: [(name: String, amount: Double, icon: NSImage?)],
    limit: Int,
    palette: [NSColor],
    value: (Double) -> String
) -> [SlicePart] {
    let positive = ranked.filter { $0.amount > 0 }
    var parts: [SlicePart] = []
    for (index, item) in positive.prefix(limit).enumerated() {
        let color = palette.isEmpty ? SlicePalette.other : palette[index % palette.count]
        parts.append(SlicePart(color: color, icon: item.icon, name: item.name, amount: item.amount, valueText: value(item.amount)))
    }
    let other = positive.dropFirst(limit).reduce(0) { $0 + $1.amount }
    if other > 0 {
        parts.append(SlicePart(color: SlicePalette.other, icon: nil, name: "Other", amount: other, valueText: value(other)))
    }
    return parts
}

private func apply(_ parts: [SlicePart], to donut: DonutChartView, legend: LegendColumn) {
    let sum = parts.reduce(0) { $0 + $1.amount }
    donut.slices = parts.map { part in
        DonutChartView.Slice(fraction: sum > 0 ? CGFloat(part.amount / sum) : 0, color: part.color)
    }
    legend.setEntries(parts.map { ($0.color, $0.icon, $0.name, $0.valueText) })
}

// MARK: - Metric pages

private final class MetricPage {
    let view: NSView
    weak var owner: DashboardRoot?
    private let tab: DashTab
    private let hero: HeroChartCard
    private let chart = AreaChartView(frame: .zero)
    private let minis: [MiniStat]
    private let meters: [MeterBar?]
    private let list: AppListCard
    private let membersWrap: NSView
    private let memberStack = NSStackView()
    private var memberRows: [MemberRow] = []
    private var memberPIDs: [Int32] = []
    private var sortedApps: [DashApp] = []
    private var selectedPID: Int32?
    private var selectedAppID: String?
    private let quitButton = ActionButton(title: "Quit")
    private let forceQuitButton = ActionButton(title: "Force Quit")
    private let quitProcessButton = ActionButton(title: "Quit Process")
    private let forceQuitProcessButton = ActionButton(title: "Force Quit Process")

    init(tab: DashTab, state: DashState) {
        self.tab = tab
        let tint = DashTheme.accent(tab)
        hero = HeroChartCard(eyebrow: Self.eyebrow(tab, state), tint: tint)
        chart.color = tint
        switch tab {
        case .cpu, .gpu, .battery:
            chart.ceiling = 100
        case .memory:
            chart.ceiling = 1
        default:
            chart.ceiling = nil
        }
        chart.translatesAutoresizingMaskIntoConstraints = false
        hero.chartContainer.addSubview(chart)
        NSLayoutConstraint.activate([
            chart.leadingAnchor.constraint(equalTo: hero.chartContainer.leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: hero.chartContainer.trailingAnchor),
            chart.topAnchor.constraint(equalTo: hero.chartContainer.topAnchor),
            chart.bottomAnchor.constraint(equalTo: hero.chartContainer.bottomAnchor),
        ])

        let built = Self.makeMinis(tab, tint: tint)
        minis = built.map(\.mini)
        meters = built.map(\.meter)
        let miniRow = equalRow(minis)

        list = AppListCard(title: "App", valueHeader: Self.valueHeader(tab), tint: tint)

        let members = Self.makeMembers(
            stack: memberStack,
            buttons: [quitButton, forceQuitButton, quitProcessButton, forceQuitProcessButton]
        )
        membersWrap = members
        membersWrap.isHidden = true

        view = column([hero, miniRow, list, membersWrap])
        list.onSelectRow = { [weak self] index in
            guard let self, index >= 0, index < self.sortedApps.count else { return }
            self.owner?.onSelectApp?(self.sortedApps[index].id)
        }
        list.onRightClickRow = { [weak self] index, event in
            guard let self, self.sortedApps.indices.contains(index) else { return }
            let app = self.sortedApps[index]
            guard let row = self.list.rowView(at: index) else { return }
            RowContextMenu.popUp(event, in: row, items: [
                ("Quit \(app.name)", "power", { [weak self] in self?.owner?.onQuitApp?(app.id, false) }),
                ("Force Quit \(app.name)", "xmark.circle", { [weak self] in self?.owner?.onQuitApp?(app.id, true) }),
            ])
        }

        quitButton.onAction = { [weak self] in
            guard let id = self?.selectedAppID else { return }
            self?.owner?.onQuitApp?(id, false)
        }
        forceQuitButton.onAction = { [weak self] in
            guard let id = self?.selectedAppID else { return }
            self?.owner?.onQuitApp?(id, true)
        }
        quitProcessButton.onAction = { [weak self] in
            guard let pid = self?.resolvedPID() else { return }
            self?.owner?.onQuitProcess?(pid, false)
        }
        forceQuitProcessButton.onAction = { [weak self] in
            guard let pid = self?.resolvedPID() else { return }
            self?.owner?.onQuitProcess?(pid, true)
        }
    }

    func update(_ state: DashState) {
        let tint = DashTheme.accent(tab)
        chart.color = tint
        switch tab {
        case .cpu: updateCPU(state)
        case .memory: updateMemory(state)
        case .disk: updateDisk(state)
        case .network: updateNetwork(state)
        case .gpu: updateGPU(state)
        case .battery: updateBattery(state)
        default: break
        }
        updateMembers(state, tint: tint)
    }

    private func updateCPU(_ state: DashState) {
        hero.setEyebrow("Now")
        hero.setValue(Format.percent(state.cpuNow))
        hero.setSideItems([
            (label: "Average today", value: Format.percent(state.cpuAverage)),
            (label: "Load", value: Format.load(state.cpuLoad)),
        ])
        chart.values = state.cpuSeries
        minis[0].setValue(Format.percent(state.cpuUserShare), caption: "Your apps")
        minis[1].setValue(Format.percent(state.cpuSystemShare), caption: "macOS")
        let coreCaption = state.efficiencyCores > 0
            ? "\(state.performanceCores) P · \(state.efficiencyCores) E"
            : "\(state.cpuCores) cores"
        minis[2].setValue("\(state.cpuCores)", caption: coreCaption)
        let top = topApp(state.apps) { $0.cpuPercent }
        minis[3].setApp(name: top?.name ?? dash, icon: top?.icon, detail: top.map { Format.percent($0.cpuPercent) })
        setAppRows(state.apps.sorted { $0.cpuPercent > $1.cpuPercent }, state: state) { app, topValue in
            (Format.percent(app.cpuPercent), share(app.cpuPercent, top: topValue, floor: 1), app.cpuPercent)
        }
    }

    private func updateMemory(_ state: DashState) {
        let memory = Format.memoryTrio(app: state.memoryApp, wired: state.memoryWired, compressed: state.memoryCompressed)
        hero.setValue(memory.hero)
        hero.setSideItems([
            (label: "Free", value: Format.bytes(state.memoryFree)),
            (label: "Swap", value: Format.bytes(state.memorySwap)),
        ])
        chart.values = state.memorySeries
        let total = Double(state.memoryTotal)
        minis[0].setValue(memory.app, caption: nil)
        minis[1].setValue(memory.wired, caption: nil)
        minis[2].setValue(memory.compressed, caption: nil)
        meters[0]?.fraction = total > 0 ? CGFloat(min(1, Double(state.memoryApp) / total)) : 0
        meters[1]?.fraction = total > 0 ? CGFloat(min(1, Double(state.memoryWired) / total)) : 0
        meters[2]?.fraction = total > 0 ? CGFloat(min(1, Double(state.memoryCompressed) / total)) : 0
        let top = topApp(state.apps) { Double($0.memoryBytes) }
        minis[3].setApp(name: top?.name ?? dash, icon: top?.icon, detail: top.map { Format.bytes($0.memoryBytes) })
        setAppRows(state.apps.sorted { $0.memoryBytes > $1.memoryBytes }, state: state) { app, topValue in
            (Format.bytes(app.memoryBytes), share(Double(app.memoryBytes), top: topValue), Double(app.memoryBytes))
        }
    }

    private func updateDisk(_ state: DashState) {
        hero.setEyebrow(diskEyebrow(state))
        hero.setValue(Format.diskGB(state.diskFree))
        hero.setSideItems([
            (label: "Used", value: Format.diskGB(state.diskUsed)),
            (label: "Session", value: Format.bytes(state.diskWrittenToday)),
        ])
        chart.values = state.diskSeries
        minis[0].setValue(Format.rate(state.diskReadPerSecond), caption: nil)
        minis[1].setValue(Format.rate(state.diskWritePerSecond), caption: nil)
        let names = state.volumeNames.map(volumeTitle).filter { !$0.isEmpty }
        let volumeCaption: String?
        if names.isEmpty {
            volumeCaption = nil
        } else if names.count == 1 {
            volumeCaption = names[0]
        } else {
            volumeCaption = "\(names[0]) +\(names.count - 1)"
        }
        minis[2].setValue("\(names.count)", caption: volumeCaption)
        let top = topApp(state.apps) { $0.diskBytesPerSecond }
        minis[3].setApp(name: top?.name ?? dash, icon: top?.icon, detail: top.map { Format.rate($0.diskBytesPerSecond) })
        setAppRows(state.apps.sorted { $0.diskBytesPerSecond > $1.diskBytesPerSecond }, state: state) { app, topValue in
            (Format.rate(app.diskBytesPerSecond), share(app.diskBytesPerSecond, top: topValue), app.diskBytesPerSecond)
        }
    }

    private func updateNetwork(_ state: DashState) {
        hero.setEyebrow("Downloading")
        hero.setValue(Format.rate(state.netDownPerSecond))
        hero.setSideItems([
            (label: "Session", value: Format.bytes(state.netToday)),
            (label: "Last 30 days", value: dash),
        ])
        chart.values = state.netSeries
        minis[0].setValue(Format.rate(state.netUpPerSecond), caption: nil)
        minis[1].setValue(dash, caption: nil)
        let kind = state.netInterfaceKind.isEmpty ? dash : state.netInterfaceKind
        let bsd = state.netInterfaceName.isEmpty ? nil : state.netInterfaceName
        minis[2].setValue(kind, caption: bsd)
        minis[3].setValue(dash, caption: "Not provided")
        setAppRows(state.apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, state: state) { _, _ in
            (dash, 0, 0)
        }
    }

    private func updateGPU(_ state: DashState) {
        hero.setValue(Format.percent(state.gpuPercent))
        hero.setSideItems([
            (label: "Average", value: Format.percent(state.gpuAverage)),
            (label: "Peak", value: Format.percent(state.gpuPeak)),
        ])
        chart.values = state.gpuPercent == nil ? [] : state.gpuSeries
        minis[0].setValue(state.gpuMemoryBytes.map(Format.bytes) ?? dash, caption: nil)
        minis[1].setValue(Format.percent(state.gpuAverage), caption: nil)
        minis[2].setValue(Format.percent(state.gpuPeak), caption: nil)
        let measured = state.apps.contains { $0.gpuPercent != nil }
        if measured {
            let top = topApp(state.apps) { $0.gpuPercent ?? -1 }
            minis[3].setApp(name: top?.name ?? dash, icon: top?.icon, detail: top?.gpuPercent.map(Format.percent) ?? dash)
            setAppRows(state.apps.sorted { ($0.gpuPercent ?? -1) > ($1.gpuPercent ?? -1) }, state: state) { app, topValue in
                let metric = app.gpuPercent ?? 0
                let text = app.gpuPercent.map(Format.percent) ?? dash
                return (text, app.gpuPercent == nil ? 0 : share(metric, top: topValue), metric)
            }
        } else {
            minis[3].setValue(dash, caption: "Not provided")
            setAppRows(state.apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, state: state) { _, _ in
                (dash, 0, 0)
            }
        }
    }

    private func updateBattery(_ state: DashState) {
        hero.setValue(Format.percent(state.batteryPercent))
        hero.setSideItems([
            (label: "Remaining", value: Format.remaining(state.batteryMinutesRemaining)),
            (label: "Cycles", value: state.batteryCycles.map(String.init) ?? dash),
        ])
        chart.values = state.batterySeries
        minis[0].setValue(Format.watts(state.batteryWatts), caption: nil)
        minis[1].setValue(Format.percent(state.batteryHealthPercent), caption: nil)
        if let health = state.batteryHealthPercent, health.isFinite {
            meters[1]?.fraction = CGFloat(min(1, max(0, health / 100)))
        } else {
            meters[1]?.fraction = 0
        }
        minis[2].setValue(Format.temperature(state.batteryTemperatureC), caption: nil)
        let anyWatts = state.apps.contains { $0.powerWatts != nil }
        if anyWatts {
            let top = topApp(state.apps) { $0.powerWatts ?? -1 }
            minis[3].setApp(name: top?.name ?? dash, icon: top?.icon, detail: top?.powerWatts.map(Format.watts) ?? dash)
            let ranked = state.apps.sorted { ($0.powerWatts ?? -1) > ($1.powerWatts ?? -1) }
            setAppRows(ranked, state: state) { app, topValue in
                let metric = app.powerWatts ?? 0
                let text = Format.watts(app.powerWatts)
                return (text, app.powerWatts == nil ? 0 : share(metric, top: topValue), metric)
            }
        } else {
            minis[3].setValue(dash, caption: "Not provided")
            setAppRows(state.apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, state: state) { _, _ in
                (dash, 0, 0)
            }
        }
    }

    private func setAppRows(
        _ apps: [DashApp],
        state: DashState,
        metric: (DashApp, Double) -> (String, CGFloat, Double)
    ) {
        sortedApps = apps
        let topValue = apps.first.map { metric($0, 0).2 } ?? 0
        let rows = apps.enumerated().map { index, app in
            let (text, fraction, _) = metric(app, topValue)
            return AppListCard.Row(
                name: app.name,
                detail: processDetail(app.processCount),
                valueText: text,
                fraction: fraction,
                icon: app.icon,
                selected: app.id == state.selectedAppID,
                featured: false
            )
        }
        list.setRows(rows)
    }

    private func updateMembers(_ state: DashState, tint: NSColor) {
        let show = state.selectedAppID != nil && !state.members.isEmpty
        membersWrap.isHidden = !show
        guard show else { return }
        if selectedAppID != state.selectedAppID {
            selectedAppID = state.selectedAppID
            selectedPID = state.members.first?.pid
        }
        if selectedPID == nil || !state.members.contains(where: { $0.pid == selectedPID }) {
            selectedPID = state.members.first?.pid
        }
        let pids = state.members.map(\.pid)
        if pids != memberPIDs {
            memberPIDs = pids
            memberRows.forEach {
                memberStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            memberRows = state.members.map { _ in
                let row = MemberRow()
                row.onSelect = { [weak self] pid in
                    self?.selectedPID = pid
                    self?.highlightMembers(tint: tint)
                }
                row.translatesAutoresizingMaskIntoConstraints = false
                memberStack.insertArrangedSubview(row, at: max(0, memberStack.arrangedSubviews.count - 1))
                row.widthAnchor.constraint(equalTo: memberStack.widthAnchor).isActive = true
                return row
            }
        }
        for (row, member) in zip(memberRows, state.members) {
            row.apply(member)
            let pid = member.pid
            let name = member.name.isEmpty ? "Process" : member.name
            row.onRightClick = { [weak self] event in
                RowContextMenu.popUp(event, in: row, items: [
                    ("Quit \(name)", "power", { [weak self] in self?.owner?.onQuitProcess?(pid, false) }),
                    ("Force Quit \(name)", "xmark.circle", { [weak self] in self?.owner?.onQuitProcess?(pid, true) }),
                ])
            }
        }
        highlightMembers(tint: tint)
    }

    private func highlightMembers(tint: NSColor) {
        let wash = DashTheme.accentWash(tab)
        for row in memberRows {
            row.setSelected(row.pid == selectedPID, wash: wash, tint: tint)
        }
    }

    private func resolvedPID() -> Int32? {
        if let selectedPID, memberPIDs.contains(selectedPID) {
            return selectedPID
        }
        return memberPIDs.first
    }

    private static func eyebrow(_ tab: DashTab, _ state: DashState) -> String {
        switch tab {
        case .cpu:
            return "Now"
        case .memory:
            return state.memoryTotal > 0 ? "In use of \(Format.memoryGB(state.memoryTotal))" : "In use"
        case .disk:
            return diskEyebrow(state)
        case .network:
            return "Downloading"
        case .gpu:
            return state.gpuName.isEmpty ? "GPU" : state.gpuName
        case .battery:
            return state.hasBattery && state.onBattery ? "On battery" : "Power adapter"
        default:
            return tab.title
        }
    }

    private static func valueHeader(_ tab: DashTab) -> String {
        switch tab {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Writing"
        case .network: return "Downloading"
        case .gpu: return "GPU"
        case .battery: return "Power"
        default: return tab.title
        }
    }

    private static func makeMinis(_ tab: DashTab, tint: NSColor) -> [(mini: MiniStat, meter: MeterBar?)] {
        let specs: [(String, String, Bool)]
        switch tab {
        case .cpu:
            specs = [("person.fill", "User", false), ("apple.logo", "System", false), ("cpu", "Cores", false), ("square.grid.2x2", "Top App", false)]
        case .memory:
            specs = [("square.grid.2x2", "App", true), ("memorychip", "Wired", true), ("rectangle.compress.vertical", "Compressed", true), ("square.grid.2x2", "Top App", false)]
        case .disk:
            specs = [("arrow.down", "Reading", false), ("arrow.up", "Writing", false), ("internaldrive", "Volumes", false), ("square.grid.2x2", "Top App", false)]
        case .network:
            specs = [("arrow.up", "Uploading", false), ("chart.bar.fill", "Last 7 Days", false), ("wifi", "Interface", false), ("square.grid.2x2", "Top App", false)]
        case .gpu:
            specs = [("memorychip", "Memory", false), ("chart.line.uptrend.xyaxis", "Average", false), ("bolt.fill", "Peak", false), ("square.grid.2x2", "Top App", false)]
        case .battery:
            specs = [("bolt.fill", "Power Draw", false), ("heart.fill", "Health", true), ("thermometer.medium", "Temperature", false), ("square.grid.2x2", "Top App", false)]
        default:
            specs = []
        }
        return specs.map { symbol, title, wantsMeter in
            let mini = MiniStat(symbol: symbol, title: title, tint: tint, footer: wantsMeter ? 14 : 0)
            guard wantsMeter else { return (mini, nil) }
            let meter = MeterBar(frame: .zero)
            meter.color = tint
            meter.translatesAutoresizingMaskIntoConstraints = false
            // MiniStat has no meter slot. Pin a 4pt bar into the card's bottom padding.
            mini.addSubview(meter)
            NSLayoutConstraint.activate([
                meter.leadingAnchor.constraint(equalTo: mini.leadingAnchor, constant: 16),
                meter.trailingAnchor.constraint(equalTo: mini.trailingAnchor, constant: -16),
                meter.bottomAnchor.constraint(equalTo: mini.bottomAnchor, constant: -12),
                meter.heightAnchor.constraint(equalToConstant: 4),
            ])
            return (mini, meter)
        }
    }

    private static func makeMembers(stack: NSStackView, buttons: [NSButton]) -> NSView {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = textLabel("Processes", size: 13, weight: .semibold, color: DashTheme.primaryText)
        stack.addArrangedSubview(title)
        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        stack.addArrangedSubview(buttonRow)
        title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return cardInset(stack, inset: 14)
    }
}

private final class MemberRow: NSView {
    var pid: Int32 = 0
    var onSelect: ((Int32) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    private let nameField = textLabel("", size: 13, weight: .semibold, color: DashTheme.primaryText)
    private let metaField = textLabel("", size: 12, weight: .regular, color: DashTheme.secondaryText)
    private let meter = MeterBar(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        click.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(click)

        meter.translatesAutoresizingMaskIntoConstraints = false
        let text = NSStackView(views: [nameField, metaField])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        addSubview(meter)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            text.trailingAnchor.constraint(lessThanOrEqualTo: meter.leadingAnchor, constant: -8),
            meter.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            meter.centerYAnchor.constraint(equalTo: centerYAnchor),
            meter.widthAnchor.constraint(equalToConstant: 72),
            meter.heightAnchor.constraint(equalToConstant: 4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ member: DashMember) {
        pid = member.pid
        nameField.stringValue = member.name.isEmpty ? dash : member.name
        metaField.stringValue = "pid \(member.pid) · \(Format.percent(member.cpuPercent)) · \(Format.bytes(member.memoryBytes))"
        let fraction = member.cpuPercent / 100
        meter.fraction = CGFloat(min(1, max(0, fraction.isFinite ? fraction : 0)))
    }

    func setSelected(_ selected: Bool, wash: NSColor, tint: NSColor) {
        layer?.backgroundColor = (selected ? wash : NSColor.clear).cgColor
        meter.color = tint
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick {
            onRightClick(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    @objc private func clicked() {
        onSelect?(pid)
    }
}

private final class ActionButton: NSButton {
    var onAction: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: 12, weight: .medium)
        target = self
        action = #selector(fire)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        onAction?()
    }
}

// MARK: - Projects

private final class ProjectsPage {
    private enum Mode: Equatable { case scanning, empty, list }

    let view: NSView
    var onStop: (() -> Void)?
    var onQuitProject: ((String, [Int32], Bool) -> Void)?
    private(set) var idlePIDs: [Int32] = []
    private let content = NSStackView()
    private let banner = ProjectsBanner(frame: .zero)
    private let rows = NSStackView()
    private let empty = textLabel("", size: 13, weight: .regular, color: DashTheme.secondaryText)
    private var rowViews: [ProjectRow] = []
    private var mode: Mode?

    init() {
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        empty.maximumNumberOfLines = 2
        view = cardInset(content, inset: 12)
        banner.onStopAll = { [weak self] in self?.onStop?() }
    }

    func update(_ state: DashState) {
        if !state.projectsScanned && state.projects.isEmpty {
            show(.scanning, message: "Looking for dev servers…")
            idlePIDs = []
            return
        }
        if state.projects.isEmpty {
            show(.empty, message: "No dev servers running.")
            idlePIDs = []
            return
        }
        show(.list, message: nil)

        let idle = state.projects.filter { $0.idleMinutes != nil || $0.cpuPercent < 2 }
        var seen = Set<Int32>()
        idlePIDs = []
        for project in idle {
            for pid in project.pids where seen.insert(pid).inserted {
                idlePIDs.append(pid)
            }
        }
        let memory = idle.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let ports = Array(Set(idle.flatMap(\.ports))).sorted()
        let title = serverTitle(count: idle.isEmpty ? state.projects.count : idle.count, idle: !idle.isEmpty)
        let detail: String
        if idle.isEmpty {
            detail = "Nothing is idle."
        } else if ports.isEmpty {
            detail = "Stopping them frees \(Format.bytes(memory))."
        } else {
            let shown = ports.prefix(6).map(String.init).joined(separator: ", ")
            let extra = ports.count > 6 ? " +\(ports.count - 6) more" : ""
            detail = "Stopping them frees \(Format.bytes(memory)) and ports \(shown)\(extra)."
        }
        banner.set(title: title, detail: detail, showsStop: !idlePIDs.isEmpty)

        if rowViews.count != state.projects.count {
            rowViews.forEach {
                rows.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            rowViews = state.projects.map { _ in
                let row = ProjectRow()
                rows.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
                return row
            }
        }
        for (row, project) in zip(rowViews, state.projects) {
            row.apply(project)
            let name = project.name.isEmpty ? "Project" : project.name
            let pids = project.pids
            row.onRightClick = { [weak self] event in
                guard !pids.isEmpty else { return }
                RowContextMenu.popUp(event, in: row, items: [
                    ("Quit \(name)", "power", { [weak self] in self?.onQuitProject?(name, pids, false) }),
                    ("Force Quit \(name)", "xmark.circle", { [weak self] in self?.onQuitProject?(name, pids, true) }),
                ])
            }
        }
    }

    private func show(_ next: Mode, message: String?) {
        if let message {
            empty.stringValue = message
        }
        guard next != mode else { return }
        mode = next
        for item in content.arrangedSubviews {
            content.removeArrangedSubview(item)
            item.removeFromSuperview()
        }
        let shown: [NSView] = next == .list ? [banner, rows] : [empty]
        for item in shown {
            item.translatesAutoresizingMaskIntoConstraints = false
            content.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
    }

    private func serverTitle(count: Int, idle: Bool) -> String {
        if count == 1 {
            return idle ? "1 dev server is running but idle" : "1 dev server running"
        }
        return idle ? "\(count) dev servers are running but idle" : "\(count) dev servers running"
    }
}

private final class ProjectRow: NSView {
    var onRightClick: ((NSEvent) -> Void)?
    private let icon = symbolView("folder", pointSize: 15, tint: DashTheme.accent(.projects), side: 18)
    private let nameField = textLabel("", size: 14, weight: .semibold, color: DashTheme.primaryText)
    private let runtimeField = textLabel("", size: 12, weight: .regular, color: DashTheme.secondaryText)
    private let memoryField = textLabel("", size: 13, weight: .semibold, color: DashTheme.primaryText)
    private let ports = NSStackView()
    private let status = CapsuleLabel()
    private var shownPorts: [Int] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        ports.orientation = .horizontal
        ports.alignment = .centerY
        ports.spacing = 4
        ports.translatesAutoresizingMaskIntoConstraints = false
        ports.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        ports.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let names = NSStackView(views: [nameField, runtimeField])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = 1
        names.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        memoryField.setContentCompressionResistancePriority(.required, for: .horizontal)
        memoryField.setContentHuggingPriority(.required, for: .horizontal)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        runtimeField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, names, spacer, ports, status, memoryField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.edgeInsets = NSEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick {
            onRightClick(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    func apply(_ project: DashProject) {
        nameField.stringValue = project.name.isEmpty ? dash : project.name
        if !project.runtime.isEmpty {
            runtimeField.stringValue = project.runtime
        } else {
            runtimeField.stringValue = processDetail(project.processCount)
        }
        memoryField.stringValue = Format.bytes(project.memoryBytes)
        let portNumbers = project.ports.sorted()
        if portNumbers != shownPorts {
            shownPorts = portNumbers
            rebuildPorts(portNumbers)
        }
        let resolved = ProjectStatus.resolve(
            cpuPercent: project.cpuPercent,
            idleMinutes: project.idleMinutes,
            uptime: project.uptime
        )
        status.isHidden = false
        switch resolved {
        case .working:
            status.set(
                text: "working",
                fill: NSColor.systemGreen.withAlphaComponent(0.16),
                foreground: NSColor.systemGreen
            )
        case .idle(let minutes):
            status.set(
                text: "idle \(Format.compact(minutes: minutes))",
                fill: DashTheme.secondaryText.withAlphaComponent(0.12),
                foreground: DashTheme.secondaryText
            )
        case .uptime(let seconds):
            let minutes = Int(seconds / 60)
            let text = minutes > 0 ? "up \(Format.compact(minutes: minutes))" : "up <1m"
            status.set(
                text: text,
                fill: DashTheme.secondaryText.withAlphaComponent(0.12),
                foreground: DashTheme.secondaryText
            )
        case .quiet:
            status.set(
                text: "idle",
                fill: DashTheme.secondaryText.withAlphaComponent(0.12),
                foreground: DashTheme.secondaryText
            )
        }
    }

    private func rebuildPorts(_ values: [Int]) {
        for view in ports.arrangedSubviews {
            ports.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let tint = DashTheme.accent(.projects)
        let fill = DashTheme.accentWash(.projects)
        for port in values {
            let capsule = CapsuleLabel()
            capsule.set(text: String(port), fill: fill, foreground: tint)
            ports.addArrangedSubview(capsule)
        }
    }
}

private final class CapsuleLabel: NSView {
    private let label = textLabel("", size: 11, weight: .medium, color: DashTheme.secondaryText)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(text: String, fill: NSColor, foreground: NSColor) {
        label.stringValue = text
        label.textColor = foreground
        layer?.backgroundColor = fill.cgColor
    }
}

// MARK: - Donut legend

private final class LegendColumn: NSStackView {
    private var lines: [LegendLine] = []

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEntries(_ entries: [(NSColor, NSImage?, String, String)]) {
        while lines.count < entries.count {
            let line = LegendLine()
            lines.append(line)
            addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        while lines.count > entries.count {
            let line = lines.removeLast()
            removeArrangedSubview(line)
            line.removeFromSuperview()
        }
        for (line, entry) in zip(lines, entries) {
            line.apply(color: entry.0, icon: entry.1, name: entry.2, value: entry.3)
        }
    }
}

private final class LegendLine: NSView {
    private let dot = ColorDot()
    private let icon = NSImageView()
    private let nameField = textLabel("", size: 12, weight: .medium, color: DashTheme.primaryText)
    private let valueField = textLabel("", size: 12, weight: .regular, color: DashTheme.secondaryText)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        valueField.alignment = .right
        valueField.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueField.setContentHuggingPriority(.required, for: .horizontal)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [dot, icon, nameField, valueField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(color: NSColor, icon image: NSImage?, name: String, value: String) {
        dot.color = color
        dot.isHidden = image != nil
        icon.image = image
        icon.isHidden = image == nil
        nameField.stringValue = name
        valueField.stringValue = value
    }
}

private final class ColorDot: NSView {
    var color: NSColor = .gray { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 8).isActive = true
        heightAnchor.constraint(equalToConstant: 8).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
