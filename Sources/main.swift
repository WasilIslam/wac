import AppKit
import CoreGraphics

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: WidgetPanel!
    private var collapsedTab: CaretTabView!
    private var drawerController: DrawerController!
    private let recorder = ScreenRecorder()
    private let audioRecorder = AudioRecorder()
    private var anyRecording: Bool { recorder.isRecording || audioRecorder.isRecording }
    private var isExpanded = false
    private var isAnimating = false
    private var eventMonitors: [Any] = []

    private let tabSize = NSSize(width: 26, height: 92)
    private let drawerWidth: CGFloat = 320
    private let idleAlpha: CGFloat = 0.55
    private let tabYDefaultsKey = "wac.tab.y"

    private var screen: NSScreen { panel.screen ?? NSScreen.main ?? NSScreen.screens[0] }
    /// True right edge of the display (screen.frame, not visibleFrame, so a
    /// right-side Dock doesn't push the widget inward).
    private var edgeX: CGFloat { screen.frame.maxX }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installSignalHandlers()
        // Permissions are requested only when the user first uses a feature
        // that needs them — never speculatively at launch.

        collapsedTab = CaretTabView(frame: NSRect(origin: .zero, size: tabSize))
        collapsedTab.autoresizingMask = [.width, .height]
        collapsedTab.onTap = { [weak self] in
            guard let self else { return }
            // While recording (screen or audio), the tab IS the stop button.
            if self.recorder.isRecording {
                self.recorder.stop()
            } else if self.audioRecorder.isRecording {
                self.audioRecorder.stop()
            } else {
                self.expand()
            }
        }
        collapsedTab.onDragEnd = { [weak self] in self?.snapToEdge(animate: true) }
        collapsedTab.onHoverChange = { [weak self] hovering in
            guard let self, !self.isExpanded else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                self.panel.animator().alphaValue =
                    (hovering || self.anyRecording) ? 1.0 : self.idleAlpha
            }
        }

        makeDrawerController()
        Annotator.shared.onSaved = { [weak self] in
            self?.drawerController.refreshMedia()
            Toast.show("annotation saved ✓")
        }
        VideoEditor.shared.onSaved = { [weak self] in self?.drawerController.refreshMedia() }
        // Trim/blur editor opens on every finished recording
        recorder.onFinished = { url in VideoEditor.shared.open(fileURL: url) }
        Toast.anchor = { [weak self] in self?.panel.frame ?? .zero }

        // Global hotkeys (no permissions needed): ⌃⌥W / ⌃⌥S / ⌃⌥R
        HotKeys.shared.onToggleDrawer = { [weak self] in
            guard let self else { return }
            self.isExpanded ? self.collapse() : self.expand()
        }
        HotKeys.shared.onScreenshot = { [weak self] in
            guard let self else { return }
            if self.isExpanded { self.collapse() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.runScreenshot() }
        }
        HotKeys.shared.onRecord = { [weak self] in self?.toggleScreenRecording() }
        HotKeys.shared.register()

        recorder.onStateChange = { [weak self] recording in
            guard let self else { return }
            self.collapsedTab.isRecording = self.anyRecording
            self.drawerController.setRecording(recording)
            Toast.show(recording ? "recording ● tab or ⌃⌥R stops" : "recording saved ✓")
            if !recording {
                CameraOverlay.shared.hide()
                self.drawerController.refreshMedia() // new file landed
            }
            if !self.isExpanded {
                self.panel.alphaValue = self.anyRecording ? 1.0 : self.idleAlpha
            }
        }
        audioRecorder.onStateChange = { [weak self] recording in
            guard let self else { return }
            self.collapsedTab.isRecording = self.anyRecording
            self.drawerController.setAudioRecording(recording)
            Toast.show(recording ? "audio recording ● tab stops" : "audio saved ✓")
            if !recording { self.drawerController.refreshMedia() }
            if !self.isExpanded {
                self.panel.alphaValue = self.anyRecording ? 1.0 : self.idleAlpha
            }
        }

        let startFrame = NSRect(origin: restoredTabOrigin(), size: tabSize)
        panel = WidgetPanel(contentRect: startFrame)
        panel.contentView = collapsedTab
        panel.alphaValue = idleAlpha
        panel.orderFrontRegardless()

        ClipboardStore.shared.startMonitoring()

        // Collapse on outside click or Esc
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.collapse()
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, self.isExpanded, // Esc
               !(self.panel.firstResponder is NSTextView) {
                self.collapse()
                return nil
            }
            return event
        } as Any)

        // Auto-detect layout changes: Dock moved/resized/hidden, resolution
        // changed, displays plugged/unplugged — all fire this notification.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenLayoutChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        drawerController.saveDraftIfEditing()
        audioRecorder.stop()
        CameraOverlay.shared.hide()
        recorder.stopAndWait() // finalize any in-flight recording
    }

    /// SIGTERM (pkill, logout, rebuild scripts) doesn't run
    /// applicationWillTerminate — handle it so a kill mid-recording
    /// never orphans screencapture and loses the file.
    func installSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.audioRecorder.stop()
            self?.recorder.stopAndWait()
            NSApp.terminate(nil)
        }
        source.resume()
        sigtermSource = source
    }
    private var sigtermSource: DispatchSourceSignal?

    /// (Re)builds the drawer — also how theme switches take effect, since
    /// views bake colors in at construction time.
    private func makeDrawerController() {
        drawerController = DrawerController(width: drawerWidth)
        drawerController.onCollapse = { [weak self] in self?.collapse() }
        drawerController.onScreenshot = { [weak self] in self?.runScreenshot() }
        drawerController.onToggleRecord = { [weak self] in self?.toggleScreenRecording() }
        drawerController.onToggleAudio = { [weak self] in self?.audioRecorder.toggle() }
        drawerController.onDraw = { Annotator.shared.openBlank() }
        drawerController.onPickColor = { [weak self] in self?.pickColor() }
        drawerController.onThemeChange = { [weak self] in self?.applyTheme() }
        drawerController.setRecording(recorder.isRecording)
        drawerController.setAudioRecording(audioRecorder.isRecording)
    }

    private func applyTheme() {
        makeDrawerController()
        if isExpanded {
            drawerController.view.frame = NSRect(origin: .zero, size: panel.frame.size)
            panel.contentView = drawerController.view
        }
        collapsedTab.needsDisplay = true // tab draws Theme colors live
    }

    @objc private func screenLayoutChanged() {
        // Re-anchor after the system settles its own geometry updates.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.isAnimating else { return }
            if self.isExpanded {
                let v = self.screen.visibleFrame
                self.panel.setFrame(
                    NSRect(x: self.edgeX - self.drawerWidth, y: v.minY,
                           width: self.drawerWidth, height: v.height),
                    display: true)
            } else {
                self.snapToEdge(animate: false)
            }
        }
    }

    // MARK: Slide open / closed

    private func expand() {
        guard !isExpanded, !isAnimating else { return }
        isExpanded = true
        isAnimating = true

        let v = screen.visibleFrame
        saveTabY(panel.frame.origin.y)

        // Park the drawer fully offscreen past the right edge, then slide in.
        let hiddenFrame = NSRect(x: edgeX, y: v.minY, width: drawerWidth, height: v.height)
        let openFrame = NSRect(x: edgeX - drawerWidth, y: v.minY, width: drawerWidth, height: v.height)

        drawerController.view.frame = NSRect(origin: .zero, size: hiddenFrame.size)
        drawerController.drawerWillExpand()
        panel.alphaValue = 1.0
        panel.contentView = drawerController.view
        panel.setFrame(hiddenFrame, display: true)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(openFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
            self?.panel.makeKey()
        })
        unstickAnimationFlag(after: 0.28)
    }

    private func collapse() {
        guard isExpanded, !isAnimating else { return }
        isAnimating = true
        drawerController.drawerWillCollapse()

        let v = screen.visibleFrame
        let hiddenFrame = NSRect(x: edgeX, y: v.minY, width: drawerWidth, height: panel.frame.height)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(hiddenFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.isExpanded = false
            self.isAnimating = false
            // Swap back to the tab-only window at its remembered spot
            self.panel.contentView = self.collapsedTab
            self.panel.setFrame(NSRect(origin: self.restoredTabOrigin(), size: self.tabSize), display: true)
            self.panel.alphaValue = self.recorder.isRecording ? 1.0 : self.idleAlpha
        })
        unstickAnimationFlag(after: 0.24)
    }

    /// Safety net: if an animation completion handler ever fails to fire,
    /// don't leave clicks permanently dead.
    private func unstickAnimationFlag(after duration: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.4) { [weak self] in
            self?.isAnimating = false
        }
    }

    private func snapToEdge(animate: Bool) {
        let v = screen.visibleFrame
        var y = panel.frame.origin.y
        y = min(max(y, v.minY + 8), v.maxY - tabSize.height - 8)
        let target = NSRect(x: edgeX - tabSize.width, y: y, width: tabSize.width, height: tabSize.height)
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
        saveTabY(y)
    }

    // MARK: Recording

    private func toggleScreenRecording() {
        if recorder.isRecording { recorder.stop(); return }
        let defaults = UserDefaults.standard
        var options = RecordingOptions(
            mic: defaults.object(forKey: "wac.rec.mic") as? Bool ?? true,
            clicks: defaults.bool(forKey: "wac.rec.clicks"),
            region: nil
        )

        // Strictly sequential: camera permission + bubble first, THEN
        // region selection, THEN recording — no prompts mid-recording.
        let proceed: () -> Void = { [weak self] in
            guard let self else { return }
            if defaults.bool(forKey: "wac.rec.region") {
                RegionSelector.shared.begin { [weak self] rect in
                    guard let rect else { // cancelled
                        CameraOverlay.shared.hide()
                        return
                    }
                    options.region = rect
                    self?.recorder.startRecording(options: options)
                }
            } else {
                self.recorder.startRecording(options: options)
            }
        }

        if defaults.bool(forKey: "wac.rec.camera") {
            let sizes: [CGFloat] = [140, 200, 280]
            let sizeIndex = min(defaults.object(forKey: "wac.rec.camsize") as? Int ?? 1, 2)
            let circle = (defaults.object(forKey: "wac.rec.camshape") as? Int ?? 0) == 0
            let corner = defaults.object(forKey: "wac.rec.camcorner") as? Int ?? 1
            CameraOverlay.shared.show(options: .init(size: sizes[sizeIndex],
                                                     circle: circle, corner: corner)) {
                // Give the camera a beat to warm up before frames matter
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: proceed)
            }
        } else {
            proceed()
        }
    }

    // MARK: Color picker (screen eyedropper → hex to clipboard)

    private func pickColor() {
        NSColorSampler().show { color in
            guard let color, let rgb = color.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X",
                             Int(round(rgb.redComponent * 255)),
                             Int(round(rgb.greenComponent * 255)),
                             Int(round(rgb.blueComponent * 255)))
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(hex, forType: .string) // also lands in Clips history
            Toast.show("\(hex) copied ✓")
        }
    }

    // MARK: Screenshot

    private func runScreenshot() {
        // Screen Recording permission — asked when the feature is used
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/wac/screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let file = dir.appendingPathComponent("wac \(formatter.string(from: Date())).png")

        panel.orderOut(nil) // keep the widget out of the shot

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", file.path] // interactive: area, or space for window
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.panel.orderFrontRegardless()
                self?.drawerController.refreshMedia() // new file landed
                // Straight into the annotator when a shot was actually taken
                if FileManager.default.fileExists(atPath: file.path) {
                    Toast.show("screenshot saved ✓")
                    Annotator.shared.open(fileURL: file)
                }
            }
        }
        do { try task.run() } catch { panel.orderFrontRegardless() }
    }

    // MARK: Position persistence (vertical position along the right edge)

    private func saveTabY(_ y: CGFloat) {
        UserDefaults.standard.set(Double(y), forKey: tabYDefaultsKey)
    }

    private func restoredTabOrigin() -> NSPoint {
        let s = panel?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let v = s.visibleFrame
        var y = v.midY - tabSize.height / 2
        if let saved = UserDefaults.standard.object(forKey: tabYDefaultsKey) as? Double {
            y = min(max(CGFloat(saved), v.minY + 8), v.maxY - tabSize.height - 8)
        }
        return NSPoint(x: s.frame.maxX - tabSize.width, y: y)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
