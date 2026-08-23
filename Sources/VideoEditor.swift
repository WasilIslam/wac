import AppKit
import AVKit
import AVFoundation
import CoreImage.CIFilterBuiltins

// MARK: - Filmstrip trim bar (QuickTime/iMovie-style)

final class TrimBarView: NSView {
    var duration: Double = 1
    var startTime: Double = 0
    var endTime: Double = 1
    var playhead: Double = 0 { didSet { needsDisplay = true } }
    /// (start, end, movedStartHandle) — fired while dragging a handle
    var onRangeChange: ((Double, Double, Bool) -> Void)?
    var onSeek: ((Double) -> Void)?

    private var thumbnails: [NSImage?] = []
    private var generator: AVAssetImageGenerator?
    private enum DragTarget { case start, end, scrub }
    private var dragTarget: DragTarget?

    private let handleWidth: CGFloat = 12

    func load(asset: AVAsset, duration: Double) {
        self.duration = max(duration, 0.1)
        startTime = 0
        endTime = self.duration

        let count = max(Int(bounds.width / 52), 8)
        thumbnails = Array(repeating: nil, count: count)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 200, height: 120)
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        generator = gen
        let times = (0..<count).map {
            NSValue(time: CMTime(seconds: self.duration * (Double($0) + 0.5) / Double(count),
                                 preferredTimescale: 600))
        }
        gen.generateCGImagesAsynchronously(forTimes: times) { [weak self] requested, cgImage, _, _, _ in
            guard let self, let cgImage else { return }
            let index = min(count - 1, max(0, Int(requested.seconds / self.duration * Double(count))))
            DispatchQueue.main.async {
                self.thumbnails[index] = NSImage(cgImage: cgImage,
                                                 size: NSSize(width: cgImage.width, height: cgImage.height))
                self.needsDisplay = true
            }
        }
    }

    // MARK: Geometry

    private var stripRect: NSRect { bounds.insetBy(dx: handleWidth, dy: 4) }
    private func xFor(_ time: Double) -> CGFloat {
        stripRect.minX + stripRect.width * CGFloat(time / duration)
    }
    private func timeFor(_ x: CGFloat) -> Double {
        Double((x - stripRect.minX) / stripRect.width) * duration
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let strip = stripRect

        // Filmstrip
        NSColor.black.setFill()
        strip.fill()
        let count = max(thumbnails.count, 1)
        let slotWidth = strip.width / CGFloat(count)
        for (index, thumb) in thumbnails.enumerated() {
            guard let thumb else { continue }
            let slot = NSRect(x: strip.minX + CGFloat(index) * slotWidth, y: strip.minY,
                              width: slotWidth + 0.5, height: strip.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: slot).addClip()
            // aspect-fill inside the slot
            let scale = max(slot.width / thumb.size.width, slot.height / thumb.size.height)
            let drawSize = NSSize(width: thumb.size.width * scale, height: thumb.size.height * scale)
            thumb.draw(in: NSRect(x: slot.midX - drawSize.width / 2,
                                  y: slot.midY - drawSize.height / 2,
                                  width: drawSize.width, height: drawSize.height))
            NSGraphicsContext.restoreGraphicsState()
        }

        // Dim the trimmed-away parts
        let startX = xFor(startTime)
        let endX = xFor(endTime)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSRect(x: strip.minX, y: strip.minY, width: startX - strip.minX, height: strip.height).fill()
        NSRect(x: endX, y: strip.minY, width: strip.maxX - endX, height: strip.height).fill()

        // Selection frame
        let selection = NSRect(x: startX, y: strip.minY, width: endX - startX, height: strip.height)
        Theme.accent.setStroke()
        let frame = NSBezierPath(rect: selection.insetBy(dx: 0, dy: -1.5))
        frame.lineWidth = 3
        frame.stroke()

        // Handles: accent tabs with grip lines
        for (x, leading) in [(startX, true), (endX, false)] {
            let handle = NSRect(x: leading ? x - handleWidth : x, y: strip.minY - 4,
                                width: handleWidth, height: strip.height + 8)
            Theme.accent.setFill()
            NSBezierPath(roundedRect: handle, xRadius: 4, yRadius: 4).fill()
            NSColor.black.withAlphaComponent(0.55).setStroke()
            let grip = NSBezierPath()
            grip.move(to: NSPoint(x: handle.midX, y: handle.midY - 7))
            grip.line(to: NSPoint(x: handle.midX, y: handle.midY + 7))
            grip.lineWidth = 1.6
            grip.stroke()
        }

        // Playhead
        if playhead >= startTime, playhead <= endTime {
            let px = xFor(playhead)
            NSColor.white.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: px, y: strip.minY - 3))
            line.line(to: NSPoint(x: px, y: strip.maxY + 3))
            line.lineWidth = 2
            line.stroke()
        }
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let startX = xFor(startTime)
        let endX = xFor(endTime)
        if abs(point.x - startX) <= handleWidth {
            dragTarget = .start
        } else if abs(point.x - endX) <= handleWidth {
            dragTarget = .end
        } else {
            dragTarget = .scrub
            scrub(to: point.x)
        }
        mouseDragged(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let time = min(max(timeFor(point.x), 0), duration)
        switch dragTarget {
        case .start:
            startTime = min(time, endTime - 0.2)
            onRangeChange?(startTime, endTime, true)
        case .end:
            endTime = max(time, startTime + 0.2)
            onRangeChange?(startTime, endTime, false)
        case .scrub:
            scrub(to: point.x)
        case nil:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragTarget = nil
    }

    private func scrub(to x: CGFloat) {
        let time = min(max(timeFor(x), startTime), endTime)
        playhead = time
        onSeek?(time)
    }
}

