import AppKit
import AVFoundation
import CoreGraphics

struct RecordingOptions {
    var mic: Bool
    var clicks: Bool
    var region: CGRect?
}

/// Screen recording via /usr/sbin/screencapture -v (with -g mic audio when
/// the user grants microphone access). Stopping sends SIGINT, which makes
/// screencapture finalize the movie file.
final class ScreenRecorder {
    private var task: Process?
    private var stdinPipe: Pipe?
    var onStateChange: ((Bool) -> Void)?
    /// Fires with the finished movie once it's on disk.
    var onFinished: ((URL) -> Void)?
    var isRecording: Bool { task?.isRunning ?? false }

    private let dir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/wac/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Permissions are requested HERE — when the user starts the action —
    /// never at app launch or after the capture.
    func startRecording(options: RecordingOptions) {
        guard !isRecording else { return }
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        if options.mic {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                start(options: options, mic: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    DispatchQueue.main.async { self?.start(options: options, mic: granted) }
                }
            default:
                start(options: options, mic: false) // denied: video only
            }
        } else {
            start(options: options, mic: false)
        }
    }

    private func start(options: RecordingOptions, mic audio: Bool) {
        guard !isRecording else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let file = dir.appendingPathComponent("wac \(formatter.string(from: Date())).mov")

        // Log screencapture's output so silent failures are diagnosable:
        // ~/Library/Application Support/wac/recorder.log
        let logURL = wacDataDirectory().appendingPathComponent("recorder.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = FileHandle(forWritingAtPath: logURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var args = ["-v"]
        if audio { args.append("-g") }
        if options.clicks { args.append("-k") }
        if let r = options.region {
            args.append("-R\(Int(r.origin.x)),\(Int(r.origin.y)),\(Int(r.width)),\(Int(r.height))")
        }
        args.append(file.path)
        process.arguments = args
        process.standardError = logHandle
        process.standardOutput = logHandle
        // screencapture's supported stop mechanism is "type any character":
        // it reads STDIN. Signals are unreliable (SIGINT is ignored in some
        // sessions, verified on macOS 26), so keep a pipe to write into.
        let pipe = Pipe()
        process.standardInput = pipe
        process.terminationHandler = { [weak self] _ in
            try? logHandle?.close()
            DispatchQueue.main.async {
                self?.task = nil
                self?.stdinPipe = nil
                self?.onStateChange?(false)
                if FileManager.default.fileExists(atPath: file.path) {
                    self?.onFinished?(file)
                }
            }
        }
        do {
            try process.run()
            task = process
            stdinPipe = pipe
            onStateChange?(true)
        } catch {
            task = nil
            stdinPipe = nil
            onStateChange?(false)
        }
    }

    func stop() {
        guard let process = task, process.isRunning else { return }
        // "any character" on stdin stops the recording and finalizes the file
        stdinPipe?.fileHandleForWriting.write(Data("q".utf8))
        try? stdinPipe?.fileHandleForWriting.close()
        // Fallbacks in case stdin wasn't consumed
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak process] in
            if let process, process.isRunning { process.interrupt() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak process] in
            if let process, process.isRunning { process.terminate() }
        }
    }

    // MARK: shutdown

    /// Synchronous best-effort stop for app shutdown — gives screencapture
    /// a moment to finalize so the recording isn't orphaned or lost.
    func stopAndWait(seconds: Double = 3) {
        guard let process = task, process.isRunning else { return }
        stdinPipe?.fileHandleForWriting.write(Data("q".utf8))
        try? stdinPipe?.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning { process.terminate() }
    }
}

// MARK: - Audio-only recording (mic → .m4a via AVAudioRecorder)

final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    var onStateChange: ((Bool) -> Void)?
    var isRecording: Bool { recorder?.isRecording ?? false }

    private let dir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/wac/audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func toggle() {
        if isRecording { stop(); return }
        // Mic permission up front, before recording begins
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async { if granted { self?.start() } }
            }
        default:
            break // denied — nothing to record with
        }
    }

    private func start() {
        guard !isRecording else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let file = dir.appendingPathComponent("wac \(formatter.string(from: Date())).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        recorder = try? AVAudioRecorder(url: file, settings: settings)
        recorder?.delegate = self
        if recorder?.record() == true {
            onStateChange?(true)
        } else {
            recorder = nil
            onStateChange?(false)
        }
    }

    func stop() {
        recorder?.stop() // delegate fires and flips state
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        self.recorder = nil
        onStateChange?(false)
    }
}
