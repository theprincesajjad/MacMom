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
        cell.isScrollable = true
        cell.usesSingleLineMode = true
        cell.lineBreakMode = .byTruncatingTail
    }
    return field
}

private func metricText(_ text: String, numberSize: CGFloat) -> NSAttributedString {
    let color = DashTheme.primaryText
    let numberFont = NSFont.monospacedDigitSystemFont(ofSize: numberSize, weight: .bold)
    let unitFont = NSFont.systemFont(ofSize: max(12, (numberSize * 0.40).rounded()), weight: .bold)
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
    private var armed = false

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

    private let captionLabel: NSTextField
    private let bodyStack = NSStackView()
    private var textBottom: NSLayoutConstraint?
    private var embeddedChart: NSView?

    init(symbol: String, title: String, tint: NSColor) {
        valueLabel = dashLabel("", size: 34, weight: .bold, color: DashTheme.primaryText, mono: true)
        valueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        captionLabel = dashLabel("", size: 13, weight: .regular, color: DashTheme.secondaryText)
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

        let header = NSStackView(views: [icon, titleLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.translatesAutoresizingMaskIntoConstraints = false

        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 2
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.addArrangedSubview(valueLabel)
        bodyStack.addArrangedSubview(captionLabel)

        addSubview(header)
        addSubview(bodyStack)

        let bottom = bodyStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        textBottom = bottom
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            header.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            bodyStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bodyStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            bodyStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
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
        valueLabel.attributedStringValue = metricText(value, numberSize: 34)
        let text = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        captionLabel.stringValue = text
        captionLabel.isHidden = text.isEmpty
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
    private var sideGrid: NSGridView?

    init(eyebrow: String, tint: NSColor) {
        self.tint = tint
        eyebrowLabel = dashLabel(eyebrow, size: 13, weight: .medium, color: DashTheme.secondaryText)
        eyebrowLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel = dashLabel("", size: 48, weight: .bold, color: DashTheme.primaryText, mono: true)
        valueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        super.init(frame: .zero)
        installCardChrome(self)

        chartContainer.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.wantsLayer = true
        chartContainer.layer?.backgroundColor = tint.withAlphaComponent(0).cgColor
        chartContainer.layer?.masksToBounds = false
        chartContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        chartContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(eyebrowLabel)
        addSubview(valueLabel)
        addSubview(chartContainer)

        NSLayoutConstraint.activate([
            eyebrowLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            eyebrowLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            eyebrowLabel.trailingAnchor.constraint(lessThanOrEqualTo: chartContainer.leadingAnchor, constant: -12),

            valueLabel.leadingAnchor.constraint(equalTo: eyebrowLabel.leadingAnchor),
            valueLabel.topAnchor.constraint(equalTo: eyebrowLabel.bottomAnchor, constant: 2),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: chartContainer.leadingAnchor, constant: -12),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),

            chartContainer.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            chartContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            chartContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chartContainer.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.62),
            chartContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 148),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateCardShadowPath(self, radius: DashTheme.cardRadius)
    }

    func setValue(_ text: String) {
        valueLabel.attributedStringValue = metricText(text, numberSize: 48)
    }

    func setSideItems(_ items: [(label: String, value: String)]) {
        sideGrid?.removeFromSuperview()
        sideGrid = nil
        guard !items.isEmpty else { return }

        let rows: [[NSView]] = items.map { item in
            let label = dashLabel(item.label, size: 13, weight: .regular, color: DashTheme.secondaryText)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let value = dashLabel(item.value, size: 13, weight: .semibold, color: DashTheme.primaryText, mono: true, alignment: .right)
            value.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            value.setContentHuggingPriority(.required, for: .horizontal)
            return [label, value]
        }
        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 7
        grid.columnSpacing = 22
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        grid.setContentHuggingPriority(.required, for: .horizontal)
        grid.setContentHuggingPriority(.required, for: .vertical)
        grid.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        grid.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: eyebrowLabel.leadingAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            grid.topAnchor.constraint(greaterThanOrEqualTo: valueLabel.bottomAnchor, constant: 14),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: chartContainer.leadingAnchor, constant: -12),
        ])
        sideGrid = grid
    }
}

