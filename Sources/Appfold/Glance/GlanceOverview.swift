import AppKit

/// Dark overview page. Formats a measured `DashState` and does not sample hardware.
final class GlanceOverviewPage: NSView {
    var onOpenTab: ((DashTab) -> Void)?

    private let uptimeLabel = glanceLabel("Up —", size: 13, weight: .medium, color: GlanceTheme.secondary)

    private let cpuValue = glanceLabel("—", size: 32, weight: .semibold, color: GlanceTheme.primary)
    private let cpuUnit = glanceLabel("%", size: 15, weight: .medium, color: GlanceTheme.secondary)
    private let cpuLoad = glanceLabel("load —", size: 13, weight: .medium, color: GlanceTheme.secondary)
    private let cpuChart = GlanceAreaChart(frame: .zero)

    private let memoryValue = glanceLabel("—", size: 28, weight: .semibold, color: GlanceTheme.primary)
    private let memoryUnit = glanceLabel("", size: 14, weight: .medium, color: GlanceTheme.secondary)
    private let memoryOf = glanceLabel("of —", size: 12, weight: .medium, color: GlanceTheme.secondary)
    private let memoryMeter = GlanceMeter(frame: .zero)

    private let netDown = glanceLabel("—", size: 18, weight: .semibold, color: GlanceTheme.primary)
    private let netUp = glanceLabel("—", size: 18, weight: .semibold, color: GlanceTheme.primary)
    private let netChart = GlanceAreaChart(frame: .zero)

    private let diskValue = glanceLabel("—", size: 28, weight: .semibold, color: GlanceTheme.primary)
    private let diskMeter = GlanceMeter(frame: .zero)

    private let gpuValue = glanceLabel("—", size: 32, weight: .semibold, color: GlanceTheme.primary)
    private let gpuUnit = glanceLabel("%", size: 15, weight: .medium, color: GlanceTheme.secondary)
    private let gpuChart = GlanceAreaChart(frame: .zero)

    private let batteryValue = glanceLabel("—", size: 32, weight: .semibold, color: GlanceTheme.primary)
    private let batteryUnit = glanceLabel("%", size: 15, weight: .medium, color: GlanceTheme.secondary)
    private let batteryRemaining = glanceLabel("—", size: 13, weight: .medium, color: GlanceTheme.secondary)
    private let batteryCaption = glanceLabel("No battery", size: 13, weight: .medium, color: GlanceTheme.secondary)
    private let batteryMeter = GlanceMeter(frame: .zero)

