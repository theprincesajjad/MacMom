import AppKit

/// CPU, Memory, Disk, Network, GPU, and Battery pages for the menu-bar glance.
/// The view tree is built once. `render` only updates measured text and bars.
final class GlanceMetricPage: NSView {
    private var built = false
    private let eyebrow = NSTextField(labelWithString: "")
    private let cpu = CPUSection()
    private let memory = MemorySection()
    private let disk = DiskSection()
    private let network = NetworkSection()
    private let gpu = GPUSection()
    private let battery = BatterySection()
    private var sections: [DashTab: NSView] = [:]

    var tab: DashTab {
        didSet {
            guard built, oldValue != tab else { return }
            show(tab)
        }
    }

    init(tab: DashTab) {
        self.tab = tab
        super.init(frame: .zero)
        build()
        built = true
        show(tab)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func render(_ state: DashState) {
        cpu.render(state)
        memory.render(state)
        disk.render(state)
        network.render(state)
        gpu.render(state)
        battery.render(state)
    }

    private func build() {
        eyebrow.lineBreakMode = .byTruncatingTail
        eyebrow.maximumNumberOfLines = 1
        eyebrow.setContentHuggingPriority(.required, for: .vertical)

        let cards: [(DashTab, NSView)] = [
            (.cpu, wrap(cpu)),
            (.memory, wrap(memory)),
            (.disk, wrap(disk)),
            (.network, wrap(network)),
            (.gpu, wrap(gpu)),
            (.battery, wrap(battery))
        ]
        var arranged: [NSView] = [eyebrow]
        for (tab, card) in cards {
            sections[tab] = card
            arranged.append(card)
        }
        let column = glanceColumn(arranged, spacing: 12)
        column.detachesHiddenViews = true
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    private func wrap(_ content: NSView) -> GlanceCard {
        let card = GlanceCard(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func show(_ tab: DashTab) {
        eyebrow.attributedStringValue = glanceTracked(
            tab.title.uppercased(),
            size: 12,
            weight: .semibold,
            color: GlanceTheme.secondary,
            kern: 1.3
        )
        for (key, card) in sections {
            card.isHidden = key != tab
        }
    }
}

// MARK: - Pieces

private final class GlanceFactLine: NSView {
    private let dot = NSView()
    private let nameField = glanceLabel("", size: 15, weight: .regular, color: GlanceTheme.secondary)
    private let valueField = glanceLabel("—", size: 15, weight: .medium, color: GlanceTheme.primary)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        valueField.alignment = .right
        valueField.setContentHuggingPriority(.required, for: .horizontal)
        valueField.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [dot, nameField, valueField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.detachesHiddenViews = true
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setDot(nil)
    }

    required init?(coder: NSCoder) { nil }

    func set(label: String, value: String, dot color: NSColor? = nil) {
        nameField.stringValue = label
        valueField.stringValue = value
        setDot(color)
    }

    private func setDot(_ color: NSColor?) {
        dot.isHidden = color == nil
        dot.layer?.backgroundColor = color?.cgColor
    }
}

private final class GlanceLevelPill: NSView {
    private let label = glanceLabel("", size: 11, weight: .semibold, color: GlanceTheme.normalText)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ level: GlanceMemoryLevel) {
        label.stringValue = level.title
        label.textColor = level.textColor
        layer?.backgroundColor = level.fillColor.cgColor
    }
}

private final class GlanceAppBlock: NSView {
    private let heading = glanceLabel("Top Apps", size: 14, weight: .medium, color: GlanceTheme.secondary)
    private let note = glanceLabel("", size: 13, weight: .regular, color: GlanceTheme.secondary)
    private let rows = (0..<5).map { _ in GlanceAppRow(frame: .zero) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        note.maximumNumberOfLines = 2
        note.lineBreakMode = .byWordWrapping
        note.cell?.wraps = true
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var arranged: [NSView] = [heading]
        arranged.append(contentsOf: rows)
        arranged.append(note)
        let column = glanceColumn(arranged, spacing: 6)
        column.detachesHiddenViews = true
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(title: String, slots: [(id: String, icon: NSImage?, name: String, value: String, fraction: CGFloat)], tint: NSColor, emptyNote: String?) {
        heading.stringValue = title
        if let emptyNote {
            note.stringValue = emptyNote
            note.isHidden = false
            rows.forEach { $0.isHidden = true }
            return
        }
        note.isHidden = true
        for (index, row) in rows.enumerated() {
            guard index < slots.count else {
                row.isHidden = true
                continue
            }
            let slot = slots[index]
            row.isHidden = false
            row.apply(id: slot.id, icon: slot.icon, name: slot.name, value: slot.value, fraction: slot.fraction, tint: tint)
        }
    }
}

private func glanceHeroNumber(_ text: String, size: CGFloat) -> NSTextField {
    let field = glanceLabel(text, size: size, weight: .semibold, color: GlanceTheme.primary)
    field.setContentHuggingPriority(.required, for: .horizontal)
    field.setContentCompressionResistancePriority(.required, for: .horizontal)
    return field
}

private func glanceBaseline(_ views: [NSView], spacing: CGFloat) -> NSStackView {
    let row = NSStackView(views: views)
    row.orientation = .horizontal
    row.alignment = .firstBaseline
    row.spacing = spacing
    row.setContentHuggingPriority(.required, for: .vertical)
    return row
}

private func glanceChart(_ color: NSColor) -> GlanceAreaChart {
    let chart = GlanceAreaChart(frame: .zero)
    chart.color = color
    chart.translatesAutoresizingMaskIntoConstraints = false
    chart.widthAnchor.constraint(equalToConstant: 150).isActive = true
    chart.heightAnchor.constraint(equalToConstant: 72).isActive = true
    return chart
}

// MARK: - CPU

private final class CPUSection: NSView {
    private let value = glanceHeroNumber("—", size: 44)
    private let unit = glanceLabel("%", size: 16, weight: .medium, color: GlanceTheme.secondary)
    private let model = glanceLabel("", size: 14, weight: .regular, color: GlanceTheme.secondary)
    private let chart = glanceChart(GlanceTheme.accent(.cpu))
    private let user = GlanceFactLine()
    private let system = GlanceFactLine()
    private let load = GlanceFactLine()
    private let apps = GlanceAppBlock()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let numbers = glanceBaseline([value, unit], spacing: 4)
        let left = glanceColumn([numbers, model], spacing: 2)
        let hero = NSStackView(views: [left, chart])
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.distribution = .equalSpacing
        let column = glanceColumn([
            hero,
            glanceHairline(),
            user,
            system,
            load,
            glanceHairline(),
            apps
        ], spacing: 10)
        pin(column)
    }

    required init?(coder: NSCoder) { nil }

    func render(_ state: DashState) {
        let hero = GlanceFormat.percentHero(state.cpuNow)
        value.stringValue = hero
        unit.isHidden = hero == "—"
        let name = GlanceHost.modelName
        model.stringValue = name
        model.isHidden = name.isEmpty
        chart.values = state.cpuSeries
        user.set(label: "User", value: GlanceFormat.percentWhole(state.cpuUserShare))
        system.set(label: "System", value: GlanceFormat.percentWhole(state.cpuSystemShare))
        load.set(label: "Load Average", value: GlanceFormat.load(state.cpuLoad))
        let ranked = state.apps.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5)
        apps.render(
            title: "Top Apps",
            slots: ranked.map { app in
                let cpu = app.cpuPercent
                return (
                    app.id, app.icon,
                    app.name,
                    GlanceFormat.percentApp(cpu),
                    cpu.isFinite ? CGFloat(min(1, max(0, cpu / 100))) : 0
                )
            },
            tint: GlanceTheme.accent(.cpu),
            emptyNote: ranked.isEmpty ? "No apps yet." : nil
        )
    }

    private func pin(_ column: NSView) {
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

// MARK: - Memory

private final class MemorySection: NSView {
    private let value = glanceHeroNumber("—", size: 44)
    private let unit = glanceLabel("GB", size: 16, weight: .medium, color: GlanceTheme.secondary)
    private let chart = glanceChart(GlanceTheme.accent(.memory))
    private let ofLabel = glanceLabel("of —", size: 14, weight: .regular, color: GlanceTheme.secondary)
    private let pill = GlanceLevelPill()
    private let segments = GlanceSegments()
    private let appLine = GlanceFactLine()
    private let wiredLine = GlanceFactLine()
    private let compressedLine = GlanceFactLine()
    private let swapLine = GlanceFactLine()
    private let apps = GlanceAppBlock()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        segments.translatesAutoresizingMaskIntoConstraints = false
        segments.heightAnchor.constraint(equalToConstant: 10).isActive = true
        let numbers = glanceBaseline([value, unit], spacing: 4)
        let hero = NSStackView(views: [numbers, chart])
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.distribution = .equalSpacing
        let ofRow = NSStackView(views: [ofLabel, pill])
        ofRow.orientation = .horizontal
        ofRow.alignment = .centerY
        ofRow.spacing = 8
        let column = glanceColumn([
            hero,
            ofRow,
            segments,
            appLine,
            wiredLine,
            compressedLine,
            swapLine,
            glanceHairline(),
            apps
        ], spacing: 8)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ state: DashState) {
        let pair = GlanceFormat.bytePair(state.memoryUsed)
        value.stringValue = pair.number
        unit.stringValue = pair.unit
        chart.values = state.memorySeries
        ofLabel.stringValue = "of " + GlanceFormat.byteText(state.memoryTotal)
        pill.apply(GlanceMemoryLevel.level(used: state.memoryUsed, total: state.memoryTotal))
        let total = state.memoryTotal
        segments.parts = [
            (GlanceFormat.fraction(state.memoryApp, of: total), GlanceTheme.accent(.cpu)),
            (GlanceFormat.fraction(state.memoryWired, of: total), GlanceTheme.accent(.disk)),
            (GlanceFormat.fraction(state.memoryCompressed, of: total), GlanceTheme.accent(.network))
        ]
        appLine.set(label: "App", value: GlanceFormat.byteText(state.memoryApp), dot: GlanceTheme.accent(.cpu))
        wiredLine.set(label: "Wired", value: GlanceFormat.byteText(state.memoryWired), dot: GlanceTheme.accent(.disk))
        compressedLine.set(label: "Compressed", value: GlanceFormat.byteText(state.memoryCompressed), dot: GlanceTheme.accent(.network))
        swapLine.set(label: "Swap Used", value: GlanceFormat.byteText(state.memorySwap))
        let ranked = state.apps.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5)
        apps.render(
            title: "Top Apps",
            slots: ranked.map { app in
                (
                    app.id, app.icon,
                    app.name,
                    GlanceFormat.byteText(app.memoryBytes),
                    GlanceFormat.fraction(app.memoryBytes, of: max(total, 1))
                )
            },
            tint: GlanceTheme.accent(.memory),
            emptyNote: ranked.isEmpty ? "No apps yet." : nil
        )
    }
}

// MARK: - Disk

private final class DiskSection: NSView {
    private let value = glanceHeroNumber("—", size: 44)
    private let unit = glanceLabel("GB free", size: 16, weight: .medium, color: GlanceTheme.secondary)
    private let subtitle = glanceLabel("—", size: 13, weight: .regular, color: GlanceTheme.secondary)
    private let meter = GlanceMeter()
    private let reading = GlanceFactLine()
    private let writing = GlanceFactLine()
    private let apps = GlanceAppBlock()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.fillColor = GlanceTheme.accent(.disk)
        meter.trackColor = NSColor(srgbRed: 0.35, green: 0.28, blue: 0.16, alpha: 1)
        NSLayoutConstraint.activate([
            meter.widthAnchor.constraint(equalToConstant: 120),
            meter.heightAnchor.constraint(equalToConstant: 8)
        ])
        let numbers = glanceBaseline([value, unit], spacing: 6)
        let subRow = NSStackView(views: [subtitle, meter])
        subRow.orientation = .horizontal
        subRow.alignment = .centerY
        subRow.spacing = 12
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let column = glanceColumn([
            numbers,
            subRow,
            reading,
            writing,
            glanceHairline(),
            apps
        ], spacing: 10)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ state: DashState) {
        value.stringValue = GlanceFormat.diskNumber(state.diskFree)
        let total = state.diskUsed + state.diskFree
        subtitle.stringValue = "\(GlanceFormat.diskNumber(state.diskUsed)) GB used of \(GlanceFormat.diskNumber(total)) GB"
        meter.fraction = GlanceFormat.fraction(state.diskUsed, of: total)
        reading.set(label: "Reading", value: GlanceFormat.rate(state.diskReadPerSecond))
        writing.set(label: "Writing", value: GlanceFormat.rate(state.diskWritePerSecond))
        let ranked = state.apps.sorted { $0.diskBytesPerSecond > $1.diskBytesPerSecond }.prefix(5)
        let topRate = ranked.first?.diskBytesPerSecond ?? 0
        apps.render(
            title: "Top Apps by Disk Writes",
            slots: ranked.map { app in
                let rate = app.diskBytesPerSecond
                let fraction: CGFloat
                if topRate > 0, rate.isFinite {
                    fraction = CGFloat(min(1, max(0, rate / topRate)))
                } else {
                    fraction = 0
                }
                return (app.id, app.icon, app.name, GlanceFormat.rate(rate), fraction)
            },
            tint: GlanceTheme.accent(.disk),
            emptyNote: ranked.isEmpty ? "No apps yet." : nil
        )
    }
}

// MARK: - Network

private final class NetworkSection: NSView {
    private let down = glanceHeroNumber("—", size: 36)
    private let up = glanceLabel("—", size: 15, weight: .medium, color: GlanceTheme.secondary)
    private let chart = glanceChart(GlanceTheme.accent(.network))
    private let downloaded = GlanceFactLine()
    private let uploaded = GlanceFactLine()
    private let apps = GlanceAppBlock()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let downArrow = glanceLabel("↓", size: 16, weight: .medium, color: GlanceTheme.secondary)
        let upArrow = glanceLabel("↑", size: 13, weight: .medium, color: GlanceTheme.secondary)
        let downRow = glanceBaseline([downArrow, down], spacing: 6)
        let upRow = glanceBaseline([upArrow, up], spacing: 6)
        let left = glanceColumn([downRow, upRow], spacing: 4)
        let hero = NSStackView(views: [left, chart])
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.distribution = .equalSpacing
        let column = glanceColumn([
            hero,
            downloaded,
            uploaded,
            glanceHairline(),
            apps
        ], spacing: 10)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ state: DashState) {
        down.stringValue = GlanceFormat.rate(state.netDownPerSecond)
        up.stringValue = GlanceFormat.rate(state.netUpPerSecond)
        chart.values = state.netSeries
        downloaded.set(label: "Downloaded This Session", value: GlanceFormat.sessionAmount(state.sessionBytesDown))
        uploaded.set(label: "Uploaded This Session", value: GlanceFormat.sessionAmount(state.sessionBytesUp))
        let measurable = state.apps.filter { $0.networkBytesPerSecond >= 1 }
        if measurable.isEmpty {
            apps.render(
                title: "Top Apps by Download",
                slots: [],
                tint: GlanceTheme.accent(.network),
                emptyNote: "Per-app network isn't available on this Mac."
            )
            return
        }
        let ranked = measurable.sorted { $0.networkBytesPerSecond > $1.networkBytesPerSecond }.prefix(5)
        let topRate = ranked.first?.networkBytesPerSecond ?? 1
        apps.render(
            title: "Top Apps by Download",
            slots: ranked.map { app in
                let rate = app.networkBytesPerSecond
                return (
                    app.id, app.icon,
                    app.name,
                    GlanceFormat.rate(rate),
                    CGFloat(min(1, max(0, rate / topRate)))
                )
            },
            tint: GlanceTheme.accent(.network),
            emptyNote: nil
        )
    }
}

