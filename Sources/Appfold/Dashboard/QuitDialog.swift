import AppKit

/// Confirm step shown before any process is signaled.
enum QuitConfirmation {
    @discardableResult
    static func ask(title: String, message: String, confirmTitle: String, icon: NSImage?, destructive: Bool) -> Bool {
        let dialog = QuitDialog(
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            icon: icon,
            destructive: destructive
        )
        return dialog.run()
    }

    static func failed(name: String) {
        let dialog = QuitDialog(
            title: "Couldn't quit \(name)",
            message: "macOS did not let MacMom close it.",
            confirmTitle: "OK",
            icon: nil,
            destructive: false,
            singleButton: true
        )
        _ = dialog.run()
    }
}

/// Right-click menu for an app, process, or project row.
enum RowContextMenu {
    static func popUp(_ event: NSEvent, in view: NSView, items: [(String, String, () -> Void)]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.font = .systemFont(ofSize: 13)
        for item in items {
            let command = MenuCommand(item.2)
            let entry = NSMenuItem(title: item.0, action: #selector(MenuCommand.run(_:)), keyEquivalent: "")
            entry.target = command
            entry.representedObject = command
            entry.isEnabled = true
            if let image = NSImage(systemSymbolName: item.1, accessibilityDescription: nil) {
                image.isTemplate = true
                image.size = NSSize(width: 14, height: 14)
                entry.image = image
            }
            menu.addItem(entry)
        }
        let point = view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: point, in: view)
    }
}

private final class MenuCommand: NSObject {
    let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run(_ sender: Any?) {
        handler()
    }
}

private final class QuitPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel?()
        case 36, 76:
            onConfirm?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class QuitDialog: NSObject {
    private let panel: QuitPanel
    private var code: NSApplication.ModalResponse = .cancel

    init(title: String, message: String, confirmTitle: String, icon: NSImage?, destructive: Bool, singleButton: Bool = false) {
        panel = QuitPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 250),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.isReleasedWhenClosed = false
        panel.level = .modalPanel
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces]

        panel.appearance = NSAppearance(named: .darkAqua)

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = Self.cardFill.cgColor
        card.layer?.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false

        let well = NSView()
        well.wantsLayer = true
        well.layer?.backgroundColor = Self.wellFill.cgColor
        well.layer?.cornerRadius = 16
        well.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 12
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let icon {
            let shown = icon.copy() as? NSImage ?? icon
            shown.size = NSSize(width: 64, height: 64)
            iconView.image = shown
            well.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            iconView.image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            iconView.contentTintColor = Self.messageFill
        }
        well.addSubview(iconView)

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 17, weight: .semibold)
        titleField.textColor = .white
        titleField.alignment = .center
        titleField.lineBreakMode = .byWordWrapping
        titleField.maximumNumberOfLines = 2
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let messageField = NSTextField(labelWithString: message)
        messageField.font = .systemFont(ofSize: 13, weight: .regular)
        messageField.textColor = Self.messageFill
        messageField.alignment = .center
        messageField.lineBreakMode = .byWordWrapping
        messageField.maximumNumberOfLines = 3
        messageField.translatesAutoresizingMaskIntoConstraints = false

        let cancel = DialogButton(title: "Cancel", fill: Self.cancelFill, foreground: .white)
        cancel.onAction = { [weak self] in self?.cancelPressed() }

        let confirmFill = destructive ? Self.forceFill : Self.quitFill
        let confirm = DialogButton(title: confirmTitle, fill: confirmFill, foreground: .white)
        confirm.onAction = { [weak self] in self?.confirmPressed() }

        let buttons = NSStackView(views: singleButton ? [confirm] : [cancel, confirm])
        buttons.orientation = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(well)
        card.addSubview(titleField)
        card.addSubview(messageField)
        card.addSubview(buttons)
        panel.contentView = card

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 320),

            well.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            well.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            well.widthAnchor.constraint(equalToConstant: 72),
            well.heightAnchor.constraint(equalToConstant: 72),
            iconView.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleField.topAnchor.constraint(equalTo: well.bottomAnchor, constant: 14),
            titleField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            messageField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),
            messageField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            messageField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            buttons.topAnchor.constraint(equalTo: messageField.bottomAnchor, constant: 18),
            buttons.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            buttons.heightAnchor.constraint(equalToConstant: 36),
            buttons.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        panel.onCancel = { [weak self] in self?.cancelPressed() }
        panel.onConfirm = { [weak self] in self?.confirmPressed() }
    }

    private static let cardFill = NSColor(srgbRed: 0.173, green: 0.173, blue: 0.180, alpha: 1)
    private static let wellFill = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    private static let messageFill = NSColor(srgbRed: 0.62, green: 0.63, blue: 0.66, alpha: 1)
    private static let cancelFill = NSColor(srgbRed: 0.27, green: 0.27, blue: 0.29, alpha: 1)
    private static let quitFill = NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)
    private static let forceFill = NSColor(srgbRed: 0.96, green: 0.26, blue: 0.21, alpha: 1)

    func run() -> Bool {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.setContentSize(NSSize(width: 320, height: 248))
        panel.center()
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return code == .OK
    }

    @objc private func confirmPressed() {
        code = .OK
        NSApp.stopModal()
    }

    @objc private func cancelPressed() {
        code = .cancel
        NSApp.stopModal()
    }

}

private final class DialogButton: NSView {
    var onAction: (() -> Void)?
    private var armed = false
    private let label = NSTextField(labelWithString: "")

    init(title: String, fill: NSColor, foreground: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = 10
        label.stringValue = title
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = foreground
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilityTitle(title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        armed = true
        alphaValue = 0.82
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = 1
        if armed, bounds.contains(convert(event.locationInWindow, from: nil)) {
            onAction?()
        }
        armed = false
    }

    override func accessibilityPerformPress() -> Bool {
        onAction?()
        return true
    }
}
