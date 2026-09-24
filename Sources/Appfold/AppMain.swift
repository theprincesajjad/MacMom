import AppKit
import AppfoldCore
import Darwin
import UniformTypeIdentifiers
import UserNotifications

private final class AppBox {
    static var delegate: AppDelegate?
}

@main
struct AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppBox.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let sampler = SystemSampler()
    private var schedule = SampleSchedule(windowVisible: false)
    private var historyWriter = HistoryWriter()
    private var alertRing = AlertRing()
    private lazy var historyStore = HistoryStore(fileURL: supportDirectory().appendingPathComponent("history.jsonl"))

    private var snapshot: SystemSnapshot?
    private var alerts: [UsageAlert] = []
    private var announcedAlertIDs: Set<String> = []
    private var selectedAppID: String?
    private var selectedProcessPID: Int32?
    private var selectedHistoryRange: HistoryRange = .last12Hours
    private var isRendering = false

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private lazy var glanceController: GlanceController = {
        let controller = GlanceController()
        controller.onOpen = { [weak self] in
            self?.openMainWindow(nil)
        }
        controller.onSettings = { [weak self] in
            self?.showGlanceExportMenu()
        }
        controller.onQuit = {
            NSApp.terminate(nil)
        }
        GlanceActions.quitApp = { [weak self] id, force in
            self?.quitApp(id: id, force: force)
        }
        return controller
    }()
    private var sessionDownAccum: UInt64 = 0
    private var sessionUpAccum: UInt64 = 0
    private var menuPanel: PanelUI?
    private var windowPanel: PanelUI?
    private var mainWindow: NSWindow?
    private var dashboard: DashboardRoot?
    private var cpuSeries: [Double] = []
    private var memorySeries: [Double] = []
    private var diskSeries: [Double] = []
    private var netSeries: [Double] = []
    private var gpuSeries: [Double] = []
    private var batterySeries: [Double] = []
    private var sessionNetBytes: Double = 0
    private var sessionDiskWrite: Double = 0
    private var lastSeriesAt: Date?
    private var cpuSum: Double = 0
    private var cpuCount: Int = 0
    private var gpuSum: Double = 0
    private var gpuCount: Int = 0
    private var gpuPeak: Double?
    private var liveProjects: [ProjectGroup] = []
    private var projectsScanned = false
    private var lastProjectScan: Date?
    private var projectBusy: [String: Date] = [:]
    private var cachedBattery = BatteryStatus(hasBattery: false, onACPower: true, percent: nil, minutesRemaining: nil, cycleCount: nil, healthPercent: nil, watts: nil, temperatureC: nil)
    private var cachedMemory = MemoryBreakdown(appBytes: 0, wiredBytes: 0, compressedBytes: 0, cachedBytes: 0, freeBytes: 0, swapBytes: 0, totalBytes: 0)
    private var cachedVolumes: [VolumeInfo] = []
    private var cachedInterface = InterfaceInfo(bsdName: "", kind: "", bytesIn: 0, bytesOut: 0)
    private var cachedGPU = GPUStatus(name: "", utilizationPercent: nil, memoryBytes: nil)
    private var hostReadAt: Date?
    private var lastBytesIn: UInt64?
    private var lastBytesOut: UInt64?
    private var uploadPerSecond: Double = 0
    private var downloadPerSecond: Double = 0
    private var iconCache: [String: NSImage] = [:]
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        installStatusItem()
        installTerminateOnSignal()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Keep the usage sample timer running"
        )
        let now = Date()
        refresh(now: now)
        schedule.markSampled(at: now)
        scheduleNext()
        if ProcessInfo.processInfo.environment["APPFOLD_SHOW_WINDOW"] == "1" {
            openMainWindow(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == mainWindow else { return }
        if !glanceController.isVisible {
            schedule.windowVisible = false
            scheduleNext()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Menu bar and main window both render this snapshot. Nothing is sampled
    /// again until `SampleSchedule` says the hidden or visible interval has elapsed.
    private func refresh(now: Date) {
        let snapshot = sampler.takeSnapshot(now: now)
        self.snapshot = snapshot
        SnapshotFile.write(snapshot)
        alertRing.add(from: snapshot)
        alerts = AlertRules.evaluate(series: alertRing.series(), policy: .standard)
        publishAlerts()
        historyWriter.write(snapshot: snapshot, store: historyStore)
        recordSeries(snapshot, now: now)
        updateStatusItem()
        let windowOpen = mainWindow?.isVisible == true
        let glanceOpen = glanceController.isVisible
        if windowOpen || glanceOpen {
            ensureHost(now: now)
            if let snapshot = self.snapshot {
                ensureProjects(now: now, snapshot: snapshot)
            }
        }
        if windowOpen {
            renderDashboard(now: now)
        }
        if glanceOpen, let snapshot = self.snapshot {
            noteProjectBusy(now: now)
            glanceController.render(makeDashState(snapshot, now: now))
        }
        if popover?.isShown == true {
            renderLists()
        }
    }

    private func refreshNow() {
        let now = Date()
        refresh(now: now)
        schedule.markSampled(at: now)
        scheduleNext()
    }

    private func scheduleNext() {
        timer?.invalidate()
        let interval = schedule.interval
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = min(1, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        if schedule.shouldSample(at: now) {
            refresh(now: now)
        }
        scheduleNext()
    }

    private func installTerminateOnSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        termSource = source
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "Open Activity")
        let open = NSMenuItem(title: "Open Activity", action: #selector(openMainWindow(_:)), keyEquivalent: "o")
        open.target = self
        appMenu.addItem(open)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Open Activity", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    private func statusMark() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 1.2, y: 6))
            path.line(to: NSPoint(x: 4.5, y: 6))
            path.line(to: NSPoint(x: 7.2, y: 12.4))
            path.line(to: NSPoint(x: 10.2, y: 3.2))
            path.line(to: NSPoint(x: 14.6, y: 8.2))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = statusMark()
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.title = " —"
            button.toolTip = "Open Activity"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        statusItem = item
    }

    private func updateStatusItem() {
        guard let snapshot else {
            statusItem?.button?.title = " —"
            return
        }
        let figure = String(format: " %.0f%%", snapshot.systemCPUPercent)
        statusItem?.button?.title = alerts.isEmpty ? figure : "!" + figure
        statusItem?.button?.toolTip = alerts.isEmpty ? "Open Activity" : alerts.map(\.message).joined(separator: "\n")
    }

    /// Posts a notification the first time an alert appears, and drops it when the alert clears.
    private func publishAlerts() {
        let current = AlertFeed.ids(alerts)
        let fresh = AlertFeed.fresh(previous: announcedAlertIDs, alerts: alerts)
        let retired = announcedAlertIDs.subtracting(current)
        announcedAlertIDs = current
        let center = UNUserNotificationCenter.current()
        if !retired.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: Array(retired))
        }
        guard !fresh.isEmpty else { return }
        center.getNotificationSettings { settings in
            let allowed: Set<UNAuthorizationStatus> = [.authorized, .provisional]
            guard allowed.contains(settings.authorizationStatus) else { return }
            for note in fresh {
                let content = UNMutableNotificationContent()
                content.title = note.title
                content.body = note.body
                content.sound = .default
                center.add(UNNotificationRequest(identifier: note.id, content: content, trigger: nil))
            }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        glanceController.toggle(from: statusItem?.button)
        if glanceController.isVisible {
            schedule.windowVisible = true
            refreshNow()
        } else if mainWindow?.isVisible != true {
            schedule.windowVisible = false
            scheduleNext()
        }
    }

    @objc private func showGlanceExportMenu() {
        let menu = NSMenu()
        let copy = NSMenuItem(title: "Copy Share Card", action: #selector(copyShareCard(_:)), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        let save = NSMenuItem(title: "Save Share Card…", action: #selector(saveShareCard(_:)), keyEquivalent: "")
        save.target = self
        menu.addItem(save)
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: glanceController.glance)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc private func copyShareCard(_ sender: Any?) {
        guard let state = currentDashState() else {
            NSSound.beep()
            return
        }
        GlanceExport.copyToPasteboard(GlanceExport.shareCard(state: state))
    }

    @objc private func saveShareCard(_ sender: Any?) {
        guard let state = currentDashState() else {
            NSSound.beep()
            return
        }
        let image = GlanceExport.shareCard(state: state)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Appfold.png"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = GlanceExport.pngData(image) else { return }
            try? data.write(to: url)
        }
    }

    private func currentDashState() -> DashState? {
        guard let snapshot else { return nil }
        let now = Date()
        ensureHost(now: now)
        ensureProjects(now: now, snapshot: snapshot)
        return makeDashState(snapshot, now: now)
    }

    @objc private func openMainWindow(_ sender: Any?) {
        if mainWindow == nil {
            mainWindow = makeWindow()
        }
        if let name = ProcessInfo.processInfo.environment["APPFOLD_TAB"],
           let match = DashTab.allCases.first(where: { $0.title.lowercased() == name.lowercased() }) {
            dashboard?.selectedTab = match
        }
        schedule.windowVisible = true
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        glanceController.close()
        if let snapshot {
            renderDashboard(now: Date(), snapshot: snapshot)
        }
        scheduleNext()
        popover?.performClose(sender)
    }

    @objc private func historyRangeChanged(_ sender: NSSegmentedControl) {
        let ranges = HistoryRange.allCases
        let index = sender.selectedSegment
        if ranges.indices.contains(index) {
            selectedHistoryRange = ranges[index]
        }
        renderHistory()
    }

    @objc private func quitSelectedApp(_ sender: Any?) {
        quitApp(force: false)
    }

    @objc private func forceQuitSelectedApp(_ sender: Any?) {
        quitApp(force: true)
    }

    @objc private func quitSelectedProcess(_ sender: Any?) {
        quitProcess(force: false)
    }

    @objc private func forceQuitSelectedProcess(_ sender: Any?) {
        quitProcess(force: true)
    }

    private func quitApp(force: Bool) {
        guard let id = selectedAppID else {
            NSSound.beep()
            return
        }
        quitApp(id: id, force: force)
    }

    private func quitApp(id: String, force: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.commitAppQuit(id: id, force: force)
        }
    }

    private func commitAppQuit(id: String, force: Bool) {
        guard let app = snapshot?.apps.first(where: { $0.id == id }) else {
            NSSound.beep()
            return
        }
        guard !app.members.isEmpty else {
            NSSound.beep()
            return
        }
        let prompt = QuitCopy.application(name: app.name, processCount: app.members.count, force: force)
        guard QuitConfirmation.ask(
            title: prompt.title,
            message: prompt.message,
            confirmTitle: prompt.confirmTitle,
            icon: icon(forBundle: app.bundlePath) ?? icon(forBundle: app.members.first?.executablePath),
            destructive: force
        ) else { return }
        let pids = app.members.map(\.pid)
        let runningPID = RunningAppLookup.pid(bundlePath: app.bundlePath, memberPIDs: pids)
        let plan = AppQuitPlanner.plan(memberPIDs: pids, runningApplicationPID: runningPID, force: force)
        if !deliver(plan, fallbackPIDs: pids) {
            QuitConfirmation.failed(name: app.name)
        }
        refreshNow()
    }

    private func quitProcess(force: Bool) {
        guard let pid = selectedProcessPID else {
            NSSound.beep()
            return
        }
        quitProcess(pid: pid, force: force)
    }

    private func quitProcess(pid: Int32, force: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.commitProcessQuit(pid: pid, force: force)
        }
    }

    private func commitProcessQuit(pid: Int32, force: Bool) {
        guard let process = snapshot?.apps.lazy.flatMap(\.members).first(where: { $0.pid == pid }) else {
            NSSound.beep()
            return
        }
        if let owner = snapshot?.apps.first(where: { $0.members.contains { $0.pid == pid } }),
           RunningAppLookup.pid(bundlePath: owner.bundlePath, memberPIDs: owner.members.map(\.pid)) == pid {
            commitAppQuit(id: owner.id, force: force)
            return
        }
        let name = process.name.isEmpty ? "Process" : process.name
        let prompt = QuitCopy.process(name: name, force: force)
        guard QuitConfirmation.ask(
            title: prompt.title,
            message: prompt.message,
            confirmTitle: prompt.confirmTitle,
            icon: icon(forBundle: process.bundlePath) ?? icon(forBundle: process.executablePath),
            destructive: force
        ) else { return }
        let plan = AppQuitPlanner.plan(memberPIDs: [pid], runningApplicationPID: nil, force: force)
        if !deliver(plan, fallbackPIDs: [pid]) {
            QuitConfirmation.failed(name: name)
        }
        refreshNow()
    }

    private func quitProject(name: String, pids: [Int32], force: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.commitProjectQuit(name: name, pids: pids, force: force)
        }
    }

    private func commitProjectQuit(name: String, pids: [Int32], force: Bool) {
        guard !pids.isEmpty else {
            NSSound.beep()
            return
        }
        let prompt = QuitCopy.application(name: name, processCount: pids.count, force: force)
        guard QuitConfirmation.ask(
            title: prompt.title,
            message: prompt.message,
            confirmTitle: prompt.confirmTitle,
            icon: nil,
            destructive: force
        ) else { return }
        let plan = AppQuitPlanner.plan(memberPIDs: pids, runningApplicationPID: nil, force: force)
        if !deliver(plan, fallbackPIDs: pids) {
            QuitConfirmation.failed(name: name)
        }
        refreshNow()
    }

    /// Asks a Mac app to quit, or signals the pids. Returns true when the request was accepted by the system.
    private func deliver(_ plan: AppQuitPlan, fallbackPIDs: [Int32]) -> Bool {
        switch plan {
        case .askApplication(let pid):
            if NSRunningApplication(processIdentifier: pid)?.terminate() == true {
                return true
            }
            return signalSucceeded(QuitService.live().perform(pids: fallbackPIDs, action: .quit, confirmed: true))
        case .signal(let pids, let action):
            return signalSucceeded(QuitService.live().perform(pids: pids, action: action, confirmed: true))
        }
    }

    private func signalSucceeded(_ outcome: QuitOutcome) -> Bool {
        outcome.signals.contains { $0.result == 0 }
    }

    private func selectedApp() -> AppRow? {
        guard let snapshot, let selectedAppID else { return nil }
        return snapshot.apps.first { $0.id == selectedAppID }
    }

    private func selectedProcess() -> ProcessFact? {
        guard let selectedProcessPID, let app = selectedApp() else { return nil }
        return app.members.first { $0.pid == selectedProcessPID }
    }

    private func renderLists() {
        guard let snapshot else { return }
        isRendering = true
        defer { isRendering = false }

        let summaryCPU = "CPU \(formatPercent(snapshot.systemCPUPercent))    Memory \(formatBytes(snapshot.systemMemoryUsedBytes)) of \(formatBytes(snapshot.systemMemoryTotalBytes))"
        let summaryIO = "Disk \(formatRate(snapshot.systemDiskBytesPerSecond))    Network \(formatRate(snapshot.systemNetworkBytesPerSecond))"
        let alertText = alerts.map(\.message).joined(separator: "\n")
        let appRows = snapshot.apps.map { app in
            [
                app.name,
                formatPercent(app.cpuPercent),
                formatBytes(app.memoryBytes),
                formatCount(app.energy),
                formatBytes(app.diskBytes),
                formatBytes(app.networkBytes)
            ]
        }

        for panel in [menuPanel, windowPanel].compactMap({ $0 }) {
            panel.summaryCPU.stringValue = summaryCPU
            panel.summaryIO.stringValue = summaryIO
            panel.alerts.stringValue = alertText
            panel.alerts.isHidden = alertText.isEmpty
            panel.appSource.rows = appRows
            panel.appTable.reloadData()
        }

        let appIndex = selectedAppID.flatMap { id in snapshot.apps.firstIndex { $0.id == id } }
        let members: [ProcessFact]
        if let appIndex {
            members = snapshot.apps[appIndex].members
            for panel in [menuPanel, windowPanel].compactMap({ $0 }) {
                panel.appTable.selectRowIndexes(IndexSet(integer: appIndex), byExtendingSelection: false)
            }
        } else {
            selectedAppID = nil
            selectedProcessPID = nil
            members = []
        }

        let processRows = members.map { process in
            [
                "\(process.name) (\(process.pid))",
                formatPercent(process.cpuPercent),
                formatBytes(process.memoryBytes),
                formatCount(process.energy),
                formatBytes(process.diskBytes),
                formatBytes(process.networkBytes)
            ]
        }
        for panel in [menuPanel, windowPanel].compactMap({ $0 }) {
            panel.processSource.rows = processRows
            panel.processTable.reloadData()
            if let pid = selectedProcessPID, let index = members.firstIndex(where: { $0.pid == pid }) {
                panel.processTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        }
        renderHistory()
    }

    private func renderHistory() {
        guard let panel = windowPanel, panel.historySource != nil, panel.historyTable != nil else { return }
        let ranks = historyStore.topApps(in: selectedHistoryRange, metric: .cpu, limit: 20)
        panel.historySource?.rows = ranks.map { rank in
            [
                rank.appName,
                String(format: "%.1f", rank.cpu),
                formatBytes(rank.memory),
                formatBytes(rank.disk),
                formatBytes(rank.network)
            ]
        }
        panel.historyTable?.reloadData()
    }

    private func bindSelection(of panel: PanelUI) {
        panel.appSource.onSelect = { [weak self] row in
            guard let self, !self.isRendering else { return }
            guard let snapshot = self.snapshot, let row, snapshot.apps.indices.contains(row) else {
                self.selectedAppID = nil
                self.selectedProcessPID = nil
                self.renderLists()
                return
            }
            self.selectedAppID = snapshot.apps[row].id
            self.selectedProcessPID = nil
            self.renderLists()
        }
        panel.processSource.onSelect = { [weak self] row in
            guard let self, !self.isRendering else { return }
            guard let app = self.selectedApp(), let row, app.members.indices.contains(row) else {
                self.selectedProcessPID = nil
                return
            }
            self.selectedProcessPID = app.members[row].pid
        }
    }

    private func makePopover() -> NSPopover {
        let panel = makePanel(kind: .menu)
        menuPanel = panel
        bindSelection(of: panel)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 520, height: 640)
        let controller = NSViewController()
        controller.view = panel.view
        popover.contentViewController = controller
        return popover
    }

    private func makeWindow() -> NSWindow {
        let root = DashboardRoot()
        root.onSelectTab = { [weak self] tab in
            guard tab == .projects, let self, let snapshot = self.snapshot else { return }
            self.renderDashboard(now: Date(), snapshot: snapshot)
        }
        root.onSelectApp = { [weak self] id in
            self?.selectedAppID = id
            self?.selectedProcessPID = self?.snapshot?.apps.first { $0.id == id }?.members.first?.pid
            guard let self, let snapshot = self.snapshot else { return }
            self.renderDashboard(now: Date(), snapshot: snapshot)
        }
        root.onQuitApp = { [weak self] id, force in
            self?.quitApp(id: id, force: force)
        }
        root.onQuitProcess = { [weak self] pid, force in
            self?.selectedProcessPID = pid
            self?.quitProcess(pid: pid, force: force)
        }
        root.onQuitProject = { [weak self] name, pids, force in
            self?.quitProject(name: name, pids: pids, force: force)
        }
        root.onStopProjects = { [weak self] pids in self?.stopProjects(pids) }
        dashboard = root
        let minWidth = PillBar.minimumWindowWidth()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: minWidth, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Open Activity"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = DashTheme.canvas
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = root
        window.minSize = NSSize(width: minWidth, height: 680)
        window.center()
        return window
    }

    private func stopProjects(_ pids: [Int32]) {
        guard !pids.isEmpty else { return }
        guard QuitConfirmation.ask(
            title: "Stop idle dev servers?",
            message: "They will be asked to exit.",
            confirmTitle: "Stop",
            icon: nil,
            destructive: false
        ) else { return }
        _ = QuitService.live().perform(pids: pids, action: .quit, confirmed: true)
        refreshNow()
    }

    private func renderDashboard(now: Date, snapshot explicit: SystemSnapshot? = nil) {
        guard let snapshot = explicit ?? self.snapshot, let dashboard else { return }
        ensureHost(now: now)
        ensureProjects(now: now, snapshot: snapshot)
        noteProjectBusy(now: now)
        dashboard.render(makeDashState(snapshot, now: now))
    }

    /// Battery, memory breakdown, disk, network, and GPU. Shared by the dashboard
    /// and the menu-bar glance. The dashboard views do not change.
    private func ensureHost(now: Date) {
        if hostReadAt != nil, now.timeIntervalSince(hostReadAt!) <= 2 { return }
        let previousIn = lastBytesIn
        let previousOut = lastBytesOut
        let previousAt = hostReadAt
        cachedBattery = HostExtras.battery()
        cachedMemory = HostExtras.memory()
        cachedVolumes = HostExtras.volumes()
        cachedInterface = HostExtras.primaryInterface()
        cachedGPU = HostExtras.gpu()
        if let previousAt, let previousIn, let previousOut, cachedInterface.bytesIn >= previousIn, cachedInterface.bytesOut >= previousOut {
            let elapsed = now.timeIntervalSince(previousAt)
            if elapsed > 0 {
                downloadPerSecond = Double(cachedInterface.bytesIn - previousIn) / elapsed
                uploadPerSecond = Double(cachedInterface.bytesOut - previousOut) / elapsed
            }
            if elapsed > 0, elapsed < 30 {
                sessionDownAccum += cachedInterface.bytesIn - previousIn
                sessionUpAccum += cachedInterface.bytesOut - previousOut
            }
        }
        lastBytesIn = cachedInterface.bytesIn
        lastBytesOut = cachedInterface.bytesOut
        hostReadAt = now
    }

    private func ensureProjects(now: Date, snapshot: SystemSnapshot) {
        let windowWants = mainWindow?.isVisible == true && dashboard?.selectedTab == .projects
        let glanceWants = glanceController.isVisible && glanceController.selectedTab == .projects
        guard windowWants || glanceWants else { return }
        if lastProjectScan != nil, now.timeIntervalSince(lastProjectScan!) <= 15 { return }
        let rows = snapshot.apps.flatMap { app in
            app.members.map { member in
                (pid: member.pid, name: member.name, memoryBytes: member.memoryBytes, cpuPercent: member.cpuPercent, startedAt: member.startedAt)
            }
        }
        liveProjects = DevProjects.scan(processes: rows)
        projectsScanned = true
        lastProjectScan = now
    }

    private func noteProjectBusy(now: Date) {
        for project in liveProjects where project.cpuPercent >= 2 {
            projectBusy[project.directory] = now
        }
    }

    private func recordSeries(_ snapshot: SystemSnapshot, now: Date) {
        if let lastSeriesAt {
            let elapsed = now.timeIntervalSince(lastSeriesAt)
            if elapsed > 0, elapsed < 30 {
                sessionNetBytes += snapshot.systemNetworkBytesPerSecond * elapsed
                sessionDiskWrite += sampler.diskWriteBytesPerSecond * elapsed
            }
        }
        lastSeriesAt = now
        append(snapshot.systemCPUPercent, to: &cpuSeries)
        let memoryFraction = snapshot.systemMemoryTotalBytes > 0 ? Double(snapshot.systemMemoryUsedBytes) / Double(snapshot.systemMemoryTotalBytes) : 0
        append(memoryFraction, to: &memorySeries)
        append(snapshot.systemDiskBytesPerSecond, to: &diskSeries)
        append(snapshot.systemNetworkBytesPerSecond, to: &netSeries)
        cpuSum += snapshot.systemCPUPercent
        cpuCount += 1
        if let utilization = cachedGPU.utilizationPercent {
            append(utilization, to: &gpuSeries)
            gpuSum += utilization
            gpuCount += 1
            gpuPeak = max(gpuPeak ?? utilization, utilization)
        }
        if let percent = cachedBattery.percent {
            append(percent, to: &batterySeries)
        }
    }

    private func append(_ value: Double, to series: inout [Double]) {
        series.append(value)
        if series.count > 48 {
            series.removeFirst(series.count - 48)
        }
    }

    private func makeDashState(_ snapshot: SystemSnapshot, now: Date) -> DashState {
        var state = DashState()
        state.cpuNow = snapshot.systemCPUPercent
        state.cpuUserShare = sampler.userCPUPercent
        state.cpuSystemShare = sampler.systemCPUShare
        state.cpuAverage = cpuCount > 0 ? cpuSum / Double(cpuCount) : snapshot.systemCPUPercent
        var load = [Double](repeating: 0, count: 1)
        if getloadavg(&load, 1) == 1 { state.cpuLoad = load[0] }
        state.cpuCores = sysctlInt("hw.ncpu")
        state.performanceCores = sysctlInt("hw.perflevel0.physicalcpu")
        state.efficiencyCores = sysctlInt("hw.perflevel1.physicalcpu")
        if state.performanceCores == 0 { state.performanceCores = state.cpuCores }
        state.cpuSeries = SeriesWindow.window(cpuSeries)

        let footprint = snapshot.apps.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let parts = HostMemory.breakdown(
            internalBytes: cachedMemory.appBytes,
            wiredBytes: cachedMemory.wiredBytes,
            compressedBytes: cachedMemory.compressedBytes,
            externalBytes: cachedMemory.cachedBytes,
            freeBytes: cachedMemory.freeBytes,
            swapBytes: cachedMemory.swapBytes,
            totalBytes: cachedMemory.totalBytes > 0 ? cachedMemory.totalBytes : snapshot.systemMemoryTotalBytes,
            processFootprintSum: footprint
        )
        state.memoryUsed = parts.inUseBytes
        state.memoryTotal = parts.totalBytes > 0 ? parts.totalBytes : snapshot.systemMemoryTotalBytes
        state.memoryApp = parts.appBytes
        state.memoryWired = parts.wiredBytes
        state.memoryCompressed = parts.compressedBytes
        state.memoryCached = parts.cachedBytes
        state.memoryFree = parts.freeBytes
        state.memorySwap = parts.swapBytes
        state.allAppsMemoryBytes = footprint
        state.memorySeries = SeriesWindow.window(memorySeries)

        if let volume = cachedVolumes.max(by: { $0.totalBytes < $1.totalBytes }) {
            state.diskFree = volume.freeBytes
            state.diskUsed = volume.totalBytes > volume.freeBytes ? volume.totalBytes - volume.freeBytes : 0
        }
        state.diskReadPerSecond = sampler.diskReadBytesPerSecond
        state.diskWritePerSecond = sampler.diskWriteBytesPerSecond
        state.diskWrittenToday = UInt64(sessionDiskWrite)
        state.diskSeries = SeriesWindow.window(diskSeries)
        state.volumeNames = cachedVolumes.map(\.name)

        state.netDownPerSecond = downloadPerSecond > 0 ? downloadPerSecond : snapshot.systemNetworkBytesPerSecond
        state.netUpPerSecond = uploadPerSecond
        state.sessionBytesDown = sessionDownAccum
        state.sessionBytesUp = sessionUpAccum
        state.netToday = UInt64(sessionNetBytes)
        state.netLast7Days = state.netToday
        state.netLast30Days = state.netToday
        state.netInterfaceName = cachedInterface.bsdName
        state.netInterfaceKind = cachedInterface.kind
        state.netSeries = SeriesWindow.window(netSeries)

        state.gpuName = cachedGPU.name
        state.gpuPercent = cachedGPU.utilizationPercent
        state.gpuMemoryBytes = cachedGPU.memoryBytes
        state.gpuAverage = gpuCount > 0 ? gpuSum / Double(gpuCount) : nil
        state.gpuPeak = gpuPeak
        state.gpuSeries = SeriesWindow.window(gpuSeries)

        state.hasBattery = cachedBattery.hasBattery
        state.onBattery = cachedBattery.hasBattery && !cachedBattery.onACPower
        state.batteryPercent = cachedBattery.percent
        state.batteryMinutesRemaining = cachedBattery.minutesRemaining
        state.batteryCycles = cachedBattery.cycleCount
        state.batteryWatts = cachedBattery.watts
        state.batteryHealthPercent = cachedBattery.healthPercent
        state.batteryTemperatureC = cachedBattery.temperatureC
        state.batterySeries = SeriesWindow.window(batterySeries)

        let byCPU = snapshot.apps.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(24)
        let byMemory = snapshot.apps.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(24)
        var seen = Set<String>()
        var apps: [DashApp] = []
        for app in byCPU + byMemory where seen.insert(app.id).inserted {
            apps.append(DashApp(
                id: app.id,
                name: app.name,
                processCount: app.members.count,
                bundlePath: app.bundlePath,
                cpuPercent: app.cpuPercent,
                memoryBytes: app.memoryBytes,
                diskBytesPerSecond: sampler.lastElapsed > 0 ? Double(app.diskBytes) / sampler.lastElapsed : 0,
                networkBytesPerSecond: 0,
                energy: app.energy,
                powerWatts: powerWatts(of: app),
                gpuPercent: nil,
                icon: icon(forBundle: app.bundlePath) ?? icon(forBundle: app.members.first?.executablePath)
            ))
        }
        state.apps = apps
        state.selectedAppID = selectedAppID
        if let selected = snapshot.apps.first(where: { $0.id == selectedAppID }) {
            state.members = selected.members.map {
                DashMember(pid: $0.pid, name: $0.name, cpuPercent: $0.cpuPercent, memoryBytes: $0.memoryBytes)
            }
        }
        state.projects = liveProjects.map { project in
            let idle: Int?
            if project.cpuPercent < 2, let busy = projectBusy[project.directory] {
                let minutes = Int(now.timeIntervalSince(busy) / 60)
                idle = minutes > 0 ? minutes : nil
            } else {
                idle = nil
            }
            let uptime = project.oldestStart.map { now.timeIntervalSince($0) }
            return DashProject(
                name: project.name,
                runtime: project.runtime,
                directory: project.directory,
                processCount: project.pids.count,
                ports: project.ports,
                memoryBytes: project.memoryBytes,
                cpuPercent: project.cpuPercent,
                pids: project.pids,
                uptime: uptime,
                idleMinutes: idle
            )
        }
        state.projectsScanned = projectsScanned
        state.alerts = alerts.map(\.message)
        return state
    }

    private func powerWatts(of app: AppRow) -> Double? {
        var total = 0.0
        var measured = false
        for member in app.members {
            guard let watts = sampler.watts(for: member.pid) else { continue }
            measured = true
            total += watts
        }
        return measured ? total : nil
    }

    private func icon(forBundle path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = iconCache[path] { return cached }
        guard iconCache.count < 128 else { return nil }
        let source = NSWorkspace.shared.icon(forFile: path)
        let image = rasterIcon(source, side: 32)
        iconCache[path] = image
        return image
    }

    private func rasterIcon(_ source: NSImage, side: CGFloat) -> NSImage {
        let pixels = Int(side)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            source.size = NSSize(width: side, height: side)
            return source
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }

    private func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname(name, &value, &size, nil, 0) != 0 { return 0 }
        return Int(value)
    }

    private func makePanel(kind: PanelKind) -> PanelUI {
        let appSource = StringTableSource()
        let processSource = StringTableSource()
        let (appScroll, appTable) = makeTable(
            [("App", 180), ("CPU", 70), ("Memory", 90), ("Energy", 70), ("Disk", 80), ("Network", 80)],
            source: appSource
        )
        let (processScroll, processTable) = makeTable(
            [("Process", 180), ("CPU", 70), ("Memory", 90), ("Energy", 70), ("Disk", 80), ("Network", 80)],
            source: processSource
        )
        appScroll.heightAnchor.constraint(equalToConstant: kind == .menu ? 220 : 240).isActive = true
        processScroll.heightAnchor.constraint(equalToConstant: kind == .menu ? 120 : 140).isActive = true

        let summaryCPU = NSTextField(labelWithString: "CPU —    Memory —")
        summaryCPU.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let summaryIO = NSTextField(labelWithString: "Disk —    Network —")
        summaryIO.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let alerts = NSTextField(wrappingLabelWithString: "")
        alerts.font = .systemFont(ofSize: 12, weight: .medium)
        alerts.textColor = .systemRed
        alerts.maximumNumberOfLines = 4
        alerts.isHidden = true

        let appTitle = sectionTitle("Apps")
        let processTitle = sectionTitle("Processes")
        let quitRow = buttonRow([
            ("Quit", #selector(quitSelectedApp(_:))),
            ("Force Quit", #selector(forceQuitSelectedApp(_:))),
            ("Quit Process", #selector(quitSelectedProcess(_:))),
            ("Force Quit Process", #selector(forceQuitSelectedProcess(_:)))
        ])

        var historySource: StringTableSource?
        var historyTable: NSTableView?
        var historyViews: [NSView] = []
        if kind == .window {
            let source = StringTableSource()
            let (scroll, table) = makeTable(
                [("App", 180), ("CPU", 80), ("Memory", 90), ("Disk", 90), ("Network", 90)],
                source: source
            )
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
            scroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
            historySource = source
            historyTable = table
            let header = NSStackView()
            header.orientation = .horizontal
            header.spacing = 12
            header.alignment = .centerY
            let title = sectionTitle("Most CPU")
            let segments = NSSegmentedControl(
                labels: HistoryRange.allCases.map(\.title),
                trackingMode: .selectOne,
                target: self,
                action: #selector(historyRangeChanged(_:))
            )
            segments.selectedSegment = HistoryRange.allCases.firstIndex(of: selectedHistoryRange) ?? 0
            header.addArrangedSubview(title)
            header.addArrangedSubview(segments)
            historyViews = [header, scroll]
        }

        var openRow: NSView?
        if kind == .menu {
            openRow = buttonRow([
                ("Open Activity", #selector(openMainWindow(_:))),
                ("Quit Open Activity", #selector(NSApplication.terminate(_:)))
            ])
        } else {
            openRow = buttonRow([
                ("Quit Open Activity", #selector(NSApplication.terminate(_:)))
            ])
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .fill
        stack.spacing = 8
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false

        var arranged: [NSView] = [summaryCPU, summaryIO, alerts, appTitle, appScroll, processTitle, processScroll, quitRow]
        if let openRow, kind == .menu {
            arranged.append(openRow)
        }
        arranged.append(contentsOf: historyViews)
        if let openRow, kind == .window {
            arranged.append(openRow)
        }
        for view in arranged {
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if view !== appScroll && view !== processScroll && !historyViews.contains(where: { $0 === view }) {
                view.setContentHuggingPriority(.required, for: .vertical)
            }
        }
        if let historyScroll = historyViews.last {
            historyScroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        }

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16)
        ])
        if kind == .menu {
            NSLayoutConstraint.activate([
                root.widthAnchor.constraint(equalToConstant: 520),
                root.heightAnchor.constraint(equalToConstant: 640),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -12)
            ])
        } else {
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12).isActive = true
        }

        return PanelUI(
            view: root,
            summaryCPU: summaryCPU,
            summaryIO: summaryIO,
            alerts: alerts,
            appSource: appSource,
            appTable: appTable,
            processSource: processSource,
            processTable: processTable,
            historySource: historySource,
            historyTable: historyTable
        )
    }

    private func buttonRow(_ items: [(String, Selector)]) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        for (title, action) in items {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            row.addArrangedSubview(button)
        }
        return row
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func makeTable(_ columns: [(String, CGFloat)], source: StringTableSource) -> (NSScrollView, NSTableView) {
        let table = NSTableView()
        table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.style = .inset
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = source
        table.delegate = source
        for (index, column) in columns.enumerated() {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col-\(index)"))
            tableColumn.title = column.0
            tableColumn.width = column.1
            tableColumn.minWidth = 56
            table.addTableColumn(tableColumn)
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return (scroll, table)
    }

    private func supportDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["APPFOLD_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Appfold", isDirectory: true)
    }
}

private enum PanelKind {
    case menu
    case window
}

private final class PanelUI {
    let view: NSView
    let summaryCPU: NSTextField
    let summaryIO: NSTextField
    let alerts: NSTextField
    let appSource: StringTableSource
    let appTable: NSTableView
    let processSource: StringTableSource
    let processTable: NSTableView
    let historySource: StringTableSource?
    let historyTable: NSTableView?

    init(
        view: NSView,
        summaryCPU: NSTextField,
        summaryIO: NSTextField,
        alerts: NSTextField,
        appSource: StringTableSource,
        appTable: NSTableView,
        processSource: StringTableSource,
        processTable: NSTableView,
        historySource: StringTableSource?,
        historyTable: NSTableView?
    ) {
        self.view = view
        self.summaryCPU = summaryCPU
        self.summaryIO = summaryIO
        self.alerts = alerts
        self.appSource = appSource
        self.appTable = appTable
        self.processSource = processSource
        self.processTable = processTable
        self.historySource = historySource
        self.historyTable = historyTable
    }
}

private final class StringTableSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [[String]] = []
    var onSelect: ((Int?) -> Void)?

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let text: String
        if let column = tableColumn, let index = tableView.tableColumns.firstIndex(of: column), rows.indices.contains(row), index < rows[row].count {
            text = rows[row][index]
        } else {
            text = ""
        }
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            let created = NSTableCellView()
            created.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingTail
            field.font = .systemFont(ofSize: 12)
            created.addSubview(field)
            created.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: created.centerYAnchor)
            ])
            cell = created
        }
        cell.textField?.stringValue = text
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        onSelect?(table.selectedRow >= 0 ? table.selectedRow : nil)
    }
}

