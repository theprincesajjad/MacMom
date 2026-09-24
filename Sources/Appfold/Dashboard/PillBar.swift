import AppKit

final class PillBar: NSView {
    var selected: DashTab = .overview {
        didSet {
            guard oldValue != selected else { return }
            applySelection()
        }
    }

    var onChange: ((DashTab) -> Void)?

    private let capsule = NSView()
    private let stack = NSStackView()
    private var items: [PillItem] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        if let aqua = NSAppearance(named: .aqua) {
            appearance = aqua
        }

        capsule.wantsLayer = true
        capsule.layer?.backgroundColor = DashTheme.card.cgColor
        capsule.layer?.cornerRadius = Metric.barHeight / 2
        capsule.layer?.masksToBounds = false
        DashTheme.applyCardShadow(to: capsule)
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.setContentHuggingPriority(.required, for: .horizontal)
        capsule.setContentCompressionResistancePriority(.required, for: .horizontal)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = Metric.spacing
        stack.edgeInsets = NSEdgeInsets(top: Metric.padY, left: Metric.padX, bottom: Metric.padY, right: Metric.padX)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(capsule)
        capsule.addSubview(stack)

        for tab in DashTab.allCases {
            let item = PillItem(tab: tab)
            item.onClick = { [weak self] in
                guard let self else { return }
                self.selected = tab
                self.onChange?(tab)
            }
            items.append(item)
            stack.addArrangedSubview(item)
        }

        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor),
            capsule.heightAnchor.constraint(equalToConstant: Metric.barHeight),

            stack.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
            stack.topAnchor.constraint(equalTo: capsule.topAnchor),
            stack.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
        ])

        applySelection()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let content = items.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width }
        let gaps = Metric.spacing * CGFloat(max(items.count - 1, 0))
        return NSSize(width: content + gaps + Metric.padX * 2, height: Metric.barHeight)
    }

    override func layout() {
        super.layout()
        let radius = capsule.bounds.height / 2
        capsule.layer?.cornerRadius = radius
        guard capsule.bounds.width > 1, capsule.bounds.height > 1 else { return }
        capsule.layer?.shadowPath = CGPath(
            roundedRect: capsule.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    private func applySelection() {
        for item in items {
            item.isOn = item.tab == selected
        }
    }
}

private enum Metric {
    static let barHeight: CGFloat = 44
    static let itemHeight: CGFloat = 36
    static let padX: CGFloat = 5
    static let padY: CGFloat = 4
    static let itemInsetX: CGFloat = 8
    static let iconSide: CGFloat = 14
    static let iconGap: CGFloat = 5
    static let spacing: CGFloat = 2
    static let textSlack: CGFloat = 2
}

private final class PillItem: NSView {
    let tab: DashTab
    var onClick: (() -> Void)?

    var isOn = false {
        didSet { render() }
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var armed = false

    override var intrinsicContentSize: NSSize {
        let font = titleLabel.font ?? NSFont.systemFont(ofSize: 12, weight: .medium)
        let text = (tab.title as NSString).size(withAttributes: [.font: font]).width
        let width = Metric.itemInsetX + Metric.iconSide + Metric.iconGap + ceil(text) + Metric.textSlack + Metric.itemInsetX
        return NSSize(width: width, height: Metric.itemHeight)
    }

    init(tab: DashTab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        titleLabel.stringValue = tab.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.backgroundColor = .clear
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter

        addSubview(iconView)
        addSubview(titleLabel)
        render()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        let iconY = (bounds.height - Metric.iconSide) / 2
        iconView.frame = NSRect(x: Metric.itemInsetX, y: iconY, width: Metric.iconSide, height: Metric.iconSide)
        let font = titleLabel.font ?? NSFont.systemFont(ofSize: 13, weight: .medium)
        let textSize = (tab.title as NSString).size(withAttributes: [.font: font])
        let labelX = iconView.frame.maxX + Metric.iconGap
        let labelWidth = max(0, bounds.width - labelX - Metric.itemInsetX)
        let labelHeight = min(bounds.height, ceil(textSize.height) + 4)
        titleLabel.frame = NSRect(
            x: labelX,
            y: (bounds.height - labelHeight) / 2,
            width: labelWidth,
            height: labelHeight
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        armed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if armed, inside {
            onClick?()
        }
        armed = false
    }

    private func render() {
        let color = isOn ? DashTheme.accent(tab) : DashTheme.secondaryText
        titleLabel.textColor = color
        iconView.image = DashTheme.symbol(tab.symbolName, pointSize: 12, tint: color)
        layer?.backgroundColor = isOn ? DashTheme.accentWash(tab).cgColor : NSColor.clear.cgColor
        needsLayout = true
    }
}
