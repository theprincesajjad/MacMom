import AppKit

/// Projects glance. Lists dev servers already measured on `DashState`.
final class GlanceProjectsPage: NSView {
    var onOpen: (() -> Void)?

    private let countField = glanceLabel("—", size: 44, weight: .semibold, color: GlanceTheme.primary)
    private let subtitleField = glanceLabel(
        "Looking for dev servers…",
        size: 14,
        weight: .regular,
        color: GlanceTheme.secondary
    )
    private let runningField = glanceLabel("Running Now", size: 15, weight: .medium, color: GlanceTheme.secondary)
    private let emptyField = glanceLabel(
        "No dev servers running",
        size: 14,
        weight: .regular,
        color: GlanceTheme.secondary
    )
    private let overflowField = glanceLabel("", size: 13, weight: .regular, color: GlanceTheme.secondary)
    private let rows = (0..<6).map { _ in GlanceProjectRow() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let title = glanceLabel("projects", size: 20, weight: .medium, color: GlanceTheme.primary)
        for label in [countField, title] {
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        countField.setContentCompressionResistancePriority(.required, for: .horizontal)

        let cluster = NSStackView(views: [countField, title])
        cluster.orientation = .horizontal
        cluster.alignment = .lastBaseline
        cluster.distribution = .fill
        cluster.spacing = 8
        cluster.translatesAutoresizingMaskIntoConstraints = false
        cluster.setContentHuggingPriority(.required, for: .horizontal)
        cluster.setContentHuggingPriority(.required, for: .vertical)
        cluster.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let hero = NSView()
        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.addSubview(cluster)
        hero.setContentHuggingPriority(.required, for: .vertical)
        hero.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            cluster.leadingAnchor.constraint(equalTo: hero.leadingAnchor),
            cluster.topAnchor.constraint(equalTo: hero.topAnchor),
            cluster.bottomAnchor.constraint(equalTo: hero.bottomAnchor),
            cluster.trailingAnchor.constraint(lessThanOrEqualTo: hero.trailingAnchor)
        ])

        for field in [subtitleField, runningField, emptyField, overflowField] {
            field.setContentHuggingPriority(.required, for: .vertical)
        }
        runningField.isHidden = true
        emptyField.isHidden = true
        overflowField.isHidden = true
        for row in rows {
            row.isHidden = true
        }
        overflowField.addGestureRecognizer(GlanceClick { [weak self] in
            self?.onOpen?()
        })

        let eyebrow = glanceEyebrow("Projects")
        eyebrow.setContentHuggingPriority(.required, for: .vertical)

        var arranged: [NSView] = [hero, subtitleField, glanceHairline(), runningField]
        arranged.append(contentsOf: rows)
        arranged.append(emptyField)
        arranged.append(overflowField)

        let card = GlanceCard(frame: .zero)
        card.setContentHuggingPriority(.required, for: .vertical)
        let body = glanceColumn(arranged, spacing: 10)
        body.detachesHiddenViews = true
        card.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        let column = glanceColumn([eyebrow, card], spacing: 12)
        column.setContentHuggingPriority(.required, for: .vertical)
        column.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func render(_ state: DashState) {
        let projects = state.projects.sorted { $0.memoryBytes > $1.memoryBytes }
        if projects.isEmpty && !state.projectsScanned {
            countField.stringValue = "—"
            subtitleField.stringValue = "Looking for dev servers…"
            runningField.isHidden = true
            emptyField.isHidden = true
            overflowField.isHidden = true
            for row in rows {
                row.isHidden = true
            }
            return
        }

        countField.stringValue = String(projects.count)
        subtitleField.stringValue = usageLine(projects)
        runningField.isHidden = false
        emptyField.isHidden = !projects.isEmpty
        for (offset, row) in rows.enumerated() {
            if offset < projects.count {
                row.apply(projects[offset])
                row.isHidden = false
            } else {
                row.isHidden = true
            }
        }
        let extra = projects.count - rows.count
        if extra > 0 {
            overflowField.stringValue = "and \(extra) more in Appfold"
            overflowField.isHidden = false
        } else {
            overflowField.isHidden = true
        }
    }

    private func usageLine(_ projects: [DashProject]) -> String {
        let memory = projects.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let ports = projects.reduce(0) { $0 + $1.ports.count }
        let amount = GlanceFormat.byteText(memory)
        if ports == 1 {
            return "\(amount) · 1 port open"
        }
        return "\(amount) · \(ports) ports open"
    }
}

private final class GlanceProjectRow: NSView {
    private let iconView = NSImageView()
    private let nameField = glanceLabel("", size: 15, weight: .medium, color: GlanceTheme.primary)
    private let memoryField = glanceLabel("", size: 14, weight: .medium, color: GlanceTheme.primary)
    private let pills = (0..<3).map { _ in GlancePortPill() }
    private let pillRow = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.image = GlanceTheme.symbol("folder.fill", pointSize: 15, tint: GlanceTheme.accent(.projects))
        iconView.contentTintColor = GlanceTheme.accent(.projects)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        memoryField.alignment = .right
        memoryField.setContentHuggingPriority(.required, for: .horizontal)
        memoryField.setContentCompressionResistancePriority(.required, for: .horizontal)

        pillRow.orientation = .horizontal
        pillRow.alignment = .centerY
        pillRow.spacing = 4
        pillRow.detachesHiddenViews = true
        pillRow.translatesAutoresizingMaskIntoConstraints = false
        pillRow.setContentHuggingPriority(.required, for: .horizontal)
        pillRow.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        for pill in pills {
            pillRow.addArrangedSubview(pill)
        }
        pillRow.isHidden = true

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let line = NSStackView(views: [iconView, nameField, pillRow, spacer, memoryField])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.distribution = .fill
        line.spacing = 8
        line.detachesHiddenViews = true
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
            spacer.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ project: DashProject) {
        nameField.stringValue = project.name
        memoryField.stringValue = GlanceFormat.byteText(project.memoryBytes)
        let shown = Array(project.ports.prefix(3))
        for index in pills.indices {
            if index < shown.count {
                pills[index].setPort(shown[index])
                pills[index].isHidden = false
            } else {
                pills[index].isHidden = true
            }
        }
        pillRow.isHidden = shown.isEmpty
    }
}

private final class GlancePortPill: NSView {
    private let label = glanceLabel("", size: 11, weight: .medium, color: GlanceTheme.portText)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.backgroundColor = GlanceTheme.portFill.cgColor
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        label.alignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func setPort(_ port: Int) {
        label.stringValue = String(port)
    }
}
