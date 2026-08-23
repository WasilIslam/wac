import AppKit
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

// MARK: - Annotation model

enum AnnotTool: CaseIterable {
    case pen, highlight, arrow, line, rect, ellipse, blur, text

    var symbol: String {
        switch self {
        case .pen: return "scribble"
        case .highlight: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "oval"
        case .blur: return "checkerboard.rectangle"
        case .text: return "textformat"
        }
    }
}

struct AnnotShape {
    var tool: AnnotTool
    var color: NSColor
    var width: CGFloat
    var points: [NSPoint] = []
    var start: NSPoint = .zero
    var end: NSPoint = .zero
    var text: String = ""
}

private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
    NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
}

func drawAnnotShape(_ s: AnnotShape, pixelated: NSImage? = nil, canvasBounds: NSRect = .zero) {
    switch s.tool {
    case .blur:
        // Draw the pre-pixelated copy of the image, clipped to the region
        guard let pixelated else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rectBetween(s.start, s.end)).addClip()
        pixelated.draw(in: canvasBounds)
        NSGraphicsContext.restoreGraphicsState()
    case .pen, .highlight:
        guard s.points.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: s.points[0])
        for p in s.points.dropFirst() { path.line(to: p) }
        path.lineWidth = s.tool == .highlight ? s.width * 3.5 : s.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        (s.tool == .highlight ? s.color.withAlphaComponent(0.35) : s.color).setStroke()
        path.stroke()
    case .arrow:
        s.color.setStroke()
        let line = NSBezierPath()
        line.move(to: s.start)
        line.line(to: s.end)
        line.lineWidth = s.width
        line.lineCapStyle = .round
        line.stroke()
        let angle = atan2(s.end.y - s.start.y, s.end.x - s.start.x)
        let len = max(9, s.width * 3.2)
        let head = NSBezierPath()
        head.move(to: NSPoint(x: s.end.x - len * cos(angle - 0.45), y: s.end.y - len * sin(angle - 0.45)))
        head.line(to: s.end)
        head.line(to: NSPoint(x: s.end.x - len * cos(angle + 0.45), y: s.end.y - len * sin(angle + 0.45)))
        head.lineWidth = s.width
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.stroke()
    case .line:
        s.color.setStroke()
        let path = NSBezierPath()
        path.move(to: s.start)
        path.line(to: s.end)
        path.lineWidth = s.width
        path.lineCapStyle = .round
        path.stroke()
    case .rect:
        s.color.setStroke()
        let path = NSBezierPath(roundedRect: rectBetween(s.start, s.end), xRadius: 2, yRadius: 2)
        path.lineWidth = s.width
        path.stroke()
    case .ellipse:
        s.color.setStroke()
        let path = NSBezierPath(ovalIn: rectBetween(s.start, s.end))
        path.lineWidth = s.width
        path.stroke()
    case .text:
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10 + s.width * 3.5),
            .foregroundColor: s.color,
        ]
        (s.text as NSString).draw(at: s.start, withAttributes: attrs)
    }
}

// MARK: - Canvas

