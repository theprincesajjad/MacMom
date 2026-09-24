import AppKit

private let listFill = NSColor(srgbRed: 0.952, green: 0.954, blue: 0.962, alpha: 1)
private let bannerFill = NSColor(srgbRed: 0.992, green: 0.918, blue: 0.890, alpha: 1)
private let stopFill = NSColor(srgbRed: 0.918, green: 0.345, blue: 0.275, alpha: 1)
private let stopPressed = NSColor(srgbRed: 0.82, green: 0.28, blue: 0.22, alpha: 1)
private let titleGray = NSColor(srgbRed: 0.33, green: 0.35, blue: 0.39, alpha: 1)

private func installCardChrome(_ view: NSView, radius: CGFloat = DashTheme.cardRadius, fill: NSColor = DashTheme.card) {
    view.wantsLayer = true
    if let aqua = NSAppearance(named: .aqua) {
        view.appearance = aqua
    }
    view.layer?.masksToBounds = false
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = fill.cgColor
    DashTheme.applyCardShadow(to: view)
}

private func updateCardShadowPath(_ view: NSView, radius: CGFloat) {
    guard view.bounds.width > 1, view.bounds.height > 1 else { return }
    view.layer?.cornerRadius = radius
    view.layer?.masksToBounds = false
    view.layer?.shadowPath = CGPath(
        roundedRect: view.bounds,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
}

private func dashLabel(
    _ text: String,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    mono: Bool = false,
    alignment: NSTextAlignment = .left
) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.font = mono
        ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.alignment = alignment
    field.lineBreakMode = .byTruncatingTail
    field.maximumNumberOfLines = 1
    field.drawsBackground = false
    field.isBezeled = false
    field.isEditable = false
    field.isSelectable = false
    field.backgroundColor = .clear
    if let cell = field.cell as? NSTextFieldCell {
        cell.wraps = false
        cell.isScrollable = false
        cell.usesSingleLineMode = true
        cell.lineBreakMode = .byTruncatingTail
        cell.truncatesLastVisibleLine = true
    }
    return field
}

private func metricText(_ text: String, numberSize: CGFloat) -> NSAttributedString {
    let color = DashTheme.primaryText
    let numberFont = NSFont.monospacedDigitSystemFont(ofSize: numberSize, weight: .bold)
    let unitFont = NSFont.systemFont(ofSize: max(16, (numberSize * 0.48).rounded()), weight: .semibold)
    let style = NSMutableParagraphStyle()
    style.alignment = .left
    style.lineBreakMode = .byTruncatingTail
    let result = NSMutableAttributedString(string: text, attributes: [
        .font: numberFont,
        .foregroundColor: color,
        .paragraphStyle: style,
    ])
    guard let unit = unitRange(in: text) else { return result }
    result.addAttribute(.font, value: unitFont, range: NSRange(unit, in: text))
    return result
}

private func unitRange(in text: String) -> Range<String.Index>? {
    if let space = text.firstIndex(of: " ") {
        let head = text[..<space]
        if head.contains(where: { $0.isNumber }) {
            let start = text.index(after: space)
            guard start < text.endIndex else { return nil }
            return start..<text.endIndex
        }
    }
    guard let index = text.firstIndex(where: { !$0.isNumber && $0 != "." && $0 != "," && $0 != "-" }) else {
        return nil
    }
    guard text[..<index].contains(where: { $0.isNumber }) else { return nil }
    return index..<text.endIndex
}

private class ClickSurface: NSView {
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    private var armed = false

