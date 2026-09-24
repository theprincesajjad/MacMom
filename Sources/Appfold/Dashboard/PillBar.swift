import AppKit
import AppfoldCore

final class PillBar: NSView {
    static let titleFont = NSFont.systemFont(ofSize: PillLayout.titlePointSize, weight: .medium)

    static func textWidths() -> [CGFloat] {
        DashTab.allCases.map { tab in
            (tab.title as NSString).size(withAttributes: [.font: titleFont]).width
        }
    }

    static func barWidth() -> CGFloat {
        PillLayout.barWidth(textWidths: textWidths())
    }

    static func minimumWindowWidth() -> CGFloat {
        PillLayout.windowMinimumWidth(textWidths: textWidths())
    }

    var selected: DashTab = .overview {
        didSet {
            guard oldValue != selected else { return }
            applySelection()
        }
    }

    var onChange: ((DashTab) -> Void)?

    private let capsule = NSView()
    private var items: [PillItem] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        if let aqua = NSAppearance(named: .aqua) {
            appearance = aqua
        }
        capsule.wantsLayer = true
        capsule.layer?.backgroundColor = DashTheme.card.cgColor
        capsule.layer?.masksToBounds = true
        addSubview(capsule)
        for tab in DashTab.allCases {
            let item = PillItem(tab: tab)
            item.onClick = { [weak self] in
                guard let self else { return }
                self.selected = tab
                self.onChange?(tab)
            }
            items.append(item)
            capsule.addSubview(item)
        }
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        applySelection()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.barWidth(), height: 40)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let measured = Self.textWidths()
        let allotted = PillLayout.allottedTextWidths(textWidths: measured, contentWidth: bounds.width)
        let itemWidths = allotted.map { PillLayout.itemWidth(textWidth: $0) }
        let bar = PillLayout.barWidth(textWidths: allotted)
        let originX = max(0, (bounds.width - bar) / 2)
        capsule.frame = NSRect(x: originX, y: 0, width: min(bar, bounds.width), height: bounds.height)
        capsule.layer?.cornerRadius = capsule.bounds.height / 2
        var x = PillLayout.padX
        for (index, item) in items.enumerated() {
            let width = itemWidths[index]
            item.frame = NSRect(x: x, y: 3, width: width, height: max(28, bounds.height - 6))
            item.placeTitle(textWidth: allotted[index])
            x += width + PillLayout.spacing
        }
    }

    private func applySelection() {
        for item in items {
            item.isOn = item.tab == selected
        }
    }
}

private final class PillItem: NSView {
    let tab: DashTab
    var onClick: (() -> Void)?
    var isOn = false { didSet { render() } }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var armed = false

    init(tab: DashTab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        titleLabel.stringValue = tab.title
        titleLabel.font = PillBar.titleFont
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.lineBreakMode = .byClipping
        titleLabel.maximumNumberOfLines = 1
        if let cell = titleLabel.cell as? NSTextFieldCell {
            cell.lineBreakMode = .byClipping
            cell.usesSingleLineMode = true
            cell.wraps = false
        }
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        addSubview(titleLabel)
        render()
    }

    required init?(coder: NSCoder) { nil }

    func placeTitle(textWidth: CGFloat) {
        let iconX = PillLayout.itemInsetX
        let iconY = (bounds.height - PillLayout.iconSide) / 2
        iconView.frame = NSRect(x: iconX, y: iconY, width: PillLayout.iconSide, height: PillLayout.iconSide)
        let labelX = iconView.frame.maxX + PillLayout.iconGap
        let labelHeight = ceil(PillBar.titleFont.ascender - PillBar.titleFont.descender) + 2
        titleLabel.frame = NSRect(
            x: labelX,
            y: (bounds.height - labelHeight) / 2,
            width: max(textWidth, bounds.width - labelX - PillLayout.itemInsetX),
            height: labelHeight
        )
        layer?.cornerRadius = bounds.height / 2
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
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

    private func render() {
        let color = isOn ? DashTheme.accent(tab) : DashTheme.secondaryText
        titleLabel.textColor = color
        iconView.image = DashTheme.symbol(tab.symbolName, pointSize: 12, tint: color)
        iconView.contentTintColor = color
        layer?.backgroundColor = isOn ? DashTheme.accentWash(tab).cgColor : NSColor.clear.cgColor
    }
}