// MARK: - GPU

private final class GPUSection: NSView {
    private let value = glanceHeroNumber("—", size: 44)
    private let unit = glanceLabel("%", size: 16, weight: .medium, color: GlanceTheme.secondary)
    private let chart = glanceChart(GlanceTheme.accent(.gpu))
    private let model = glanceLabel("", size: 14, weight: .regular, color: GlanceTheme.secondary)
    private let memory = GlanceFactLine()
    private let apps = GlanceAppBlock()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let numbers = glanceBaseline([value, unit], spacing: 4)
        let hero = NSStackView(views: [numbers, chart])
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.distribution = .equalSpacing
        let column = glanceColumn([
            hero,
            model,
            memory,
            glanceHairline(),
            apps
        ], spacing: 10)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ state: DashState) {
        let hero = GlanceFormat.percentHero(state.gpuPercent ?? .nan)
        value.stringValue = hero
        unit.isHidden = hero == "—"
        chart.values = state.gpuSeries
        let name = state.gpuName.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = name.isEmpty ? GlanceHost.modelName : name
        model.stringValue = modelName
        model.isHidden = modelName.isEmpty
        if let bytes = state.gpuMemoryBytes {
            memory.set(label: "GPU Memory in Use", value: GlanceFormat.byteText(bytes))
        } else {
            memory.set(label: "GPU Memory in Use", value: "—")
        }
        let measured = state.apps.filter { $0.gpuPercent != nil }
        if measured.isEmpty {
            apps.render(
                title: "Top Apps",
                slots: [],
                tint: GlanceTheme.accent(.gpu),
                emptyNote: "Per-app GPU isn't available on this Mac."
            )
            return
        }
        let ranked = measured.sorted { ($0.gpuPercent ?? 0) > ($1.gpuPercent ?? 0) }.prefix(5)
        apps.render(
            title: "Top Apps",
            slots: ranked.map { app in
                let percent = app.gpuPercent ?? 0
                return (
                    app.id, app.icon,
                    app.name,
                    GlanceFormat.percentApp(percent),
                    CGFloat(min(1, max(0, percent / 100)))
                )
            },
            tint: GlanceTheme.accent(.gpu),
            emptyNote: nil
        )
    }
}