    override var mouseDownCanMoveWindow: Bool { false }

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

    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick {
            onRightClick(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

final class CardView: NSView {
    var fillColor: NSColor = DashTheme.card {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        installCardChrome(self, fill: fillColor)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        installCardChrome(self, fill: fillColor)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = DashTheme.cardRadius
        layer?.masksToBounds = false
        layer?.backgroundColor = fillColor.cgColor
    }

    override func layout() {
        super.layout()
        updateCardShadowPath(self, radius: DashTheme.cardRadius)
    }
}

final class StatTile: NSView {
    let valueLabel: NSTextField

    private let eyebrowLabel: NSTextField
    private let captionLabel: NSTextField
    private let factRow = NSStackView()
    private let bodyStack = NSStackView()
    private var textBottom: NSLayoutConstraint?
    private var embeddedChart: NSView?
    private var factKey = ""

    init(symbol: String, title: String, tint: NSColor) {
        eyebrowLabel = dashLabel("", size: 12, weight: .medium, color: DashTheme.secondaryText)
        eyebrowLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        eyebrowLabel.isHidden = true
        valueLabel = dashLabel("", size: 32, weight: .bold, color: DashTheme.primaryText, mono: true)
        valueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        captionLabel = dashLabel("", size: 12, weight: .regular, color: DashTheme.secondaryText)
        captionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        captionLabel.isHidden = true
        super.init(frame: .zero)
        installCardChrome(self)

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.image = DashTheme.symbol(symbol, pointSize: 13, tint: tint)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = dashLabel(title, size: 14, weight: .semibold, color: tint)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let chevron = NSImageView()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.imageScaling = .scaleProportionallyDown
        chevron.image = DashTheme.symbol("chevron.right", pointSize: 10, tint: DashTheme.secondaryText.withAlphaComponent(0.85))
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let header = NSStackView(views: [icon, titleLabel, spacer, chevron])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.translatesAutoresizingMaskIntoConstraints = false

        factRow.orientation = .horizontal
        factRow.alignment = .bottom
        factRow.distribution = .fillEqually
        factRow.spacing = 8
        factRow.translatesAutoresizingMaskIntoConstraints = false
        factRow.isHidden = true

        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 4
        bodyStack.detachesHiddenViews = true
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.addArrangedSubview(eyebrowLabel)
        bodyStack.addArrangedSubview(valueLabel)
        bodyStack.addArrangedSubview(factRow)
        bodyStack.addArrangedSubview(captionLabel)

        addSubview(header)
        addSubview(bodyStack)

        let bottom = bodyStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        textBottom = bottom
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 12),

            bodyStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bodyStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            bodyStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            valueLabel.widthAnchor.constraint(lessThanOrEqualTo: bodyStack.widthAnchor),
            captionLabel.widthAnchor.constraint(lessThanOrEqualTo: bodyStack.widthAnchor),
            eyebrowLabel.widthAnchor.constraint(lessThanOrEqualTo: bodyStack.widthAnchor),
            factRow.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),
            bottom,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateCardShadowPath(self, radius: DashTheme.cardRadius)
    }

    func setValue(_ value: String, caption: String?) {
        valueLabel.attributedStringValue = metricText(value, numberSize: 32)
        let text = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        captionLabel.stringValue = text
        captionLabel.isHidden = text.isEmpty
    }

    func setEyebrow(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        eyebrowLabel.stringValue = trimmed
        eyebrowLabel.isHidden = trimmed.isEmpty
    }

    func setFacts(_ facts: [(label: String, value: String)]) {
        let key = facts.map { "\($0.label)\u{1}\($0.value)" }.joined(separator: "\u{2}")
        if key == factKey { return }
        factKey = key
        factRow.arrangedSubviews.forEach {
            factRow.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        factRow.isHidden = facts.isEmpty
        captionLabel.isHidden = !facts.isEmpty || captionLabel.stringValue.isEmpty
        for fact in facts.prefix(3) {
            let label = dashLabel(fact.label, size: 11, weight: .regular, color: DashTheme.secondaryText)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let value = dashLabel(fact.value, size: 13, weight: .semibold, color: DashTheme.primaryText, mono: true)
            value.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            let column = NSStackView(views: [label, value])
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 1
            column.translatesAutoresizingMaskIntoConstraints = false
            factRow.addArrangedSubview(column)
            label.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor).isActive = true
            value.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor).isActive = true
        }
    }