    private let busyRows = [
        GlanceAppRow(frame: .zero),
        GlanceAppRow(frame: .zero),
        GlanceAppRow(frame: .zero)
    ]
    private let busyEmpty = glanceLabel("No apps yet", size: 13, weight: .medium, color: GlanceTheme.secondary)

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = GlanceTheme.canvas.cgColor
    }

    func render(_ state: DashState) {
        uptimeLabel.stringValue = "Up " + GlanceFormat.uptime(ProcessInfo.processInfo.systemUptime)

        let cpuText = GlanceFormat.percentHero(state.cpuNow)
        cpuValue.stringValue = cpuText
        cpuUnit.isHidden = cpuText == "—"
        cpuLoad.stringValue = "load " + GlanceFormat.load(state.cpuLoad)
        cpuChart.values = state.cpuSeries

        let memory = GlanceFormat.bytePair(state.memoryUsed)
        memoryValue.stringValue = memory.number
        memoryUnit.stringValue = memory.unit
        memoryOf.stringValue = "of " + GlanceFormat.byteText(state.memoryTotal)
        memoryMeter.fraction = GlanceFormat.fraction(state.memoryUsed, of: state.memoryTotal)

        netDown.stringValue = GlanceFormat.rate(state.netDownPerSecond)
        netUp.stringValue = GlanceFormat.rate(state.netUpPerSecond)
        netChart.values = state.netSeries

        diskValue.stringValue = GlanceFormat.diskNumber(state.diskFree)
        let diskTotal = state.diskUsed + state.diskFree
        diskMeter.fraction = GlanceFormat.fraction(state.diskUsed, of: diskTotal)

        let gpuText = GlanceFormat.percentHero(state.gpuPercent ?? .nan)
        gpuValue.stringValue = gpuText
        gpuUnit.isHidden = gpuText == "—"
        gpuChart.values = state.gpuSeries

        renderBattery(state)
        renderBusy(state.apps)
    }

    private func renderBattery(_ state: DashState) {
        if state.hasBattery {
            let hero = GlanceFormat.percentHero(state.batteryPercent ?? .nan)
            batteryValue.stringValue = hero
            batteryUnit.isHidden = hero == "—"
            batteryRemaining.stringValue = GlanceFormat.remaining(state.batteryMinutesRemaining)
            batteryRemaining.isHidden = false
            batteryCaption.isHidden = true
            batteryMeter.isHidden = false
            let percent = state.batteryPercent ?? 0
            batteryMeter.fraction = percent.isFinite ? CGFloat(percent / 100) : 0
        } else {
            batteryValue.stringValue = "—"
            batteryUnit.isHidden = true
            batteryRemaining.isHidden = true
            batteryCaption.isHidden = false
            batteryMeter.isHidden = true
        }
    }

    private func renderBusy(_ apps: [DashApp]) {
        let ranked = apps.sorted { $0.cpuPercent > $1.cpuPercent }
        busyEmpty.isHidden = !ranked.isEmpty
        for (index, row) in busyRows.enumerated() {
            guard index < ranked.count else {
                row.isHidden = true
                continue
            }
            let app = ranked[index]
            let cpu = app.cpuPercent
            row.isHidden = false
            row.apply(
                icon: app.icon,
                name: app.name,
                value: GlanceFormat.percentApp(cpu),
                fraction: cpu.isFinite ? CGFloat(min(1, cpu / 100)) : 0,
                tint: GlanceTheme.accent(.cpu)
            )
        }
    }

    private func build() {
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        layer?.backgroundColor = GlanceTheme.canvas.cgColor

        cpuUnit.isHidden = true
        gpuUnit.isHidden = true
        batteryUnit.isHidden = true
        batteryRemaining.isHidden = true
        batteryMeter.isHidden = true
        busyEmpty.isHidden = false
        busyRows.forEach { $0.isHidden = true }

        let column = glanceColumn([
            makeHeader(),
            metricRow(makeCPU(), makeMemory()),
            metricRow(makeNetwork(), makeDisk()),
            metricRow(makeGPU(), makeBattery()),
            makeBusiest()
        ], spacing: 12)
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    private func makeHeader() -> NSView {
        let eyebrow = glanceEyebrow("Overview")
        let clock = NSImageView()
        clock.image = GlanceTheme.symbol("clock", pointSize: 12, tint: GlanceTheme.secondary)
        clock.imageScaling = .scaleProportionallyDown
        clock.imageAlignment = .alignCenter
        clock.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clock.widthAnchor.constraint(equalToConstant: 14),
            clock.heightAnchor.constraint(equalToConstant: 14)
        ])
        uptimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        uptimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let clockRow = NSStackView(views: [clock, uptimeLabel])
        clockRow.orientation = .horizontal
        clockRow.alignment = .centerY
        clockRow.spacing = 5
        clockRow.setContentHuggingPriority(.required, for: .horizontal)
        clockRow.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let header = NSStackView(views: [eyebrow, spacer, clockRow])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.setContentHuggingPriority(.required, for: .vertical)
        header.setContentCompressionResistancePriority(.required, for: .vertical)
        return header
    }

    private func makeCPU() -> GlanceCard {
        lock(cpuChart, height: 40)
        cpuChart.color = GlanceTheme.accent(.cpu)
        pinTrailing(cpuLoad)
        let hero = heroLine(baselineCluster([cpuValue, cpuUnit], spacing: 2), trailing: cpuLoad)
        return makeCard(tab: .cpu, title: "CPU", parts: [hero, growingSpacer(), cpuChart])
    }

    private func makeMemory() -> GlanceCard {
        lock(memoryMeter, height: 4)
        memoryMeter.fillColor = GlanceTheme.accent(.memory)
        pinTrailing(memoryOf)
        let hero = heroLine(baselineCluster([memoryValue, memoryUnit], spacing: 3), trailing: memoryOf)
        return makeCard(tab: .memory, title: "Memory", parts: [hero, growingSpacer(), memoryMeter])
    }

    private func makeNetwork() -> GlanceCard {
        lock(netChart, height: 40)
        netChart.color = GlanceTheme.accent(.network)
        let downArrow = glanceLabel("↓", size: 14, weight: .medium, color: GlanceTheme.secondary)
        let upArrow = glanceLabel("↑", size: 14, weight: .medium, color: GlanceTheme.secondary)
        let rates = baselineCluster([downArrow, netDown, upArrow, netUp], spacing: 4)
        rates.setCustomSpacing(14, after: netDown)
        return makeCard(tab: .network, title: "Network", parts: [leadingLine(rates), growingSpacer(), netChart])
    }

    private func makeDisk() -> GlanceCard {
        lock(diskMeter, height: 8)
        diskMeter.fillColor = GlanceTheme.accent(.disk)
        diskMeter.trackColor = NSColor(srgbRed: 0.35, green: 0.28, blue: 0.16, alpha: 1)
        let unit = glanceLabel("GB", size: 14, weight: .medium, color: GlanceTheme.secondary)
        let free = glanceLabel("free", size: 13, weight: .medium, color: GlanceTheme.secondary)
        let hero = baselineCluster([diskValue, unit, free], spacing: 4)
        hero.setCustomSpacing(6, after: unit)
        return makeCard(tab: .disk, title: "Disk", parts: [leadingLine(hero), growingSpacer(), diskMeter])
    }

    private func makeGPU() -> GlanceCard {
        lock(gpuChart, height: 40)
        gpuChart.color = GlanceTheme.accent(.gpu)
        let hero = baselineCluster([gpuValue, gpuUnit], spacing: 2)
        return makeCard(tab: .gpu, title: "GPU", parts: [leadingLine(hero), growingSpacer(), gpuChart])
    }

    private func makeBattery() -> GlanceCard {
        lock(batteryMeter, height: 8)
        batteryMeter.fillColor = GlanceTheme.accent(.battery)
        batteryCaption.setContentHuggingPriority(.required, for: .vertical)
        batteryCaption.setContentCompressionResistancePriority(.required, for: .vertical)
        let hero = baselineCluster([batteryValue, batteryUnit, batteryRemaining], spacing: 2)
        hero.setCustomSpacing(8, after: batteryUnit)
        return makeCard(
            tab: .battery,
            title: "Battery",
            parts: [leadingLine(hero), batteryCaption, growingSpacer(), batteryMeter]
        )
    }

    private func makeBusiest() -> GlanceCard {
        let card = GlanceCard(frame: .zero)
        let title = glanceLabel("Busiest Right Now", size: 16, weight: .medium, color: GlanceTheme.secondary)
        let stack = glanceColumn([title, busyEmpty] + busyRows, spacing: 8)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        card.setContentHuggingPriority(.defaultHigh, for: .vertical)
        card.setContentCompressionResistancePriority(.required, for: .vertical)
        return card
    }

    private func makeCard(tab: DashTab, title: String, parts: [NSView]) -> GlanceCard {
        let card = GlanceCard(frame: .zero)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let preferred = card.heightAnchor.constraint(equalToConstant: 150)
        preferred.priority = NSLayoutConstraint.Priority(750)
        preferred.isActive = true
        // Extra page height lands in the card; the spacer keeps the chart or meter on the bottom.
        card.setContentHuggingPriority(NSLayoutConstraint.Priority(100), for: .vertical)
        card.setContentCompressionResistancePriority(.required, for: .vertical)
        let stack = glanceColumn([cardHeader(tab, title)] + parts, spacing: 8)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        card.addGestureRecognizer(GlanceClick { [weak self] in
            self?.onOpenTab?(tab)
        })
        return card
    }

    private func metricRow(_ left: NSView, _ right: NSView) -> NSStackView {
        let row = glanceRow([left, right], spacing: 10)
        row.alignment = .centerY
        row.setContentHuggingPriority(NSLayoutConstraint.Priority(200), for: .vertical)
        row.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        return row
    }

    private func cardHeader(_ tab: DashTab, _ title: String) -> NSStackView {
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyDown
        icon.imageAlignment = .alignCenter
        icon.image = GlanceTheme.symbol(GlanceTheme.symbolName(tab), pointSize: 13, tint: GlanceTheme.accent(tab))
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        let label = glanceLabel(title, size: 13, weight: .medium, color: GlanceTheme.secondary)
        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.setContentHuggingPriority(.required, for: .vertical)
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        return row
    }

    private func baselineCluster(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.spacing = spacing
        row.setContentHuggingPriority(.required, for: .horizontal)
        row.setContentHuggingPriority(.required, for: .vertical)
        row.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        for view in views {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentHuggingPriority(.required, for: .vertical)
            view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
        return row
    }

    private func leadingLine(_ cluster: NSStackView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        cluster.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(cluster)
        NSLayoutConstraint.activate([
            cluster.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            cluster.topAnchor.constraint(equalTo: row.topAnchor),
            cluster.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            cluster.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor)
        ])
        row.setContentHuggingPriority(.required, for: .vertical)
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        return row
    }

    private func heroLine(_ leading: NSStackView, trailing: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        leading.translatesAutoresizingMaskIntoConstraints = false
        trailing.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(leading)
        row.addSubview(trailing)
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            leading.topAnchor.constraint(equalTo: row.topAnchor),
            leading.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            trailing.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            trailing.firstBaselineAnchor.constraint(equalTo: leading.firstBaselineAnchor),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: leading.trailingAnchor, constant: 8)
        ])
        row.setContentHuggingPriority(.required, for: .vertical)
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        return row
    }

    private func pinTrailing(_ label: NSTextField) {
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(700), for: .horizontal)
    }

    private func growingSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        let preferred = spacer.heightAnchor.constraint(equalToConstant: 0)
        preferred.priority = .defaultLow
        preferred.isActive = true
        return spacer
    }

    private func lock(_ view: NSView, height: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
    }
}