private enum RunningAppLookup {
    /// Pid of the Mac app that owns this bundle, when that pid is one of the grouped processes.
    static func pid(bundlePath: String?, memberPIDs: [Int32]) -> Int32? {
        let members = Set(memberPIDs)
        let running = NSWorkspace.shared.runningApplications
        if let bundlePath {
            let wanted = URL(fileURLWithPath: bundlePath).resolvingSymlinksInPath().path
            if let match = running.first(where: { app in
                guard let path = app.bundleURL?.resolvingSymlinksInPath().path else { return false }
                return path == wanted && members.contains(app.processIdentifier)
            }) {
                return match.processIdentifier
            }
        }
        for pid in memberPIDs {
            guard let app = NSRunningApplication(processIdentifier: pid), app.bundleURL != nil else { continue }
            if app.activationPolicy == .regular || app.activationPolicy == .accessory {
                return pid
            }
        }
        return nil
    }
}

private enum SnapshotFile {
    static func write(_ snapshot: SystemSnapshot) {
        guard let path = ProcessInfo.processInfo.environment["APPFOLD_SNAPSHOT_PATH"], !path.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

private func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024, unit < units.count - 1 {
        value /= 1024
        unit += 1
    }
    if unit == 0 { return "\(bytes) B" }
    return String(format: "%.1f %@", value, units[unit])
}

private func formatRate(_ bytesPerSecond: Double) -> String {
    formatBytes(UInt64(max(0, bytesPerSecond))) + "/s"
}

private func formatPercent(_ value: Double) -> String {
    String(format: "%.1f%%", value)
}

private func formatCount(_ value: UInt64) -> String {
    let units = ["", "K", "M", "B", "T"]
    var number = Double(value)
    var unit = 0
    while number >= 1000, unit < units.count - 1 {
        number /= 1000
        unit += 1
    }
    if unit == 0 { return "\(value)" }
    return String(format: "%.1f%@", number, units[unit])
}