    func embedChart(_ chart: NSView, height: CGFloat) {
        embeddedChart?.removeFromSuperview()
        embeddedChart = chart
        textBottom?.priority = .defaultLow
        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.setContentHuggingPriority(.defaultLow, for: .vertical)
        chart.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(chart)
        let hug = chart.topAnchor.constraint(equalTo: bodyStack.bottomAnchor, constant: 12)
        hug.priority = .defaultHigh
        NSLayoutConstraint.activate([
            chart.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chart.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            chart.heightAnchor.constraint(equalToConstant: max(0, height)),
            chart.topAnchor.constraint(greaterThanOrEqualTo: bodyStack.bottomAnchor, constant: 12),
            hug,
        ])
    }
}

final class HeroChartCard: NSView {
    let valueLabel: NSTextField
    let chartContainer = NSView()

    private let tint: NSColor
    private let eyebrowLabel: NSTextField
    private let textColumn = NSStackView()
    private var sideColumn: NSStackView?
    private var sideSnapshot: [(String, String)] = []

    init(eyebrow: String, tint: NSColor) {
        self.tint = tint
        eyebrowLabel = dashLabel(eyebrow, size: 13, weight: .medium, color: DashTheme.secondaryText)
        eyebrowLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel = dashLabel("", size: 44, weight: .bold, color: DashTheme.primaryText, mono: true)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        super.init(frame: .zero)
        installCardChrome(self)

        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 8
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        textColumn.setContentCompressionResistancePriority(.required, for: .horizontal)
        textColumn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        textColumn.addArrangedSubview(eyebrowLabel)
        textColumn.addArrangedSubview(valueLabel)

        chartContainer.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.wantsLayer = true
        chartContainer.layer?.backgroundColor = NSColor.clear.cgColor
        chartContainer.layer?.masksToBounds = true
        chartContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        chartContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(textColumn)
        addSubview(chartContainer)

        let chartFloor = chartContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 136)
        chartFloor.priority = NSLayoutConstraint.Priority(rawValue: 750)
        let chartWidthFloor = chartContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        chartWidthFloor.priority = NSLayoutConstraint.Priority(rawValue: 260)
        NSLayoutConstraint.activate([
            textColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            textColumn.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),

            chartContainer.leadingAnchor.constraint(equalTo: textColumn.trailingAnchor, constant: 20),
            chartContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chartContainer.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            chartContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            chartWidthFloor,
            chartFloor,
            heightAnchor.constraint(greaterThanOrEqualToConstant: 168),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateCardShadowPath(self, radius: DashTheme.cardRadius)
    }

    func setEyebrow(_ text: String) {
        if eyebrowLabel.stringValue != text {
            eyebrowLabel.stringValue = text
        }
    }

    func setValue(_ text: String) {
        valueLabel.attributedStringValue = metricText(text, numberSize: 44)
    }

    func setSideItems(_ items: [(label: String, value: String)]) {
        let snapshot = items.map { ($0.label, $0.value) }
        if snapshot.count == sideSnapshot.count,
           zip(snapshot, sideSnapshot).allSatisfy({ $0.0 == $1.0 && $0.1 == $1.1 }) {
            return
        }
        sideSnapshot = snapshot
        if let sideColumn {
            textColumn.removeArrangedSubview(sideColumn)
            sideColumn.removeFromSuperview()
        }
        sideColumn = nil
        guard !items.isEmpty else { return }

        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        column.setContentCompressionResistancePriority(.required, for: .horizontal)
        column.setContentHuggingPriority(.required, for: .horizontal)
        for item in items {
            let label = dashLabel(item.label, size: 13, weight: .regular, color: DashTheme.secondaryText)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.setContentHuggingPriority(.required, for: .horizontal)
            let value = dashLabel(item.value, size: 13, weight: .semibold, color: DashTheme.primaryText, mono: true)
            value.setContentCompressionResistancePriority(.required, for: .horizontal)
            value.setContentHuggingPriority(.required, for: .horizontal)
            let row = NSStackView(views: [label, value])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 16
            row.translatesAutoresizingMaskIntoConstraints = false
            column.addArrangedSubview(row)
        }
        textColumn.addArrangedSubview(column)
        sideColumn = column
    }
}

