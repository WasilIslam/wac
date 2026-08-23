import AppKit
import AVFoundation

/// Loom-style floating camera bubble. Because screen recording captures
/// everything on screen, this window gets baked into the recording.
final class CameraOverlay {
    static let shared = CameraOverlay()

    struct Options {
        var size: CGFloat
        var circle: Bool
        var corner: Int // 0 ↙  1 ↘  2 ↖  3 ↗
    }

    private var session: AVCaptureSession?
    private var window: NSPanel?
    var isShowing: Bool { window != nil }

    /// `ready` fires on the main queue once the bubble is visible (or the
    /// camera is unavailable) — callers must wait for it before recording,
    /// so the permission prompt never appears mid-recording.
    func show(options: Options, ready: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            present(options)
            ready()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.present(options) }
                    else { Toast.show("camera denied — recording without it") }
                    ready()
                }
            }
        default:
            Toast.show("camera access denied — see System Settings")
            ready()
        }
    }

    private func present(_ options: Options) {
        hide()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            Toast.show("no camera found")
            return
        }
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true // selfie view
        }

        let size = options.size
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        container.wantsLayer = true
        previewLayer.frame = container.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        container.layer?.addSublayer(previewLayer)
        container.layer?.cornerRadius = options.circle ? size / 2 : 18
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 3
        container.layer?.borderColor = Theme.accent.cgColor
        container.layer?.backgroundColor = NSColor.black.cgColor

        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let margin: CGFloat = 24
        let origin: NSPoint
        switch options.corner {
        case 1: origin = NSPoint(x: visible.maxX - size - margin, y: visible.minY + margin)
        case 2: origin = NSPoint(x: visible.minX + margin, y: visible.maxY - size - margin)
        case 3: origin = NSPoint(x: visible.maxX - size - margin, y: visible.maxY - size - margin)
        default: origin = NSPoint(x: visible.minX + margin, y: visible.minY + margin)
        }

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true // drag it anywhere mid-recording
        panel.contentView = container
        panel.orderFrontRegardless()

        window = panel
        session = captureSession
        DispatchQueue.global(qos: .userInitiated).async { captureSession.startRunning() }
    }

    func hide() {
        session?.stopRunning()
        session = nil
        window?.orderOut(nil)
        window = nil
    }
}