// MARK: - Battery

private final class BatterySection: NSView {
    private let absent = glanceLabel("No battery on this Mac.", size: 15, weight: .regular, color: GlanceTheme.secondary)
    private let value = glanceHeroNumber("—", size: 44)
    private let unit = glanceLabel("%", size: 16, weight: .medium, color: GlanceTheme.secondary)
    private let remaining = glanceLabel("—", size: 14, weight: .regular, color: GlanceTheme.secondary)
    private let meter = GlanceMeter()
    private let power = GlanceFactLine()
    private let health = GlanceFactLine()
    private let cycles = GlanceFactLine()
    private let hairline = glanceHairline()
    private let apps = GlanceAppBlock()
    private var details: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.fillColor = GlanceTheme.accent(.battery)
        NSLayoutConstraint.activate([
            meter.widthAnchor.constraint(equalToConstant: 140),
            meter.heightAnchor.constraint(equalToConstant: 8)
        ])
        let numbers = glanceBaseline([value, unit], spacing: 4)
        let left = glanceColumn([numbers, remaining], spacing: 4)
        let hero = NSStackView(views: [left, meter])
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.distribution = .equalSpacing
        details = [hero, power, health, cycles, hairline, apps]
        let column = glanceColumn([absent] + details, spacing: 10)
        column.detachesHiddenViews = true
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ state: DashState) {
        let hasBattery = state.hasBattery
        absent.isHidden = hasBattery
        details.forEach { $0.isHidden = !hasBattery }
        guard hasBattery else { return }
        let hero = GlanceFormat.percentHero(state.batteryPercent ?? .nan)
        value.stringValue = hero
        unit.isHidden = hero == "—"
        remaining.stringValue = GlanceFormat.remaining(state.batteryMinutesRemaining)
        let percent = state.batteryPercent ?? 0
        meter.fraction = percent.isFinite ? CGFloat(min(1, max(0, percent / 100))) : 0
        power.set(label: "Power Draw", value: GlanceFormat.watts(state.batteryWatts))
        if let healthPercent = state.batteryHealthPercent {
            health.set(label: "Maximum Capacity", value: GlanceFormat.percentWhole(healthPercent))
        } else {
            health.set(label: "Maximum Capacity", value: "—")
        }
        if let count = state.batteryCycles {
            cycles.set(label: "Cycle Count", value: String(count))
        } else {
            cycles.set(label: "Cycle Count", value: "—")
        }
        let withWatts = state.apps.filter { $0.powerWatts != nil }
        if !withWatts.isEmpty {
            let ranked = withWatts.sorted { ($0.powerWatts ?? 0) > ($1.powerWatts ?? 0) }.prefix(5)
            let top = ranked.first?.powerWatts ?? 1
            apps.render(
                title: "Top Apps by Power",
                slots: ranked.map { app in
                    let watts = app.powerWatts ?? 0
                    let fraction = top > 0 ? CGFloat(min(1, max(0, watts / top))) : 0
                    return (app.id, app.icon, app.name, GlanceFormat.watts(watts), fraction)
                },
                tint: GlanceTheme.accent(.battery),
                emptyNote: nil
            )
            return
        }
        let ranked = state.apps.sorted { $0.energy > $1.energy }.prefix(5)
        let maxEnergy = state.apps.map(\.energy).max() ?? 0
        apps.render(
            title: "Top Apps by Energy",
            slots: ranked.map { app in
                let share = maxEnergy > 0 ? Double(app.energy) / Double(maxEnergy) * 100 : 0
                let fraction: CGFloat = maxEnergy > 0 ? CGFloat(Double(app.energy) / Double(maxEnergy)) : 0
                return (app.id, app.icon, app.name, GlanceFormat.percentApp(share), fraction)
            },
            tint: GlanceTheme.accent(.battery),
            emptyNote: ranked.isEmpty ? "No apps yet." : nil
        )
    }
}