final class MiniStat: NSView {
    private let valueLabel: NSTextField
    private let captionLabel: NSTextField
    private let appIcon = NSImageView()
    private let nameRow = NSStackView()

    init(symbol: String, title: String, tint: NSColor, footer: CGFloat = 0) {
        valueLabel = dashLabel("", size: 22, weight: .bold, color: DashTheme.primaryText, mono: true)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        captionLabel = dashLabel("", size: 12, weight: .regular, color: DashTheme.secondaryText)
        captionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        captionLabel.isHidden = true
        super.init(frame: .zero)
        installCardChrome(self)

        let badge = NSView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.wantsLayer = true
        badge.layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
        badge.layer?.cornerRadius = 11
        badge.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.image = DashTheme.symbol(symbol, pointSize: 11, tint: tint)
        badge.addSubview(icon)

        let titleLabel = dashLabel(title, size: 13, weight: .medium, color: titleGray)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [badge, titleLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.isHidden = true
        appIcon.setContentHuggingPriority(.required, for: .horizontal)
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 6
        nameRow.translatesAutoresizingMaskIntoConstraints = false
        nameRow.addArrangedSubview(appIcon)
        nameRow.addArrangedSubview(valueLabel)

        let body = NSStackView(views: [nameRow, captionLabel])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 2
        body.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(body)

        // One height for every summary card. A caption or a meter must not
        // make its card taller than the others in the row.
        let bottomInset: CGFloat = max(16, 14 + footer)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 112),
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13),
            appIcon.widthAnchor.constraint(equalToConstant: 18),
            appIcon.heightAnchor.constraint(equalToConstant: 18),

            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            body.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -bottomInset),
            nameRow.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            captionLabel.widthAnchor.constraint(lessThanOrEqualTo: body.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateCardShadowPath(self, radius: DashTheme.cardRadius)
    }

    func setValue(_ value: String, caption: String?) {
        appIcon.isHidden = true
        appIcon.image = nil
        valueLabel.attributedStringValue = metricText(value, numberSize: 22)
        let text = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        captionLabel.stringValue = text
        captionLabel.isHidden = text.isEmpty
    }

    /// Top-app tile: icon and name stay inside the card, with the metric underneath.
    func setApp(name: String, icon: NSImage?, detail: String?) {
        appIcon.image = icon
        appIcon.isHidden = icon == nil
        valueLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        valueLabel.textColor = DashTheme.primaryText
        valueLabel.stringValue = name
        let text = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        captionLabel.stringValue = text
        captionLabel.isHidden = text.isEmpty
    }
}

