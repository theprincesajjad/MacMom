import AppKit

enum DashTheme {
    static let canvas = NSColor(srgbRed: 0.965, green: 0.965, blue: 0.970, alpha: 1)
    static let card = NSColor.white
    static let primaryText = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)
    static let secondaryText = NSColor(srgbRed: 0.45, green: 0.48, blue: 0.52, alpha: 1)
    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 16

    static func accent(_ tab: DashTab) -> NSColor {
        switch tab {
        case .overview:
            return NSColor(srgbRed: 0.42, green: 0.51, blue: 0.64, alpha: 1)
        case .cpu:
            return NSColor(srgbRed: 0.23, green: 0.48, blue: 0.96, alpha: 1)
        case .memory:
            return NSColor(srgbRed: 0.45, green: 0.36, blue: 0.95, alpha: 1)
        case .disk:
            return NSColor(srgbRed: 0.95, green: 0.60, blue: 0.16, alpha: 1)
        case .network:
            return NSColor(srgbRed: 0.16, green: 0.70, blue: 0.50, alpha: 1)
        case .gpu:
            return NSColor(srgbRed: 0.91, green: 0.35, blue: 0.56, alpha: 1)
        case .battery:
            return NSColor(srgbRed: 0.16, green: 0.66, blue: 0.33, alpha: 1)
        case .projects:
            return NSColor(srgbRed: 0.92, green: 0.55, blue: 0.42, alpha: 1)
        }
    }

    static func accentWash(_ tab: DashTab) -> NSColor {
        mix(accent(tab), with: .white, amount: 0.22)
    }

    static func symbol(_ name: String, pointSize: CGFloat, tint: NSColor) -> NSImage {
        let side = max(pointSize, 1)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?.copy() as? NSImage else {
            return NSImage(size: NSSize(width: side, height: side))
        }
        base.isTemplate = false
        let size = (base.size.width > 0 && base.size.height > 0) ? base.size : NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            tint.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func applyCardShadow(to view: NSView) {
        view.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.14, alpha: 0.10)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 14
        view.shadow = shadow
        view.layer?.masksToBounds = false
    }

    private static func mix(_ color: NSColor, with other: NSColor, amount: CGFloat) -> NSColor {
        guard let foreground = color.usingColorSpace(.sRGB),
              let background = other.usingColorSpace(.sRGB) else {
            return color.withAlphaComponent(amount)
        }
        let mix = min(max(amount, 0), 1)
        return NSColor(
            srgbRed: foreground.redComponent * mix + background.redComponent * (1 - mix),
            green: foreground.greenComponent * mix + background.greenComponent * (1 - mix),
            blue: foreground.blueComponent * mix + background.blueComponent * (1 - mix),
            alpha: 1
        )
    }
}