// MARK: - Editor window

/// Post-recording editor: filmstrip trim + pixelate regions, then re-export.
final class VideoEditor: NSObject {
    static let shared = VideoEditor()
    var onSaved: (() -> Void)?

    private var window: NSWindow?
    private var player: AVPlayer!
    private var playerView: AVPlayerView!
    private var blurOverlay: BlurSelectView!
    private var trimBar: TrimBarView!
    private var timeObserver: Any?
    private var asset: AVAsset!
    private var fileURL: URL!
    private var duration: Double = 0
    private var videoSize = CGSize(width: 1280, height: 800)
    private var rangeLabel: NSTextField!
    private var blurButton: NSButton!
    private var exporting = false

    func open(fileURL url: URL) {
        closeWindow()
        fileURL = url
        let urlAsset = AVURLAsset(url: url)
        asset = urlAsset
        duration = max(CMTimeGetSeconds(urlAsset.duration), 0.1)
        if let track = urlAsset.tracks(withMediaType: .video).first {
            let rect = CGRect(origin: .zero, size: track.naturalSize)
                .applying(track.preferredTransform)
            videoSize = CGSize(width: max(abs(rect.width), 1), height: max(abs(rect.height), 1))
        } else {
            videoSize = CGSize(width: 1280, height: 800)
        }
        buildWindow()
    }

