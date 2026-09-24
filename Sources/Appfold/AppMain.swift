import AppKit
import AppfoldCore
import Darwin

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
    private var selectedAppID: String?
    private var selectedProcessPID: Int32?
    private var selectedHistoryRange: HistoryRange = .last12Hours
    private var isRendering = false

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var menuPanel: PanelUI?
    private var windowPanel: PanelUI?
    private var mainWindow: NSWindow?
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        installStatusItem()
        installTerminateOnSignal()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Keep the usage sample timer running"
        )
        let now = Date()
        refresh(now: now)
        schedule.markSampled(at: now)
        scheduleNext()
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
        schedule.windowVisible = false
        scheduleNext()
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
        historyWriter.write(snapshot: snapshot, store: historyStore)
        updateStatusItem()
        if mainWindow?.isVisible == true || popover?.isShown == true {
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
        let appMenu = NSMenu(title: "Appfold")
        let open = NSMenuItem(title: "Open Appfold", action: #selector(openMainWindow(_:)), keyEquivalent: "o")
        open.target = self
        appMenu.addItem(open)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Appfold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Appfold") {
                image.isTemplate = true
                image.size = NSSize(width: 16, height: 16)
                button.image = image
            }
            button.imagePosition = .imageLeading
            button.title = " —"
            button.toolTip = "Appfold"
            button.target = self
            button.action = #selector(togglePopover(_:))
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
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover == nil {
            popover = makePopover()
        }
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        renderLists()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func openMainWindow(_ sender: Any?) {
        if mainWindow == nil {
            mainWindow = makeWindow()
        }
        schedule.windowVisible = true
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        renderLists()
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
        guard let app = selectedApp() else {
            NSSound.beep()
            return
        }
        let title = force ? "Force Quit \(app.name)?" : "Quit \(app.name)?"
        let message = force
            ? "\(app.name) will end immediately, including its helper processes."
            : "\(app.name) will be asked to exit, including its helper processes."
        guard QuitConfirmation.ask(title: title, message: message, confirmTitle: force ? "Force Quit" : "Quit") else {
            return
        }
        _ = QuitService.live().perform(app: app, action: force ? .forceQuit : .quit, confirmed: true)
        refreshNow()
    }

    private func quitProcess(force: Bool) {
        guard let process = selectedProcess() else {
            NSSound.beep()
            return
        }
        let title = force ? "Force Quit \(process.name)?" : "Quit \(process.name)?"
        let message = force
            ? "Process \(process.pid) will end immediately."
            : "Process \(process.pid) will be asked to exit."
        guard QuitConfirmation.ask(title: title, message: message, confirmTitle: force ? "Force Quit" : "Quit") else {
            return
        }
        _ = QuitService.live().perform(pids: [process.pid], action: force ? .forceQuit : .quit, confirmed: true)
        refreshNow()
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
        let panel = makePanel(kind: .window)
        windowPanel = panel
        bindSelection(of: panel)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Appfold"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = panel.view
        window.minSize = NSSize(width: 680, height: 560)
        window.center()
        return window
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
                ("Open Appfold", #selector(openMainWindow(_:))),
                ("Quit Appfold", #selector(NSApplication.terminate(_:)))
            ])
        } else {
            openRow = buttonRow([
                ("Quit Appfold", #selector(NSApplication.terminate(_:)))
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

private enum QuitConfirmation {
    static func ask(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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
