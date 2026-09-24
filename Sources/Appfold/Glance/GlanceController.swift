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
    private weak var statusButton: NSStatusBarButton?
    /// The status-item click that closed the panel also sends the button action. Ignore that reopen.
    private var suppressOpen = false

    var onOpen: (() -> Void)?
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
        glance.onQuit = { [weak self] in self?.onQuit?() }
        glance.onAppearanceChange = { [weak self] in self?.applyPreferredAppearance() }
        applyPreferredAppearance()
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
        statusButton = button
        if suppressOpen {
            suppressOpen = false
            if panel.isVisible { close() }
            return
        }
        if panel.isVisible {
            close()
            return
        }
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

    func applyPreferredAppearance() {
        let appearance = MacMomPreferences.appearance
        panel.appearance = appearance
        glance.appearance = appearance
        glance.needsDisplay = true
    }

    func render(_ state: DashState) {
        glance.render(state)
    }

    func close() {
        removeMonitors()
        panel.orderOut(nil)
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseUp {
                if self.suppressOpen {
                    DispatchQueue.main.async { [weak self] in self?.suppressOpen = false }
                }
                return event
            }
            guard self.panel.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.close()
                return nil
            }
            if event.type == .leftMouseDown, self.clickIsOnStatusButton() {
                self.suppressOpen = true
                self.close()
                return nil
            }
            if event.type == .leftMouseDown, !self.eventStaysOpen(event) {
                self.close()
            }
            return event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            if self.clickIsOnStatusButton() {
                self.suppressOpen = true
                self.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.suppressOpen = false
                }
                return
            }
            if self.panel.frame.contains(NSEvent.mouseLocation) { return }
            self.close()
        }
    }

    private func clickIsOnStatusButton() -> Bool {
        guard let button = statusButton, let window = button.window else { return false }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        return rect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
    }

    /// Clicks on the glance, or on the quit menu that hangs off it, must not close the panel first.
    private func eventStaysOpen(_ event: NSEvent) -> Bool {
        if event.window === panel { return true }
        if panel.frame.contains(NSEvent.mouseLocation) { return true }
        let name = event.window.map { String(describing: type(of: $0)) } ?? ""
        return name.contains("Menu")
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
