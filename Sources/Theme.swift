import AppKit

// MARK: - Palettes

struct Palette {
    let name: String
    let base: NSColor
    let glowA: NSColor
    let glowB: NSColor
    let accent: NSColor
    let danger: NSColor
    // Card tint trio (screenshot / audio / draw etc.)
    let foam: NSColor
    let iris: NSColor
    let rose: NSColor
    let hairline: NSColor
    let divider: NSColor
    let rowHover: NSColor
    let cardBg: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let hoverBg: NSColor
    let selectedBg: NSColor
    let fieldBg: NSColor
    let selectedText: NSColor
}

// MARK: - Theme (forwards to the selected palette)

enum Theme {
    static let rosePine = Palette(
        name: "rosé pine",
        base: NSColor(red: 0.098, green: 0.090, blue: 0.141, alpha: 1),
        glowA: NSColor(red: 0.769, green: 0.655, blue: 0.906, alpha: 0.11),
        glowB: NSColor(red: 0.612, green: 0.812, blue: 0.847, alpha: 0.06),
        accent: NSColor(red: 0.965, green: 0.757, blue: 0.467, alpha: 1),
        danger: NSColor(red: 0.922, green: 0.435, blue: 0.573, alpha: 1),
        foam: NSColor(red: 0.612, green: 0.812, blue: 0.847, alpha: 1),
        iris: NSColor(red: 0.769, green: 0.655, blue: 0.906, alpha: 1),
        rose: NSColor(red: 0.922, green: 0.737, blue: 0.729, alpha: 1),
        hairline: NSColor(red: 0.565, green: 0.549, blue: 0.667, alpha: 0.20),
        divider: NSColor(red: 0.565, green: 0.549, blue: 0.667, alpha: 0.12),
        rowHover: NSColor(red: 0.769, green: 0.655, blue: 0.906, alpha: 0.08),
        cardBg: NSColor(red: 0.149, green: 0.137, blue: 0.227, alpha: 0.65),
        textPrimary: NSColor(red: 0.878, green: 0.871, blue: 0.957, alpha: 1),
        textSecondary: NSColor(red: 0.565, green: 0.549, blue: 0.667, alpha: 1),
        textTertiary: NSColor(red: 0.431, green: 0.416, blue: 0.525, alpha: 0.90),
        hoverBg: NSColor(red: 0.769, green: 0.655, blue: 0.906, alpha: 0.11),
        selectedBg: NSColor(red: 0.965, green: 0.757, blue: 0.467, alpha: 0.16),
        fieldBg: NSColor(red: 0.149, green: 0.137, blue: 0.227, alpha: 0.85),
        selectedText: NSColor(red: 0.980, green: 0.878, blue: 0.722, alpha: 1)
    )