    private func closeWindow() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        window?.close()
        window = nil
    }

    private func buildWindow() {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let controlsHeight: CGFloat = 118
        let maxArea = NSSize(width: visible.width * 0.75,
                             height: visible.height * 0.75 - controlsHeight)
        let scale = min(maxArea.width / videoSize.width, maxArea.height / videoSize.height)
        let videoArea = NSSize(width: max(floor(videoSize.width * scale), 720),
                               height: floor(videoSize.height * scale))

        player = AVPlayer(url: fileURL)
        playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .minimal
        playerView.frame = NSRect(x: 0, y: controlsHeight,
                                  width: videoArea.width, height: videoArea.height)

        blurOverlay = BlurSelectView(frame: playerView.frame)
        blurOverlay.active = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: videoArea.width,
                                           height: videoArea.height + controlsHeight))
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.base.cgColor
        content.addSubview(playerView)
        content.addSubview(blurOverlay)
        content.addSubview(buildControls(width: videoArea.width, height: controlsHeight))

        let editorWindow = NSWindow(contentRect: NSRect(origin: .zero, size: content.frame.size),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
        editorWindow.title = fileURL.lastPathComponent
        editorWindow.appearance = NSAppearance(named: .darkAqua)
        editorWindow.backgroundColor = Theme.base
        editorWindow.level = .floating
        editorWindow.isReleasedWhenClosed = false
        editorWindow.contentView = content
        editorWindow.center()
        window = editorWindow

        // Playhead follows playback; preview pauses at the trim end
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            guard let self, let trimBar = self.trimBar else { return }
            let seconds = CMTimeGetSeconds(time)
            trimBar.playhead = seconds
            if seconds >= trimBar.endTime, self.player.rate > 0 {
                self.player.pause()
                self.player.seek(to: CMTime(seconds: trimBar.startTime, preferredTimescale: 600),
                                 toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }

        trimBar.load(asset: asset, duration: duration)

        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)),
                                               name: NSWindow.willCloseNotification,
                                               object: editorWindow)
        NSApp.activate(ignoringOtherApps: true)
        editorWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func windowClosed(_ note: Notification) {
        guard let closed = note.object as? NSWindow, closed == window else { return }
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        window = nil
    }

    private func buildControls(width: CGFloat, height: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        trimBar = TrimBarView(frame: NSRect(x: 14, y: height - 62, width: width - 28, height: 54))
        trimBar.autoresizingMask = [.width]
        trimBar.onRangeChange = { [weak self] start, end, movedStart in
            guard let self else { return }
            self.player.pause()
            let seekTo = movedStart ? start : end
            self.player.seek(to: CMTime(seconds: seekTo, preferredTimescale: 600),
                             toleranceBefore: .zero, toleranceAfter: .zero)
            self.rangeLabel.stringValue = self.rangeText()
        }
        trimBar.onSeek = { [weak self] time in
            self?.player.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: .zero)
        }

        rangeLabel = NSTextField(labelWithString: "")
        rangeLabel.font = Theme.mono(10, .semibold)
        rangeLabel.textColor = Theme.textPrimary

        blurButton = NSButton(title: "Blur region", target: self, action: #selector(toggleBlurMode))
        blurButton.bezelStyle = .rounded
        blurButton.setButtonType(.pushOnPushOff)

        let clearBlurs = NSButton(title: "Clear blurs", target: self, action: #selector(clearBlurTapped))
        clearBlurs.bezelStyle = .rounded

        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"

        let hint = NSTextField(labelWithString: "drag the gold handles to trim · click the strip to scrub")
        hint.font = Theme.mono(9)
        hint.textColor = Theme.textTertiary
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let buttonsRow = NSStackView(views: [rangeLabel, hint, blurButton, clearBlurs, save])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 10
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(trimBar)
        bar.addSubview(buttonsRow)
        NSLayoutConstraint.activate([
            buttonsRow.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            buttonsRow.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            buttonsRow.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -12),
        ])
        rangeLabel.stringValue = rangeText()
        return bar
    }

    // MARK: Controls

    private func rangeText() -> String {
        func fmt(_ t: Double) -> String {
            String(format: "%02d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
        }
        let start = trimBar?.startTime ?? 0
        let end = trimBar?.endTime ?? duration
        return "\(fmt(start)) → \(fmt(end))"
    }

    @objc private func toggleBlurMode() {
        blurOverlay.active = blurButton.state == .on
        if blurOverlay.active {
            player.pause()
            Toast.show("drag over the video to add a blur region")
        }
    }

    @objc private func clearBlurTapped() {
        blurOverlay.rects.removeAll()
        blurOverlay.needsDisplay = true
    }

    // MARK: Export

    @objc private func saveTapped() {
        guard !exporting else { return }
        exporting = true
        Toast.show("exporting video…")

        guard let export = AVAssetExportSession(asset: asset,
                                                presetName: AVAssetExportPresetHighestQuality) else {
            exporting = false
            Toast.show("export failed to start")
            return
        }
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: trimBar.startTime, preferredTimescale: 600),
            end: CMTime(seconds: trimBar.endTime, preferredTimescale: 600))

        let videoRects = blurOverlay.rects.compactMap { viewRectToVideoRect($0) }
        if !videoRects.isEmpty {
            let composition = AVMutableVideoComposition(asset: asset) { request in
                var result = request.sourceImage
                for rect in videoRects {
                    let filter = CIFilter.pixellate()
                    filter.inputImage = request.sourceImage.clampedToExtent()
                    filter.scale = Float(max(request.sourceImage.extent.width / 60, 14))
                    filter.center = CGPoint(x: rect.midX, y: rect.midY)
                    if let pixelated = filter.outputImage?.cropped(to: rect) {
                        result = pixelated.composited(over: result)
                    }
                }
                request.finish(with: result, context: nil)
            }
            export.videoComposition = composition
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        export.outputURL = tempURL
        export.outputFileType = .mov
        export.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.exporting = false
                if export.status == .completed {
                    self.player.pause()
                    self.player.replaceCurrentItem(with: nil) // release the file
                    _ = try? FileManager.default.replaceItemAt(self.fileURL, withItemAt: tempURL)
                    Toast.show("video saved ✓")
                    self.onSaved?()
                    self.window?.close()
                } else {
                    Toast.show("export failed: \(export.error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }

    /// Overlay-view rect → video pixel rect (both bottom-left origin).
    private func viewRectToVideoRect(_ rect: NSRect) -> CGRect? {
        let videoBounds = playerView.videoBounds
        guard videoBounds.width > 1 else { return nil }
        let clipped = rect.intersection(videoBounds)
        guard !clipped.isEmpty else { return nil }
        let scale = videoSize.width / videoBounds.width
        return CGRect(x: (clipped.minX - videoBounds.minX) * scale,
                      y: (clipped.minY - videoBounds.minY) * scale,
                      width: clipped.width * scale,
                      height: clipped.height * scale)
    }
}

// MARK: - Blur region overlay

final class BlurSelectView: NSView {
    var active = false { didSet { needsDisplay = true } }
    var rects: [NSRect] = []
    private var startPoint: NSPoint?
    private var current: NSRect?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Pass clicks through to the player when not in blur mode
    override func hitTest(_ point: NSPoint) -> NSView? { active ? super.hitTest(point) : nil }

    override func draw(_ dirtyRect: NSRect) {
        for rect in rects { drawRegion(rect) }
        if let current { drawRegion(current) }
        if active {
            Theme.danger.withAlphaComponent(0.6).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            border.setLineDash([6, 4], count: 2, phase: 0)
            border.lineWidth = 2
            border.stroke()
        }
    }

    private func drawRegion(_ rect: NSRect) {
        Theme.danger.withAlphaComponent(0.18).setFill()
        rect.fill()
        Theme.danger.setStroke()
        let path = NSBezierPath(rect: rect)
        path.setLineDash([5, 3], count: 2, phase: 0)
        path.lineWidth = 1.5
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        current = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                         width: abs(start.x - point.x), height: abs(start.y - point.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let current, current.width > 6, current.height > 6 {
            rects.append(current)
        }
        current = nil
        startPoint = nil
        needsDisplay = true
    }
}
