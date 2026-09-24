import AppKit

/// Renders a fixed-size share card from measured dashboard state.
enum GlanceExport {
    /// 1200 by 630 points, dark card. Uses only measured fields on `state`. Missing numbers become an em dash via GlanceFormat. Never invent CPU, memory, or app figures.
    static func shareCard(state: DashState) -> NSImage {
        let size = NSSize(width: 1200, height: 630)
        if let image = rasterCard(state: state, size: size), !image.representations.isEmpty {
            return image
        }
        return focusCard(state: state, size: size)
    }

    /// PNG bytes of an image, or nil if the bitmap cannot be produced.
    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation else { return nil }
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Replaces the general pasteboard with the PNG. Call NSPasteboard.general.clearContents() before writing. Write both .png data and a TIFF for apps that only read TIFF.
    static func copyToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let png = pngData(image)
        let tiff = image.tiffRepresentation
        var types: [NSPasteboard.PasteboardType] = []
        if png != nil {
            types.append(.png)
        }
        if tiff != nil {
            types.append(.tiff)
        }
        guard !types.isEmpty else { return }
        pasteboard.declareTypes(types, owner: nil)
        if let png {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// Bitmap of a view's current drawing, or nil if the view has no size.
    static func snapshot(_ view: NSView) -> NSImage? {
        let bounds = view.bounds
        guard !bounds.isEmpty else { return nil }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private static let margin: CGFloat = 48

    /// Unflipped user space: origin is the bottom left. Callers install the context first.
    private static func render(_ state: DashState, size: NSSize) {
        GlanceTheme.canvas.setFill()
        NSRect(origin: .zero, size: size).fill()

        let left = margin
        let right = size.width - margin
        let width = right - left
        var top = margin

        top = drawHeader(left: left, right: right, top: top, canvasHeight: size.height)
        top += 32
        top = drawMemoryHero(state, left: left, width: width, top: top, canvasHeight: size.height)
        top += 18
        drawMemoryBar(
            state,
            in: NSRect(x: left, y: size.height - top - 16, width: width, height: 16)
        )
        top += 16 + 22
        top = drawCPU(state, left: left, top: top, canvasHeight: size.height)
        top += 26
        drawApps(state, left: left, right: right, top: top, canvasHeight: size.height)
        drawFooter(right: right)
    }

    private static func rasterCard(state: DashState, size: NSSize) -> NSImage? {
        let pixelsWide = Int(size.width.rounded())
        let pixelsHigh = Int(size.height.rounded())
        guard pixelsWide > 0, pixelsHigh > 0 else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        draw(state, size: size, in: context)
        let output = rep.converting(to: .sRGB, renderingIntent: .relativeColorimetric) ?? rep
        output.size = size
        let image = NSImage(size: size)
        image.isTemplate = false
        image.addRepresentation(output)
        return image
    }

    private static func focusCard(state: DashState, size: NSSize) -> NSImage {
        let drawing = NSImage(size: size, flipped: false) { rect in
            render(state, size: rect.size)
            return true
        }
        guard let tiff = drawing.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return drawing
        }
        rep.size = size
        let image = NSImage(size: size)
        image.isTemplate = false
        image.addRepresentation(rep)
        return image
    }

    private static func draw(_ state: DashState, size: NSSize, in context: NSGraphicsContext) {
        context.imageInterpolation = .high
        context.shouldAntialias = true
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        render(state, size: size)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawHeader(left: CGFloat, right: CGFloat, top: CGFloat, canvasHeight: CGFloat) -> CGFloat {
        let symbol = GlanceTheme.symbol("waveform", pointSize: 18, tint: GlanceTheme.accent(.cpu))
        let titleFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
        let modelFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        let titleHeight = titleFont.ascender - titleFont.descender
        let bandHeight = max(28, max(symbol.size.height, titleHeight))
        let band = NSRect(x: left, y: canvasHeight - top - bandHeight, width: right - left, height: bandHeight)
        var titleX = left
        if symbol.size.width > 0, symbol.size.height > 0 {
            let symbolRect = NSRect(
                x: left,
                y: band.minY + (band.height - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
            titleX = symbolRect.maxX + 10
        }
        let titleBaseline = baseline(centeredIn: band, font: titleFont)
        let titleWidth = drawText("Appfold", at: NSPoint(x: titleX, y: titleBaseline), font: titleFont, color: GlanceTheme.primary)
        let model = GlanceHost.modelName
        if !model.isEmpty {
            let maxWidth = right - (titleX + titleWidth + 16)
            let shown = truncated(model, font: modelFont, maxWidth: maxWidth)
            if !shown.isEmpty {
                let modelBaseline = baseline(centeredIn: band, font: modelFont)
                let modelWidth = textWidth(shown, font: modelFont)
                drawText(shown, at: NSPoint(x: right - modelWidth, y: modelBaseline), font: modelFont, color: GlanceTheme.secondary)
            }
        }
        return top + bandHeight
    }

    private static func drawMemoryHero(_ state: DashState, left: CGFloat, width: CGFloat, top: CGFloat, canvasHeight: CGFloat) -> CGFloat {
        let pair = GlanceFormat.bytePair(state.memoryUsed)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 72, weight: .semibold)
        let unitFont = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        let ofFont = NSFont.systemFont(ofSize: 20, weight: .medium)
        let numberBaseline = baseline(fromTop: top, font: numberFont, canvasHeight: canvasHeight)
        var x = left
        x += drawText(pair.number, at: NSPoint(x: x, y: numberBaseline), font: numberFont, color: GlanceTheme.primary) + 10
        x += drawText(pair.unit, at: NSPoint(x: x, y: numberBaseline), font: unitFont, color: GlanceTheme.secondary) + 16
        let ofText = "of " + GlanceFormat.byteText(state.memoryTotal)
        let shown = truncated(ofText, font: ofFont, maxWidth: left + width - x)
        if !shown.isEmpty {
            let unitCenter = numberBaseline + (unitFont.ascender + unitFont.descender) / 2
            let ofBaseline = unitCenter - (ofFont.ascender + ofFont.descender) / 2
            drawText(shown, at: NSPoint(x: x, y: ofBaseline), font: ofFont, color: GlanceTheme.secondary)
        }
        return top + (numberFont.ascender - numberFont.descender)
    }

    private static func drawMemoryBar(_ state: DashState, in rect: NSRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = rect.height / 2
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        GlanceTheme.track.setFill()
        rect.fill()
        let segments: [(UInt64, NSColor)] = [
            (state.memoryApp, GlanceTheme.accent(.cpu)),
            (state.memoryWired, GlanceTheme.accent(.disk)),
            (state.memoryCompressed, GlanceTheme.accent(.network))
        ]
        var x = rect.minX
        for (bytes, color) in segments {
            let fraction = GlanceFormat.fraction(bytes, of: state.memoryTotal)
            let available = rect.maxX - x
            let drawWidth = min(rect.width * fraction, max(0, available))
            if drawWidth <= 0 { continue }
            color.setFill()
            NSRect(x: x, y: rect.minY, width: drawWidth, height: rect.height).fill()
            x += drawWidth
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawCPU(_ state: DashState, left: CGFloat, top: CGFloat, canvasHeight: CGFloat) -> CGFloat {
        let labelFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        let valueBaseline = baseline(fromTop: top, font: valueFont, canvasHeight: canvasHeight)
        let labelWidth = drawText("CPU", at: NSPoint(x: left, y: valueBaseline), font: labelFont, color: GlanceTheme.secondary)
        let value = GlanceFormat.percentHero(state.cpuNow) + "%"
        drawText(value, at: NSPoint(x: left + labelWidth + 12, y: valueBaseline), font: valueFont, color: GlanceTheme.primary)
        return top + (valueFont.ascender - valueFont.descender)
    }

    private static func drawApps(_ state: DashState, left: CGFloat, right: CGFloat, top: CGFloat, canvasHeight: CGFloat) {
        let ranked = topApps(state.apps)
        let nameFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        if ranked.isEmpty {
            let y = baseline(fromTop: top, font: nameFont, canvasHeight: canvasHeight)
            drawText("No apps yet", at: NSPoint(x: left, y: y), font: nameFont, color: GlanceTheme.secondary)
            return
        }
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        let rowHeight: CGFloat = 34
        let meterWidth: CGFloat = 120
        let meterHeight: CGFloat = 8
        let footerFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let footerClearance = margin + footerFont.ascender - footerFont.descender + 12
        var rowTop = top
        for app in ranked {
            let row = NSRect(x: left, y: canvasHeight - rowTop - rowHeight, width: right - left, height: rowHeight)
            if row.minY < footerClearance { break }
            let value = GlanceFormat.byteText(app.memoryBytes)
            let valueWidth = textWidth(value, font: valueFont)
            let valueX = right - valueWidth
            let meterX = valueX - 14 - meterWidth
            let name = truncated(app.name, font: nameFont, maxWidth: max(0, meterX - 16 - left))
            let nameBaseline = baseline(centeredIn: row, font: nameFont)
            let valueBaseline = baseline(centeredIn: row, font: valueFont)
            if !name.isEmpty {
                drawText(name, at: NSPoint(x: left, y: nameBaseline), font: nameFont, color: GlanceTheme.primary)
            }
            let meterRect = NSRect(x: meterX, y: row.midY - meterHeight / 2, width: meterWidth, height: meterHeight)
            drawMeter(in: meterRect, fraction: GlanceFormat.fraction(app.memoryBytes, of: state.memoryTotal), fill: GlanceTheme.accent(.memory))
            drawText(value, at: NSPoint(x: valueX, y: valueBaseline), font: valueFont, color: GlanceTheme.primary)
            rowTop += rowHeight
        }
    }

    private static func drawFooter(right: CGFloat) {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let text = "Appfold"
        let width = textWidth(text, font: font)
        let baseline = margin - font.descender
        drawText(text, at: NSPoint(x: right - width, y: baseline), font: font, color: GlanceTheme.tertiary)
    }

    private static func drawMeter(in rect: NSRect, fraction: CGFloat, fill: NSColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = rect.height / 2
        GlanceTheme.track.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0 else { return }
        let width = min(rect.width, max(rect.height, rect.width * clamped))
        fill.setFill()
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    private static func topApps(_ apps: [DashApp]) -> [DashApp] {
        apps.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.memoryBytes == rhs.element.memoryBytes {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.memoryBytes > rhs.element.memoryBytes
            }
            .prefix(5)
            .map(\.element)
    }

    private static func baseline(fromTop top: CGFloat, font: NSFont, canvasHeight: CGFloat) -> CGFloat {
        (canvasHeight - top - font.ascender).rounded()
    }

    private static func baseline(centeredIn band: NSRect, font: NSFont) -> CGFloat {
        (band.midY - (font.ascender + font.descender) / 2).rounded()
    }

    @discardableResult
    private static func drawText(_ text: String, at baselineOrigin: NSPoint, font: NSFont, color: NSColor) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let string = text as NSString
        string.draw(at: baselineOrigin, withAttributes: attributes)
        return ceil(string.size(withAttributes: attributes).width)
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func truncated(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        if maxWidth <= 0 { return "" }
        if textWidth(text, font: font) <= maxWidth { return text }
        let ellipsis = "…"
        if textWidth(ellipsis, font: font) > maxWidth { return "" }
        let characters = Array(text)
        var low = 0
        var high = characters.count
        var best = ellipsis
        while low <= high {
            let mid = (low + high) / 2
            let candidate = String(characters.prefix(mid)) + ellipsis
            if textWidth(candidate, font: font) <= maxWidth {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }
}
