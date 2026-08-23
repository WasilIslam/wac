import AppKit

/// Full-screen overlay: drag a rectangle to pick a recording region.
/// Returns the rect in CoreGraphics global coordinates (top-left origin),
/// ready for `screencapture -R`.
final class RegionSelector {
    static let shared = RegionSelector()
    private var window: NSWindow?
    private var completion: ((CGRect?) -> Void)?

    func begin(completion: @escaping (CGRect?) -> Void) {
        guard window == nil else { completion(nil); return }
        self.completion = completion

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]

        let overlay = KeyableWindow(contentRect: screen.frame, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        overlay.level = .screenSaver
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false

        let view = RegionSelectView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onDone = { [weak self] viewRect in
            guard let self else { return }
            let result: CGRect?
            if let viewRect {
                // view → global NS (bottom-left) → global CG (top-left of primary)
                let nsRect = NSRect(x: viewRect.origin.x + screen.frame.origin.x,
                                    y: viewRect.origin.y + screen.frame.origin.y,
                                    width: viewRect.width, height: viewRect.height)
                let primaryHeight = NSScreen.screens[0].frame.height
                result = CGRect(x: nsRect.origin.x,
                                y: primaryHeight - nsRect.maxY,
                                width: nsRect.width, height: nsRect.height)
            } else {
                result = nil
            }
            self.window?.orderOut(nil)
            self.window = nil
            NSCursor.arrow.set()
            self.completion?(result)
            self.completion = nil
        }
        overlay.contentView = view
        window = overlay
        overlay.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
    }
}

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class RegionSelectView: NSView {
    var onDone: ((NSRect?) -> Void)?
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: NSRect? {
        guard let a = startPoint, let b = currentPoint else { return nil }
        return NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything except the selection
        let overlay = NSBezierPath(rect: bounds)
        if let sel = selection { overlay.appendRect(sel) }
        overlay.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        overlay.fill()

        if let sel = selection {
            Theme.accent.setStroke()
            let border = NSBezierPath(rect: sel)
            border.lineWidth = 1.5
            border.stroke()

            let label = "\(Int(sel.width)) × \(Int(sel.height))  —  release to record, esc to cancel"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Theme.mono(11, .semibold), .foregroundColor: NSColor.white,
            ]
            (label as NSString).draw(at: NSPoint(x: sel.minX + 4, y: sel.maxY + 6), withAttributes: attrs)
        } else {
            let hint = "drag to select the recording region · esc to cancel"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Theme.mono(13, .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ]
            let size = (hint as NSString).size(withAttributes: attrs)
            (hint as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 80),
                                    withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        if let sel = selection, sel.width > 10, sel.height > 10 {
            onDone?(sel)
        } else {
            onDone?(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDone?(nil) } // esc
    }
}