final class AppListCard: NSView {
    struct Row: Equatable {
        var name: String
        var detail: String
        var valueText: String
        var fraction: CGFloat
        var icon: NSImage?
        var selected: Bool
        var featured: Bool

        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.name == rhs.name
                && lhs.detail == rhs.detail
                && lhs.valueText == rhs.valueText
                && lhs.fraction == rhs.fraction
                && lhs.selected == rhs.selected
                && lhs.featured == rhs.featured
                && lhs.icon === rhs.icon
        }
    }

    var onSelectRow: ((Int) -> Void)?
    var onRightClickRow: ((Int, NSEvent) -> Void)?

    private let tint: NSColor
    private let rowsContainer = NSView()
    private var rowViews: [AppRowView] = []
    private var rowsBottom: NSLayoutConstraint?
    private var rendered: [Row] = []

    init(title: String, valueHeader: String, tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        installCardChrome(self, fill: listFill)

        let titleLabel = dashLabel(title, size: 12, weight: .medium, color: DashTheme.secondaryText)
        let headerLabel = dashLabel(valueHeader, size: 12, weight: .medium, color: DashTheme.secondaryText, alignment: .right)
        headerLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        rowsContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        addSubview(headerLabel)
        addSubview(rowsContainer)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            headerLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            headerLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            rowsContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowsContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowsContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            rowsContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        setRows([])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateCardShadowPath(self, radius: DashTheme.cardRadius)
    }

    func setRows(_ rows: [Row]) {
        if rows == rendered, rows.count == rowViews.count { return }
        rendered = rows
        if rows.count == rowViews.count {
            for (view, row) in zip(rowViews, rows) {
                view.apply(row)
            }
            return
        }

        rowsBottom?.isActive = false
        rowsBottom = nil
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        var previous: NSView?
        for (index, row) in rows.enumerated() {
            let view = AppRowView(tint: tint)
            view.apply(row)
            view.translatesAutoresizingMaskIntoConstraints = false
            let rowIndex = index
            view.onClick = { [weak self] in
                self?.onSelectRow?(rowIndex)
            }
            view.onRightClick = { [weak self] event in
                self?.onRightClickRow?(rowIndex, event)
            }
            rowsContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: rowsContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: rowsContainer.trailingAnchor),
                view.heightAnchor.constraint(equalToConstant: 58),
                view.topAnchor.constraint(equalTo: previous?.bottomAnchor ?? rowsContainer.topAnchor),
            ])
            previous = view
            rowViews.append(view)
        }

        if let previous {
            rowsBottom = previous.bottomAnchor.constraint(equalTo: rowsContainer.bottomAnchor)
        } else {
            rowsBottom = rowsContainer.heightAnchor.constraint(equalToConstant: 0)
        }
        rowsBottom?.isActive = true
    }

    func rowView(at index: Int) -> NSView? {
        rowViews.indices.contains(index) ? rowViews[index] : nil
    }
}

private final class AppRowView: ClickSurface {
    private let tint: NSColor
    private let plate = NSView()
    private let iconWell = NSView()
    private let iconView = NSImageView()
    private let monogramLabel: NSTextField
    private let nameLabel: NSTextField
    private let detailLabel: NSTextField
    private let valueLabel: NSTextField
    private let meter: RowMeter
    private var iconToken: ObjectIdentifier?