final class AnnotCanvas: NSView {
    var image: NSImage!
    var shapes: [AnnotShape] = [] { didSet { needsDisplay = true } }
    var redoStack: [AnnotShape] = []
    var current: AnnotShape?
    var tool: AnnotTool = .arrow
    var color: NSColor = .systemRed
    var strokeWidth: CGFloat = 4
    var onTextRequest: ((NSPoint) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Fully pixelated copy of the image, cached — blur regions clip into it.
    private var _pixelated: NSImage?
    var pixelatedImage: NSImage? {
        if let _pixelated { return _pixelated }
        guard let tiff = image?.tiffRepresentation, let ciImage = CIImage(data: tiff) else { return nil }
        let filter = CIFilter.pixellate()
        filter.inputImage = ciImage.clampedToExtent()
        filter.scale = Float(max(ciImage.extent.width / 70, 10))
        filter.center = .zero
        guard let output = filter.outputImage?.cropped(to: ciImage.extent) else { return nil }
        let result = NSImage(size: image.size)
        result.addRepresentation(NSCIImageRep(ciImage: output))
        _pixelated = result
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds)
        for shape in shapes { drawAnnotShape(shape, pixelated: pixelatedImage, canvasBounds: bounds) }
        if let current { drawAnnotShape(current, pixelated: pixelatedImage, canvasBounds: bounds) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if tool == .text {
            onTextRequest?(p)
            return
        }
        current = AnnotShape(tool: tool, color: color, width: strokeWidth,
                             points: [p], start: p, end: p)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        current?.points.append(p)
        current?.end = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let current {
            shapes.append(current)
            redoStack.removeAll()
        }
        current = nil
    }

    func undo() {
        if let s = shapes.popLast() { redoStack.append(s) }
    }

    func redo() {
        if let s = redoStack.popLast() { shapes.append(s) }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            event.modifierFlags.contains(.shift) ? redo() : undo()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Toolbar controls

final class SwatchButton: HoverView {
    var onTap: (() -> Void)?
    let swatchColor: NSColor
    var isSelected = false { didSet { needsDisplay = true } }

    init(color: NSColor) {
        swatchColor = color
        super.init(frame: .zero)
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 5, dy: 5)
        swatchColor.setFill()
        NSBezierPath(ovalIn: inset).fill()
        if isSelected {
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onTap?() }
    }
}

// MARK: - Annotator window

final class Annotator: NSObject, NSTextFieldDelegate {
    static let shared = Annotator()
    var onSaved: (() -> Void)?

    private var window: NSWindow?
    private var canvas: AnnotCanvas!
    private var fileURL: URL!
    private var pixelSize = NSSize.zero
    private var toolSegment: NSSegmentedControl!
    private var widthSegment: NSSegmentedControl!
    private var swatches: [SwatchButton] = []
    private var colorWell: NSColorWell!
    private var activeTextField: NSTextField?
    private var pendingTextPoint: NSPoint?

    private let colors: [NSColor] = [
        NSColor(red: 1.00, green: 0.30, blue: 0.30, alpha: 1),
        NSColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1),
        NSColor(red: 0.30, green: 0.90, blue: 0.50, alpha: 1),
        NSColor(red: 0.35, green: 0.60, blue: 1.00, alpha: 1),
        .white,
    ]
    private let widths: [CGFloat] = [2, 4, 8]

    /// Open an existing image for annotation.
    func open(fileURL url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let px: NSSize
        if let rep = image.representations.first {
            px = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            px = image.size
        }
        present(image: image, pixelSize: px, fileURL: url)
    }

    /// Blank white canvas — free drawing, saved to ~/Pictures/wac/drawings.
    func openBlank() {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = NSSize(width: floor(visible.width * 0.8),
                          height: floor(visible.height * 0.8) - 46)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/wac/drawings", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let file = dir.appendingPathComponent("wac \(formatter.string(from: Date())).png")

        present(image: image,
                pixelSize: NSSize(width: size.width * 2, height: size.height * 2), // retina export
                fileURL: file)
    }

    private func present(image: NSImage, pixelSize px: NSSize, fileURL url: URL) {
        window?.close()
        fileURL = url
        pixelSize = px

        // Size the editor to ~80% of the screen; small captures scale UP so
        // there's room to work (annotations export at original pixels).
        let toolbarHeight: CGFloat = 46
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let maxSize = NSSize(width: visible.width * 0.8,
                             height: visible.height * 0.8 - toolbarHeight)
        let scale = min(2.5, maxSize.width / image.size.width, maxSize.height / image.size.height)
        let canvasSize = NSSize(width: floor(image.size.width * scale),
                                height: floor(image.size.height * scale))

        canvas = AnnotCanvas(frame: NSRect(origin: .zero, size: canvasSize))
        canvas.image = image
        canvas.onTextRequest = { [weak self] point in self?.beginTextEntry(at: point) }

        // Keep the window wide enough for the whole toolbar
        let contentWidth = max(canvasSize.width, 760)
        let content = NSView(frame: NSRect(x: 0, y: 0,
                                           width: contentWidth,
                                           height: canvasSize.height + toolbarHeight))
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.base.cgColor

        canvas.frame = NSRect(x: floor((contentWidth - canvasSize.width) / 2), y: 0,
                              width: canvasSize.width, height: canvasSize.height)
        content.addSubview(canvas)
        content.addSubview(buildToolbar(width: contentWidth, y: canvasSize.height,
                                        height: toolbarHeight))

        let w = NSWindow(contentRect: NSRect(origin: .zero, size: content.frame.size),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = url.lastPathComponent
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = Theme.base
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.contentView = content
        w.center()
        window = w

        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)),
                                               name: NSWindow.willCloseNotification, object: w)

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(canvas)
        toolSegment.selectedSegment = 2 // arrow
        canvas.tool = .arrow
        widthSegment.selectedSegment = 1
        canvas.strokeWidth = widths[1]
        selectColor(0)
    }

    @objc private func windowClosed(_ note: Notification) {
        if let w = note.object as? NSWindow, w == window { window = nil }
    }

    // MARK: Toolbar

    private func buildToolbar(width: CGFloat, y: CGFloat, height: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: y, width: width, height: height))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.base.cgColor

        let divider = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.divider.cgColor
        divider.autoresizingMask = [.width]
        bar.addSubview(divider)

        // Native controls: standard segmented controls and buttons, so
        // behavior/contrast come from AppKit instead of custom hover effects.
        func symbolImage(_ name: String) -> NSImage {
            NSImage(systemSymbolName: name, accessibilityDescription: name)!
                .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))!
        }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        toolSegment = NSSegmentedControl(
            images: AnnotTool.allCases.map { symbolImage($0.symbol) },
            trackingMode: .selectOne, target: self, action: #selector(toolChanged))
        stack.addArrangedSubview(toolSegment)

        swatches.removeAll() // toolbar is rebuilt on every open
        let swatchRow = NSStackView()
        swatchRow.orientation = .horizontal
        swatchRow.spacing = 1
        for (index, color) in colors.enumerated() {
            let swatch = SwatchButton(color: color)
            swatch.onTap = { [weak self] in self?.selectColor(index) }
            swatches.append(swatch)
            swatchRow.addArrangedSubview(swatch)
        }
        // Native color well → any color, not just the swatches
        if #available(macOS 13.0, *) {
            colorWell = NSColorWell(style: .minimal)
        } else {
            colorWell = NSColorWell()
        }
        colorWell.color = colors[0]
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged(_:))
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 34).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        swatchRow.addArrangedSubview(colorWell)
        stack.addArrangedSubview(swatchRow)

        widthSegment = NSSegmentedControl(
            images: ["minus", "equal", "line.3.horizontal"].map(symbolImage),
            trackingMode: .selectOne, target: self, action: #selector(widthChanged))
        stack.addArrangedSubview(widthSegment)

        let undo = NSButton(image: symbolImage("arrow.uturn.backward"),
                            target: self, action: #selector(undoTapped))
        undo.bezelStyle = .texturedRounded
        let redo = NSButton(image: symbolImage("arrow.uturn.forward"),
                            target: self, action: #selector(redoTapped))
        redo.bezelStyle = .texturedRounded
        let undoRow = NSStackView(views: [undo, redo])
        undoRow.orientation = .horizontal
        undoRow.spacing = 2
        stack.addArrangedSubview(undoRow)

        let copy = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
        copy.bezelStyle = .rounded
        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r" // default button → accent-colored, high contrast

        bar.addSubview(stack)
        bar.addSubview(copy)
        bar.addSubview(save)
        copy.translatesAutoresizingMaskIntoConstraints = false
        save.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            save.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            save.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            copy.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -6),
            copy.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    @objc private func toolChanged() {
        canvas.tool = AnnotTool.allCases[toolSegment.selectedSegment]
        window?.makeFirstResponder(canvas)
    }

    @objc private func widthChanged() {
        canvas.strokeWidth = widths[widthSegment.selectedSegment]
        window?.makeFirstResponder(canvas)
    }

    @objc private func undoTapped() { canvas.undo() }
    @objc private func redoTapped() { canvas.redo() }
    @objc private func copyTapped() { copyToClipboard() }
    @objc private func saveTapped() { save() }

    private func selectColor(_ index: Int) {
        canvas.color = colors[index]
        colorWell.color = colors[index]
        for (i, swatch) in swatches.enumerated() { swatch.isSelected = i == index }
    }

    @objc private func colorWellChanged(_ sender: NSColorWell) {
        canvas.color = sender.color
        for swatch in swatches { swatch.isSelected = false }
    }

    // MARK: Text entry

    private func beginTextEntry(at point: NSPoint) {
        commitTextEntry()
        pendingTextPoint = point
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 4,
                                              width: max(120, canvas.bounds.width - point.x - 8),
                                              height: 24))
        field.font = .boldSystemFont(ofSize: 10 + canvas.strokeWidth * 3.5)
        field.textColor = canvas.color
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.4)
        field.focusRingType = .none
        field.placeholderString = "type…"
        field.delegate = self
        field.target = self
        field.action = #selector(textEntered)
        canvas.addSubview(field)
        activeTextField = field
        window?.makeFirstResponder(field)
    }

    @objc private func textEntered() { commitTextEntry() }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Media rename cells have their own delegate; this only sees ours
        commitTextEntry()
    }

    private func commitTextEntry() {
        guard let field = activeTextField else { return }
        activeTextField = nil
        let text = field.stringValue
        let point = pendingTextPoint ?? .zero
        field.removeFromSuperview()
        pendingTextPoint = nil
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var shape = AnnotShape(tool: .text, color: canvas.color, width: canvas.strokeWidth)
        shape.start = point
        shape.text = text
        canvas.shapes.append(shape)
        canvas.redoStack.removeAll()
    }

    // MARK: Output

    /// Render image + shapes at the ORIGINAL pixel resolution.
    private func renderAnnotated() -> Data? {
        commitTextEntry()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform()
        transform.scaleX(by: pixelSize.width / canvas.bounds.width,
                         yBy: pixelSize.height / canvas.bounds.height)
        transform.concat()
        canvas.image.draw(in: canvas.bounds)
        for shape in canvas.shapes {
            drawAnnotShape(shape, pixelated: canvas.pixelatedImage, canvasBounds: canvas.bounds)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private func save() {
        guard let data = renderAnnotated() else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL)
        onSaved?()
        window?.close()
    }

    private func copyToClipboard() {
        guard let data = renderAnnotated(), let image = NSImage(data: data) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        Toast.show("copied to clipboard ✓")
    }
}
