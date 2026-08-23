import AppKit

// MARK: - Panel

final class WidgetPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the Dock (level 20), so the tab stays visible even when the
        // Dock occupies the same screen edge.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    // Never let AppKit shove the offscreen part of the drawer back onto the screen
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: - Hover tracking base

class HoverView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    // Deliver the click even when the window isn't key yet — without this,
    // the first click only focuses the panel and the user must click twice.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}

// MARK: - Caret tab (collapsed state)

/// The grab handle: tap = open drawer, vertical drag = move along the edge.
/// Drag is manual (no performDrag), so mouseUp always arrives and taps are
/// never swallowed as drags.
final class CaretTabView: HoverView {
    var onTap: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var isRecording = false {
        didSet {
            updateIcon()
            needsDisplay = true
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            timeLabel.isHidden = !isRecording
            if isRecording {
                recordingStart = Date()
                updateElapsed()
                elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    self?.updateElapsed()
                }
            }
        }
    }

    private let chevron = NSImageView()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private var recordingStart = Date()
    private var elapsedTimer: Timer?
    private var downMouseY: CGFloat = 0
    private var downWindowY: CGFloat = 0
    private var didDrag = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        updateIcon()
        addSubview(chevron)
        timeLabel.font = Theme.mono(7.5, .bold)
        timeLabel.textColor = Theme.textPrimary
        timeLabel.alignment = .center
        timeLabel.isHidden = true
        addSubview(timeLabel)
    }

    private func updateElapsed() {
        let seconds = max(Int(Date().timeIntervalSince(recordingStart)), 0)
        if seconds < 3600 {
            timeLabel.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
        } else {
            timeLabel.stringValue = String(format: "%dh%02d", seconds / 3600, (seconds % 3600) / 60)
        }
    }

    /// While recording, the tab itself is the stop button.
    private func updateIcon() {
        let name = isRecording ? "stop.fill" : "chevron.left"
        chevron.image = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(.init(pointSize: isRecording ? 11 : 12, weight: .bold))
        chevron.contentTintColor = isRecording ? Theme.danger : Theme.textPrimary
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        chevron.frame = NSRect(x: (bounds.width - 16) / 2 - 1, y: (bounds.height - 18) / 2,
                               width: 16, height: 18)
        // Elapsed time sits ABOVE the stop icon
        timeLabel.frame = NSRect(x: 0, y: bounds.height - 22, width: bounds.width, height: 11)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.fillSurface(
            path: Theme.leftRoundedPath(in: bounds, radius: 11),
            bounds: bounds,
            glows: isRecording
                ? [(NSPoint(x: bounds.maxX, y: bounds.midY), bounds.height * 0.85,
                    Theme.danger.withAlphaComponent(0.35))]
                : []
        )
    }

    override func mouseDown(with event: NSEvent) {
        downMouseY = NSEvent.mouseLocation.y
        downWindowY = window?.frame.origin.y ?? 0
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let dy = NSEvent.mouseLocation.y - downMouseY
        if didDrag || abs(dy) > 3 {
            didDrag = true
            // Vertical-only drag: the tab lives on the edge, so x never moves.
            window.setFrameOrigin(NSPoint(x: window.frame.origin.x, y: downWindowY + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag { onDragEnd?() } else { onTap?() }
        didDrag = false
    }
}

// MARK: - Icon button (borderless, merged into the surface)

final class IconButton: HoverView {
    var onTap: (() -> Void)?
    private let highlight = NSView()
    private let icon = NSImageView()
    private let baseTint: NSColor
    private let hoverTint: NSColor

    init(symbol: String, pointSize: CGFloat = 12,
         tint: NSColor = Theme.textSecondary, hoverTint: NSColor = Theme.textPrimary) {
        self.baseTint = tint
        self.hoverTint = hoverTint
        super.init(frame: .zero)
        wantsLayer = true

        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = Theme.hoverBg.cgColor
        highlight.layer?.cornerRadius = 8
        highlight.isHidden = true
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .bold))
        icon.contentTintColor = tint
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        NSLayoutConstraint.activate([
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        onHoverChange = { [weak self] hovering in
            guard let self else { return }
            self.highlight.isHidden = !hovering
            self.icon.contentTintColor = hovering ? self.hoverTint : self.baseTint
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onTap?() }
    }
}

// MARK: - Pill tab (segmented navigation)

final class PillTabButton: HoverView {
    var onTap: (() -> Void)?
    var isSelected = false { didSet { refresh() } }
    private let label: NSTextField

    init(title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 13
        label.font = Theme.mono(10, .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
        ])
        refresh()
        onHoverChange = { [weak self] hovering in
            guard let self, !self.isSelected else { return }
            self.layer?.backgroundColor = hovering
                ? Theme.rowHover.cgColor
                : NSColor.clear.cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setTitle(_ text: String) {
        label.stringValue = text
    }

    private func refresh() {
        label.textColor = isSelected ? Theme.selectedText : Theme.textSecondary
        layer?.backgroundColor = isSelected ? Theme.selectedBg.cgColor : NSColor.clear.cgColor
        layer?.borderWidth = isSelected ? 1 : 0
        layer?.borderColor = Theme.hairline.cgColor
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onTap?() }
    }
}

// MARK: - Filled action button (e.g. Save)

final class FilledButton: HoverView {
    var onTap: (() -> Void)?
    private let label: NSTextField

    init(title: String, color: NSColor = Theme.accent) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        layer?.cornerRadius = 9
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
        ])
        onHoverChange = { [weak self] hovering in
            self?.layer?.backgroundColor = color.withAlphaComponent(hovering ? 1.0 : 0.85).cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onTap?() }
    }
}

