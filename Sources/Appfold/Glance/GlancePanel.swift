import AppKit

/// Menu-bar glance shell: icon rail, scrolling page, pinned footer.
final class GlancePanel: NSView {
    static let preferredSize = NSSize(width: 420, height: 740)

    var onOpen: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private let overviewPage = GlanceOverviewPage(frame: .zero)
    private let metricPage = GlanceMetricPage(tab: .cpu)
    private let projectsPage = GlanceProjectsPage(frame: .zero)
    private let rail = GlanceIconRail(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let openButton = GlanceButton(title: "Open Appfold", symbol: "macwindow")
    private let settingsButton = GlanceButton(title: "", symbol: "gearshape", circular: true)
    private let quitButton = GlanceButton(title: "Quit", symbol: "power")
    private var documentWidth: NSLayoutConstraint?

    var selectedTab: DashTab = .overview {
        didSet {
            guard selectedTab != oldValue else { return }
            showSelectedTab()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        applyChrome()

        overviewPage.onOpenTab = { [weak self] tab in
            self?.selectedTab = tab
        }
        projectsPage.onOpen = { [weak self] in
            self?.onOpen?()
        }
        rail.onSelect = { [weak self] tab in
            self?.selectedTab = tab
        }
        openButton.onClick = { [weak self] in
            self?.onOpen?()
        }
        settingsButton.onClick = { [weak self] in
            self?.onSettings?()
        }
        quitButton.onClick = { [weak self] in
            self?.onQuit?()
        }

        openButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        openButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        settingsButton.setContentHuggingPriority(.required, for: .horizontal)
        quitButton.setContentHuggingPriority(.required, for: .horizontal)
        quitButton.widthAnchor.constraint(equalToConstant: 108).isActive = true

        let clip = GlanceClipView(frame: .zero)
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.contentView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let footer = NSStackView(views: [openButton, settingsButton, quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false

        rail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rail)
        addSubview(scrollView)
        addSubview(footer)

        NSLayoutConstraint.activate([
            rail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rail.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            rail.heightAnchor.constraint(equalToConstant: 52),

            scrollView.topAnchor.constraint(equalTo: rail.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            footer.heightAnchor.constraint(equalToConstant: 44),
        ])

        showSelectedTab()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        applyChrome()
    }

    func render(_ state: DashState) {
        overviewPage.render(state)
        metricPage.render(state)
        projectsPage.render(state)
        // Highlight only. Assigning selectedTab would install the page again.
        if rail.selectedTab != selectedTab {
            rail.selectedTab = selectedTab
        }
    }

    private func applyChrome() {
        layer?.backgroundColor = GlanceTheme.canvas.cgColor
        layer?.cornerRadius = GlanceTheme.panelRadius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = GlanceTheme.hairline.cgColor
    }

    private func showSelectedTab() {
        if rail.selectedTab != selectedTab {
            rail.selectedTab = selectedTab
        }
        switch selectedTab {
        case .overview:
            install(overviewPage)
        case .projects:
            install(projectsPage)
        default:
            metricPage.tab = selectedTab
            install(metricPage)
        }
    }

    private func install(_ page: NSView) {
        let document = GlanceDocumentView(frame: .zero)
        page.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            page.topAnchor.constraint(equalTo: document.topAnchor),
            page.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        documentWidth?.isActive = false
        scrollView.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        // Required so the page tracks the clip width. Height stays with the page, leaving canvas under a short one.
        let width = document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        width.priority = .required
        width.isActive = true
        documentWidth = width
        scrollView.contentView.scroll(to: .zero)
    }
}

/// Flipped so a short page stays at the top of the panel instead of the bottom.
private final class GlanceClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class GlanceDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class GlanceIconRail: NSView {
    var onSelect: ((DashTab) -> Void)?

    private let slots: [GlanceRailSlot]

    var selectedTab: DashTab = .overview {
        didSet {
            guard selectedTab != oldValue else { return }
            applySelection()
        }
    }

    override init(frame frameRect: NSRect) {
        let slots = DashTab.allCases.map { GlanceRailSlot(tab: $0) }
        self.slots = slots
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = GlanceTheme.card.cgColor
        layer?.cornerRadius = GlanceTheme.cardRadius
        layer?.masksToBounds = true

        let stack = NSStackView(views: slots)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        for slot in slots {
            slot.onSelect = { [weak self] tab in
                self?.onSelect?(tab)
            }
        }
        applySelection()
    }

    required init?(coder: NSCoder) { nil }

    private func applySelection() {
        for slot in slots {
            slot.isSelected = slot.tab == selectedTab
        }
    }
}

private final class GlanceRailSlot: NSView {
    let tab: DashTab
    var onSelect: ((DashTab) -> Void)?

    private let chip = NSView(frame: .zero)
    private let icon = NSImageView(frame: .zero)

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            applySelection()
        }
    }

    init(tab: DashTab) {
        self.tab = tab
        super.init(frame: .zero)
        toolTip = tab.title
        translatesAutoresizingMaskIntoConstraints = false
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 11
        chip.layer?.masksToBounds = true
        chip.layer?.backgroundColor = GlanceTheme.accent(tab).cgColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentHuggingPriority(.required, for: .vertical)
        addSubview(chip)
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addGestureRecognizer(GlanceClick { [weak self] in
            guard let self else { return }
            self.onSelect?(self.tab)
        })
        applySelection()
    }

    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func layout() {
        super.layout()
        let side: CGFloat = 34
        let next = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        if chip.frame != next {
            chip.frame = next
        }
    }

    private func applySelection() {
        chip.isHidden = !isSelected
        icon.image = GlanceTheme.symbol(
            GlanceTheme.symbolName(tab),
            pointSize: 16,
            tint: isSelected ? GlanceTheme.primary : GlanceTheme.tertiary
        )
        needsLayout = true
    }
}