final class MiniStat: NSView {
    private let valueLabel: NSTextField
    private let captionLabel: NSTextField

    init(symbol: String, title: String, tint: NSColor) {
        valueLabel = dashLabel("", size: 22, weight: .bold, color: DashTheme.primaryText, mono: true)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
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

        let body = NSStackView(views: [valueLabel, captionLabel])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 2
        body.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(body)

        let hug = body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        hug.priority = .defaultLow
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13),

            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            header.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            body.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),
            hug,
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
        valueLabel.attributedStringValue = metricText(value, numberSize: 22)
        let text = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.name == rhs.name
                && lhs.detail == rhs.detail
                && lhs.valueText == rhs.valueText
                && lhs.fraction == rhs.fraction
                && lhs.selected == rhs.selected
                && lhs.icon === rhs.icon
        }
    }

    var onSelectRow: ((Int) -> Void)?

    private let tint: NSColor
    private let rowsContainer = NSView()
    private var rowViews: [AppRowView] = []
    private var rowsBottom: NSLayoutConstraint?

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
        rowsBottom?.isActive = false
        rowsBottom = nil
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        var previous: NSView?
        for (index, row) in rows.enumerated() {
            let view = AppRowView(row: row, tint: tint)
            view.translatesAutoresizingMaskIntoConstraints = false
            let rowIndex = index
            view.onClick = { [weak self] in
                self?.onSelectRow?(rowIndex)
            }
            rowsContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: rowsContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: rowsContainer.trailingAnchor),
                view.heightAnchor.constraint(equalToConstant: 56),
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
}

private final class AppRowView: ClickSurface {
    private let plate = NSView()

    init(row: AppListCard.Row, tint: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true

        plate.translatesAutoresizingMaskIntoConstraints = false
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor.white.cgColor
        plate.layer?.cornerRadius = DashTheme.innerRadius
        plate.layer?.masksToBounds = false
        plate.isHidden = !row.selected

        let iconWell = NSView()
        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 8
        iconWell.layer?.masksToBounds = true
        installIcon(row: row, tint: tint, in: iconWell)

        let nameLabel = dashLabel(row.name, size: 14, weight: .semibold, color: DashTheme.primaryText)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detailLabel = dashLabel(row.detail, size: 12, weight: .regular, color: DashTheme.secondaryText)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.isHidden = row.detail.isEmpty

        let textStack = NSStackView(views: [nameLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let valueLabel = dashLabel(row.valueText, size: 13, weight: .semibold, color: DashTheme.primaryText, mono: true, alignment: .right)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let meter = RowMeter(fraction: row.fraction, tint: tint, emphasized: row.selected)
        meter.translatesAutoresizingMaskIntoConstraints = false

        addSubview(plate)
        addSubview(iconWell)
        addSubview(textStack)
        addSubview(valueLabel)
        addSubview(meter)

        let lane = meter.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.34)
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

            textStack.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -10),

            meter.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            meter.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            meter.heightAnchor.constraint(equalToConstant: 3),
            meter.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 12),
            lane,

            valueLabel.trailingAnchor.constraint(equalTo: meter.trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: meter.topAnchor, constant: -4),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installIcon(row: AppListCard.Row, tint: NSColor, in well: NSView) {
        if let icon = row.icon {
            well.layer?.backgroundColor = NSColor.clear.cgColor
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.image = icon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            well.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: well.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: well.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: well.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: well.bottomAnchor),
            ])
            return
        }
        well.layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
        let letter = monogram(row.name)
        let label = dashLabel(letter, size: 13, weight: .semibold, color: tint, alignment: .center)
        well.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: well.centerYAnchor),
        ])
    }

    private func monogram(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}

private final class RowMeter: NSView {
    let fraction: CGFloat
    let tint: NSColor
    let emphasized: Bool

    init(fraction: CGFloat, tint: NSColor, emphasized: Bool) {
        self.fraction = fraction
        self.tint = tint
        self.emphasized = emphasized
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