    static let terminal = Palette(
        name: "terminal",
        base: NSColor(red: 0.030, green: 0.052, blue: 0.040, alpha: 1),
        glowA: NSColor(red: 0.25, green: 0.95, blue: 0.55, alpha: 0.12),
        glowB: NSColor(red: 0.10, green: 0.65, blue: 0.85, alpha: 0.06),
        accent: NSColor(red: 0.25, green: 0.95, blue: 0.55, alpha: 1),
        danger: NSColor(red: 0.98, green: 0.38, blue: 0.40, alpha: 1),
        foam: NSColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 1),
        iris: NSColor(red: 0.55, green: 1.00, blue: 0.75, alpha: 1),
        rose: NSColor(red: 1.00, green: 0.75, blue: 0.35, alpha: 1),
        hairline: NSColor(red: 0.40, green: 1.00, blue: 0.60, alpha: 0.13),
        divider: NSColor(red: 0.40, green: 1.00, blue: 0.60, alpha: 0.08),
        rowHover: NSColor(red: 0.40, green: 1.00, blue: 0.60, alpha: 0.06),
        cardBg: NSColor(red: 0.40, green: 1.00, blue: 0.60, alpha: 0.04),
        textPrimary: NSColor(red: 0.88, green: 0.98, blue: 0.91, alpha: 1),
        textSecondary: NSColor(red: 0.55, green: 0.78, blue: 0.62, alpha: 0.85),
        textTertiary: NSColor(red: 0.45, green: 0.70, blue: 0.52, alpha: 0.55),
        hoverBg: NSColor(red: 0.40, green: 1.00, blue: 0.60, alpha: 0.09),
        selectedBg: NSColor(red: 0.40, green: 1.00, blue: 0.60, alpha: 0.14),
        fieldBg: NSColor(red: 0.40, green: 1.00, blue: 0.60, alpha: 0.07),
        selectedText: NSColor(red: 0.78, green: 1.00, blue: 0.86, alpha: 1)
    )

    static let violet = Palette(
        name: "violet",
        base: NSColor(red: 0.043, green: 0.043, blue: 0.067, alpha: 1),
        glowA: NSColor(red: 0.48, green: 0.38, blue: 1.00, alpha: 0.12),
        glowB: NSColor(red: 0.15, green: 0.45, blue: 1.00, alpha: 0.07),
        accent: NSColor(red: 0.58, green: 0.48, blue: 1.00, alpha: 1),
        danger: NSColor(red: 0.96, green: 0.40, blue: 0.42, alpha: 1),
        foam: NSColor(red: 0.40, green: 0.62, blue: 1.00, alpha: 1),
        iris: NSColor(red: 0.70, green: 0.50, blue: 1.00, alpha: 1),
        rose: NSColor(red: 0.98, green: 0.60, blue: 0.45, alpha: 1),
        hairline: NSColor.white.withAlphaComponent(0.10),
        divider: NSColor.white.withAlphaComponent(0.07),
        rowHover: NSColor.white.withAlphaComponent(0.07),
        cardBg: NSColor.white.withAlphaComponent(0.05),
        textPrimary: .white,
        textSecondary: NSColor.white.withAlphaComponent(0.48),
        textTertiary: NSColor.white.withAlphaComponent(0.32),
        hoverBg: NSColor.white.withAlphaComponent(0.08),
        selectedBg: NSColor(red: 0.58, green: 0.48, blue: 1.00, alpha: 0.16),
        fieldBg: NSColor.white.withAlphaComponent(0.06),
        selectedText: NSColor(red: 0.85, green: 0.82, blue: 1.00, alpha: 1)
    )

    static let slate = Palette(
        name: "slate",
        base: NSColor(red: 0.051, green: 0.067, blue: 0.090, alpha: 1),
        glowA: NSColor(red: 0.345, green: 0.651, blue: 1.00, alpha: 0.10),
        glowB: NSColor(red: 0.20, green: 0.80, blue: 0.75, alpha: 0.05),
        accent: NSColor(red: 0.345, green: 0.651, blue: 1.00, alpha: 1),
        danger: NSColor(red: 0.95, green: 0.42, blue: 0.42, alpha: 1),
        foam: NSColor(red: 0.30, green: 0.82, blue: 0.75, alpha: 1),
        iris: NSColor(red: 0.65, green: 0.55, blue: 0.95, alpha: 1),
        rose: NSColor(red: 0.95, green: 0.72, blue: 0.35, alpha: 1),
        hairline: NSColor(red: 0.60, green: 0.70, blue: 0.85, alpha: 0.16),
        divider: NSColor(red: 0.60, green: 0.70, blue: 0.85, alpha: 0.10),
        rowHover: NSColor(red: 0.345, green: 0.651, blue: 1.00, alpha: 0.07),
        cardBg: NSColor(red: 0.65, green: 0.75, blue: 0.90, alpha: 0.06),
        textPrimary: NSColor(red: 0.90, green: 0.93, blue: 0.96, alpha: 1),
        textSecondary: NSColor(red: 0.55, green: 0.62, blue: 0.70, alpha: 1),
        textTertiary: NSColor(red: 0.42, green: 0.48, blue: 0.56, alpha: 0.90),
        hoverBg: NSColor(red: 0.345, green: 0.651, blue: 1.00, alpha: 0.10),
        selectedBg: NSColor(red: 0.345, green: 0.651, blue: 1.00, alpha: 0.16),
        fieldBg: NSColor(red: 0.65, green: 0.75, blue: 0.90, alpha: 0.08),
        selectedText: NSColor(red: 0.75, green: 0.87, blue: 1.00, alpha: 1)
    )

    static let palettes: [Palette] = [rosePine, terminal, violet, slate]

    static var current: Palette = {
        let saved = UserDefaults.standard.string(forKey: "wac.theme")
        return palettes.first { $0.name == saved } ?? rosePine
    }()

    static func select(_ name: String) {
        guard let palette = palettes.first(where: { $0.name == name }) else { return }
        current = palette
        UserDefaults.standard.set(name, forKey: "wac.theme")
    }

    // Forwarders — all UI code reads Theme.<color>
    static var base: NSColor { current.base }
    static var glowViolet: NSColor { current.glowA }
    static var glowBlue: NSColor { current.glowB }
    static var accent: NSColor { current.accent }
    static var danger: NSColor { current.danger }
    static var foam: NSColor { current.foam }
    static var iris: NSColor { current.iris }
    static var rose: NSColor { current.rose }
    static var hairline: NSColor { current.hairline }
    static var divider: NSColor { current.divider }
    static var rowHover: NSColor { current.rowHover }
    static var cardBg: NSColor { current.cardBg }
    static var textPrimary: NSColor { current.textPrimary }
    static var textSecondary: NSColor { current.textSecondary }
    static var textTertiary: NSColor { current.textTertiary }
    static var hoverBg: NSColor { current.hoverBg }
    static var selectedBg: NSColor { current.selectedBg }
    static var fieldBg: NSColor { current.fieldBg }
    static var selectedText: NSColor { current.selectedText }

    /// Rounded on the LEFT corners only (right edge sits flush against the screen edge).
    static func leftRoundedPath(in bounds: NSRect, radius: CGFloat) -> NSBezierPath {
        // Extend the rect past the right edge so those corners get clipped away.
        NSBezierPath(roundedRect: NSRect(x: bounds.minX, y: bounds.minY,
                                         width: bounds.width + radius, height: bounds.height),
                     xRadius: radius, yRadius: radius)
    }

    static func glow(center: NSPoint, radius: CGFloat, color: NSColor) {
        NSGradient(starting: color, ending: color.withAlphaComponent(0))?
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }

    /// Flat base + hairline stroke (glows only when a caller passes them,
    /// e.g. the recording indicator).
    static func fillSurface(path: NSBezierPath, bounds: NSRect, glows: [(NSPoint, CGFloat, NSColor)]) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        base.setFill()
        bounds.fill()
        for (center, radius, color) in glows { glow(center: center, radius: radius, color: color) }
        NSGraphicsContext.restoreGraphicsState()
        hairline.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

func sectionLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.attributedStringValue = NSAttributedString(
        string: text.uppercased(),
        attributes: [
            .font: Theme.mono(9.5, .semibold),
            .foregroundColor: Theme.textTertiary,
            .kern: 1.6,
        ]
    )
    return label
}

func dividerLine() -> NSView {
    let line = NSView()
    line.wantsLayer = true
    line.layer?.backgroundColor = Theme.divider.cgColor
    line.translatesAutoresizingMaskIntoConstraints = false
    line.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return line
}

/// Root directory for wac's persisted data.
func wacDataDirectory() -> URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("wac", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
