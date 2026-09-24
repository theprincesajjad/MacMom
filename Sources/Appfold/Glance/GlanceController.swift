import AppKit

/// Borderless panel for the menu-bar glance. It never becomes the main window,
/// so the Appfold dashboard stays the only normal window.
final class GlanceWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows and hides the menu-bar glance under the status item.
final class GlanceController: NSObject, NSWindowDelegate {
    let glance: GlancePanel
    private let panel: GlanceWindow
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    /// Set when this click already dismissed the panel, so the status item does not reopen it.
    private var suppressOpen = false

    var onOpen: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    var isVisible: Bool { panel.isVisible }
    var selectedTab: DashTab { glance.selectedTab }

    override init() {
        let size = GlancePanel.preferredSize
        glance = GlancePanel(frame: NSRect(origin: .zero, size: size))
        panel = GlanceWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        glance.onOpen = { [weak self] in self?.onOpen?() }
        glance.onSettings = { [weak self] in self?.onSettings?() }
        glance.onQuit = { [weak self] in self?.onQuit?() }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        glance.autoresizingMask = [.width, .height]
        panel.contentView = glance
        panel.delegate = self
    }

    func toggle(from button: NSStatusBarButton?) {
        if panel.isVisible {
            dismiss()
            return
        }
        if suppressOpen { return }
        show(from: button)
    }

    func show(from button: NSStatusBarButton?) {
        let screen = button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        var size = GlancePanel.preferredSize
        size.width = min(size.width, max(280, visible.width - 24))
        size.height = min(size.height, max(320, visible.height - 12))
        panel.setContentSize(size)

        var origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 8)
        if let button, let buttonWindow = button.window {
            let rect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            origin.x = rect.maxX - size.width
            origin.y = rect.minY - size.height - 6
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
    }

    func render(_ state: DashState) {
        glance.render(state)
    }

    func close() {
        removeMonitors()
        panel.orderOut(nil)
    }

    private func dismiss() {
        suppressOpen = true
        close()
        DispatchQueue.main.async { [weak self] in
            self?.suppressOpen = false
        }
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if event.window !== self.panel {
                    self.dismiss()
                }
            }
            return event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        removeMonitors()
    }
}
