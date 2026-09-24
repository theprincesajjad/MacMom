import AppKit
import UserNotifications

/// Settings shown from the gear in the menu-bar panel.
final class GlanceSettingsPage: NSView {
    var onAppearanceChange: (() -> Void)?

    private let lightButton = AppearanceChoice(title: "Light", symbol: "sun.max")
    private let darkButton = AppearanceChoice(title: "Dark", symbol: "moon")
    private let notesSwitch = NSSwitch()
    private let notesLabel = glanceLabel("Notifications", size: 15, weight: .medium, color: GlanceTheme.primary)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let title = glanceLabel("Settings", size: 22, weight: .semibold, color: GlanceTheme.primary)
        let appearanceLabel = glanceLabel("Appearance", size: 13, weight: .medium, color: GlanceTheme.secondary)

        lightButton.onClick = { [weak self] in
            MacMomPreferences.isDark = false
            self?.sync()
            self?.onAppearanceChange?()
        }
        darkButton.onClick = { [weak self] in
            MacMomPreferences.isDark = true
            self?.sync()
            self?.onAppearanceChange?()
        }

        let choices = NSStackView(views: [lightButton, darkButton])
        choices.orientation = .horizontal
        choices.distribution = .fillEqually
        choices.spacing = 8
        choices.translatesAutoresizingMaskIntoConstraints = false

        notesSwitch.target = self
        notesSwitch.action = #selector(notesChanged)
        notesSwitch.controlSize = .regular
        notesSwitch.setContentHuggingPriority(.required, for: .horizontal)

        let notesRow = NSStackView(views: [notesLabel, notesSwitch])
        notesRow.orientation = .horizontal
        notesRow.alignment = .centerY
        notesRow.distribution = .fill
        notesRow.translatesAutoresizingMaskIntoConstraints = false
        notesLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let note = glanceLabel("Alerts for sustained high CPU, climbing memory, and heavy disk or network.", size: 12, weight: .regular, color: GlanceTheme.secondary)
        note.maximumNumberOfLines = 3
        note.cell?.wraps = true
        note.lineBreakMode = .byWordWrapping

        let card = GlanceCard()
        let column = glanceColumn([appearanceLabel, choices, glanceHairline(), notesRow, note], spacing: 12)
        card.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            choices.heightAnchor.constraint(equalToConstant: 64),
        ])

        let stack = glanceColumn([title, card], spacing: 14)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        sync()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func sync() {
        lightButton.setSelected(!MacMomPreferences.isDark)
        darkButton.setSelected(MacMomPreferences.isDark)
        notesSwitch.state = MacMomPreferences.notificationsEnabled ? .on : .off
    }

    @objc private func notesChanged() {
        let enabled = notesSwitch.state == .on
        MacMomPreferences.notificationsEnabled = enabled
        if enabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}

private final class AppearanceChoice: NSView {
    var onClick: (() -> Void)?
    private let titleField: NSTextField
    private let iconView = NSImageView()
    private var armed = false
    private var selected = false

    init(title: String, symbol: String) {
        titleField = glanceLabel(title, size: 14, weight: .semibold, color: GlanceTheme.primary)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        iconView.image = GlanceTheme.symbol(symbol, pointSize: 16, tint: GlanceTheme.primary)
        iconView.contentTintColor = GlanceTheme.primary
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let row = NSStackView(views: [iconView, titleField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let fill = selected ? GlanceTheme.accent(.cpu).withAlphaComponent(0.22) : GlanceTheme.control
        layer?.backgroundColor = GlanceTheme.paint(fill, effectiveAppearance)
        layer?.borderWidth = selected ? 1.5 : 0
        layer?.borderColor = GlanceTheme.paint(GlanceTheme.accent(.cpu), effectiveAppearance)
    }

    override func mouseDown(with event: NSEvent) {
        armed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        if armed, bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
        armed = false
    }
}
