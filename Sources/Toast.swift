import AppKit

/// Tiny transient HUD near the widget: "▸ copied ✓", "▸ screenshot saved" …
enum Toast {
    /// Set by the app delegate — returns the widget panel's frame so toasts
    /// appear next to it.
    static var anchor: (() -> NSRect)?

    private static var panel: NSPanel?
    private static var hideWorkItem: DispatchWorkItem?

    static func show(_ text: String) {
        DispatchQueue.main.async { present(text) }
    }

    private static func present(_ text: String) {
        hideWorkItem?.cancel()
        panel?.orderOut(nil)
        panel = nil

        let label = NSTextField(labelWithString: "▸ \(text)")
        label.font = Theme.mono(11, .semibold)
        label.textColor = Theme.textPrimary
        label.sizeToFit()

        let pad: CGFloat = 13
        let size = NSSize(width: label.frame.width + pad * 2, height: 32)
        let view = ToastView(frame: NSRect(origin: .zero, size: size))
        label.setFrameOrigin(NSPoint(x: pad, y: (size.height - label.frame.height) / 2))
        view.addSubview(label)

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let anchorRect = anchor?() ?? NSRect(x: screen.visibleFrame.maxX, y: screen.visibleFrame.midY,
                                             width: 0, height: 0)
        var origin = NSPoint(x: anchorRect.minX - size.width - 12,
                             y: anchorRect.midY - size.height / 2)
        origin.x = max(screen.visibleFrame.minX + 8, origin.x)
        origin.y = min(max(origin.y, screen.visibleFrame.minY + 8),
                       screen.visibleFrame.maxY - size.height - 8)

        let toast = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        toast.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toast.backgroundColor = .clear
        toast.isOpaque = false
        toast.hasShadow = true
        toast.ignoresMouseEvents = true
        toast.contentView = view
        toast.alphaValue = 0
        toast.orderFrontRegardless()
        panel = toast

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toast.animator().alphaValue = 1
        }

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                toast.animator().alphaValue = 0
            }, completionHandler: {
                if panel == toast {
                    toast.orderOut(nil)
                    panel = nil
                }
            })
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

private final class ToastView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: bounds.height / 2 - 1, yRadius: bounds.height / 2 - 1)
        Theme.base.withAlphaComponent(0.96).setFill()
        path.fill()
        Theme.accent.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
