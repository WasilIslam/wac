// Renders wac's app icon (dark dotted tile + glow + caret) into an .iconset.
// Usage: swift gen-icon.swift <output.iconset>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "wac.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS-style margins: tile fills ~80% of the canvas
    let tile = NSRect(x: s * 0.10, y: s * 0.10, width: s * 0.80, height: s * 0.80)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    path.addClip()

    // Base — Rosé Pine ink
    NSColor(red: 0.098, green: 0.090, blue: 0.141, alpha: 1).setFill()
    tile.fill()

    // Scanlines
    let lineGap = max(tile.height / 64, 1)
    NSColor(red: 0.88, green: 0.87, blue: 0.96, alpha: 0.04).setFill()
    var y = tile.minY
    while y < tile.maxY {
        NSRect(x: tile.minX, y: y, width: tile.width, height: max(lineGap / 3, 0.5)).fill()
        y += lineGap
    }

    // Glows
    func glow(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: NSColor) {
        NSGradient(starting: color, ending: color.withAlphaComponent(0))?
            .draw(fromCenter: NSPoint(x: cx, y: cy), radius: 0,
                  toCenter: NSPoint(x: cx, y: cy), radius: r, options: [])
    }
    glow(tile.maxX - tile.width * 0.15, tile.maxY - tile.height * 0.12, tile.width * 0.85,
         NSColor(red: 0.965, green: 0.757, blue: 0.467, alpha: 0.30))
    glow(tile.minX + tile.width * 0.10, tile.minY + tile.height * 0.15, tile.width * 0.7,
         NSColor(red: 0.769, green: 0.655, blue: 0.906, alpha: 0.20))

    // Hairline border (inside the clip)
    NSColor.white.withAlphaComponent(0.16).setStroke()
    let border = NSBezierPath(roundedRect: tile.insetBy(dx: s * 0.004, dy: s * 0.004),
                              xRadius: tile.width * 0.22, yRadius: tile.width * 0.22)
    border.lineWidth = max(s * 0.008, 1)
    border.stroke()

    // Caret "‹" — wac's pull-handle identity
    let cx = tile.midX + tile.width * 0.03
    let cy = tile.midY
    let armX = tile.width * 0.11
    let armY = tile.height * 0.19
    let caret = NSBezierPath()
    caret.move(to: NSPoint(x: cx + armX, y: cy + armY))
    caret.line(to: NSPoint(x: cx - armX, y: cy))
    caret.line(to: NSPoint(x: cx + armX, y: cy - armY))
    caret.lineWidth = tile.width * 0.085
    caret.lineCapStyle = .round
    caret.lineJoinStyle = .round
    NSColor(red: 0.878, green: 0.871, blue: 0.957, alpha: 1).setStroke()
    caret.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let entries: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (size, name) in entries {
    let rep = render(size)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: outDir.appendingPathComponent(name))
}
print("iconset written to \(outDir.path)")