    init(tint: NSColor) {
        self.tint = tint
        monogramLabel = dashLabel("", size: 13, weight: .semibold, color: tint, alignment: .center)
        nameLabel = dashLabel("", size: 14, weight: .semibold, color: DashTheme.primaryText)
        detailLabel = dashLabel("", size: 12, weight: .regular, color: DashTheme.secondaryText)
        valueLabel = dashLabel("", size: 13, weight: .semibold, color: DashTheme.primaryText, mono: true, alignment: .right)
        meter = RowMeter(tint: tint)
        super.init(frame: .zero)
        wantsLayer = true

        plate.translatesAutoresizingMaskIntoConstraints = false
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor.white.cgColor
        plate.layer?.cornerRadius = DashTheme.innerRadius
        plate.layer?.masksToBounds = false

        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 8
        iconWell.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconWell.addSubview(iconView)
        iconWell.addSubview(monogramLabel)

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = NSStackView(views: [nameLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        meter.translatesAutoresizingMaskIntoConstraints = false

        addSubview(plate)
        addSubview(iconWell)
        addSubview(textStack)
        addSubview(valueLabel)
        addSubview(meter)

        let lane = meter.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.32)
        lane.priority = NSLayoutConstraint.Priority.defaultHigh
        NSLayoutConstraint.activate([
            plate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            plate.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            plate.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            plate.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),

            iconWell.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconWell.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWell.widthAnchor.constraint(equalToConstant: 28),
            iconWell.heightAnchor.constraint(equalToConstant: 28),
            iconView.leadingAnchor.constraint(equalTo: iconWell.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: iconWell.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: iconWell.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconWell.bottomAnchor),
            monogramLabel.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            monogramLabel.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: meter.leadingAnchor, constant: -12),

            meter.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            meter.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            meter.heightAnchor.constraint(equalToConstant: 4),
            lane,

            valueLabel.trailingAnchor.constraint(equalTo: meter.trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: meter.topAnchor, constant: -4),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ row: AppListCard.Row) {
        let measured = row.valueText != "—"
        plate.isHidden = !row.selected
        nameLabel.stringValue = row.name
        detailLabel.stringValue = row.detail
        detailLabel.isHidden = row.detail.isEmpty
        valueLabel.stringValue = row.valueText
        meter.fraction = measured ? row.fraction : 0
        meter.emphasized = row.selected
        if let icon = row.icon {
            let token = ObjectIdentifier(icon)
            if iconToken != token {
                iconView.image = icon
                iconToken = token
            }
            iconView.isHidden = false
            monogramLabel.isHidden = true
            iconWell.layer?.backgroundColor = NSColor.clear.cgColor
            return
        }
        iconToken = nil
        iconView.image = nil
        iconView.isHidden = true
        monogramLabel.isHidden = false
        monogramLabel.stringValue = monogram(row.name)
        iconWell.layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
    }

    private func monogram(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}

private final class RowMeter: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var emphasized = false { didSet { needsDisplay = true } }
    let tint: NSColor

    init(tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        tint.withAlphaComponent(0.18).setFill()
        track.fill()

        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0 else { return }
        var bar = bounds
        bar.size.width = min(bounds.width, max(bounds.height, bounds.width * clamped))
        let fill = NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2)
        (emphasized ? tint : tint.withAlphaComponent(0.72)).setFill()
        fill.fill()
    }
}

final class ProjectsBanner: NSView {
    var onStopAll: (() -> Void)?

    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let stopButton = StopAllButton(title: "Stop All...")

    override init(frame frameRect: NSRect) {
        titleLabel = dashLabel("", size: 14, weight: .bold, color: DashTheme.primaryText)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailLabel = dashLabel("", size: 12, weight: .regular, color: DashTheme.secondaryText)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        super.init(frame: frameRect)
        wantsLayer = true
        if let aqua = NSAppearance(named: .aqua) {
            appearance = aqua
        }
        layer?.cornerRadius = 18
        layer?.masksToBounds = false
        layer?.backgroundColor = bannerFill.cgColor

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.image = DashTheme.symbol("moon.zzz.fill", pointSize: 15, tint: DashTheme.accent(.projects))
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let textColumn = NSStackView(views: [titleLabel, detailLabel])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 2
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        textColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textColumn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let leading = NSStackView(views: [icon, textColumn])
        leading.orientation = .horizontal
        leading.alignment = .centerY
        leading.spacing = 10
        leading.translatesAutoresizingMaskIntoConstraints = false
        leading.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.setContentHuggingPriority(.required, for: .horizontal)
        stopButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        stopButton.isHidden = true
        stopButton.onClick = { [weak self] in
            self?.onStopAll?()
        }

        let root = NSStackView(views: [leading, stopButton])
        root.orientation = .horizontal
        root.alignment = .centerY
        root.distribution = .gravityAreas
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.detachesHiddenViews = true
        addSubview(root)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 18
    }

    func set(title: String, detail: String, showsStop: Bool) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        detailLabel.isHidden = detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        stopButton.isHidden = !showsStop
    }
}

private final class StopAllButton: ClickSurface {
    private let title: String
    private var pressed = false {
        didSet { needsDisplay = true }
    }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let width = (title as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(width) + 28, height: 30)
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (pressed ? stopPressed : stopFill).setFill()
        path.fill()

        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ])
        let box = text.boundingRect(
            with: NSSize(width: bounds.width, height: 80),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let rect = NSRect(
            x: 0,
            y: max(0, (bounds.height - box.height) / 2),
            width: bounds.width,
            height: box.height
        )
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        super.mouseUp(with: event)
    }
}