// MARK: - Keycap chip (⌃⌥S style hint)

final class KeyCap: NSView {
    init(_ text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = Theme.hairline.cgColor

        let label = NSTextField(labelWithString: text)
        label.font = Theme.mono(8.5, .bold)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Action card (compact square button)

final class ActionCard: HoverView {
    var onTap: (() -> Void)?
    private let chip = NSView()
    private let icon = NSImageView()
    private let label: NSTextField
    private var tint: NSColor

    init(symbol: String, tint: NSColor, title: String, keycap: String? = nil) {
        self.tint = tint
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.cardBg.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = Theme.hairline.cgColor

        chip.wantsLayer = true
        chip.layer?.backgroundColor = tint.withAlphaComponent(0.13).cgColor
        chip.layer?.cornerRadius = 17
        chip.layer?.borderWidth = 1
        chip.layer?.borderColor = tint.withAlphaComponent(0.22).cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false

        icon.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.mono(10.5, .semibold)
        label.textColor = Theme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chip)
        chip.addSubview(icon)
        addSubview(label)
        setIcon(symbol)

        if let keycap {
            let cap = KeyCap(keycap)
            cap.translatesAutoresizingMaskIntoConstraints = false
            addSubview(cap)
            NSLayoutConstraint.activate([
                cap.topAnchor.constraint(equalTo: topAnchor, constant: 5),
                cap.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            ])
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 82),
            chip.centerXAnchor.constraint(equalTo: centerXAnchor),
            chip.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            chip.widthAnchor.constraint(equalToConstant: 34),
            chip.heightAnchor.constraint(equalToConstant: 34),
            icon.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        onHoverChange = { [weak self] hovering in
            guard let self else { return }
            self.layer?.backgroundColor = (hovering ? Theme.rowHover : Theme.cardBg).cgColor
            self.chip.layer?.backgroundColor = self.tint.withAlphaComponent(hovering ? 0.22 : 0.13).cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setIcon(_ symbol: String) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        icon.contentTintColor = tint
    }

    func update(symbol: String, title: String) {
        setIcon(symbol)
        label.stringValue = title
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onTap?() }
    }
}

// MARK: - Drawer surface

final class SidebarView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.fillSurface(
            path: Theme.leftRoundedPath(in: bounds, radius: 18),
            bounds: bounds,
            glows: []
        )
    }
}

// MARK: - Scroll list helpers

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

func makeScrollList() -> (NSScrollView, NSStackView) {
    let stack = FlippedStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false

    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.scrollerStyle = .overlay
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = stack

    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
    ])
    return (scroll, stack)
}
