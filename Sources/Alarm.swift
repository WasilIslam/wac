import AppKit

/// Timers ("ring in N minutes") and alarms ("ring at HH:mm"), persisted so
/// they survive a relaunch. Rings with a looping system chime + a floating
/// dismiss banner.
final class AlarmManager {
    static let shared = AlarmManager()

    struct Alarm: Codable {
        let id: String
        let fireDate: Date
    }

    private(set) var alarms: [Alarm] = []
    var onChange: (() -> Void)?

    private var ticker: Timer?
    private var sound: NSSound?
    private var alertWindow: NSPanel?
    private let defaultsKey = "wac.alarms"

    private init() {
        load()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: Scheduling

    func addTimer(minutes: Double) {
        add(date: Date().addingTimeInterval(minutes * 60))
    }

    /// Rings at the next occurrence of HH:mm (today, or tomorrow if past).
    func addAlarm(hour: Int, minute: Int) {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard var date = Calendar.current.date(from: comps) else { return }
        if date <= Date() {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        add(date: date)
    }

    private func add(date: Date) {
        alarms.append(Alarm(id: UUID().uuidString, fireDate: date))
        alarms.sort { $0.fireDate < $1.fireDate }
        save()
        onChange?()
    }

    func cancel(id: String) {
        alarms.removeAll { $0.id == id }
        save()
        onChange?()
    }

    // MARK: Firing

    private func tick() {
        guard let due = alarms.first(where: { $0.fireDate <= Date() }) else { return }
        alarms.removeAll { $0.fireDate <= Date() }
        save()
        onChange?()
        ring(due)
    }

    private func ring(_ alarm: Alarm) {
        let chime = NSSound(named: "Glass") // built-in macOS sound
        chime?.loops = true
        chime?.play()
        sound = chime
        showBanner(for: alarm)
    }

    private func showBanner(for alarm: Alarm) {
        alertWindow?.orderOut(nil)

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let label = NSTextField(labelWithString: "⏰  \(formatter.string(from: alarm.fireDate))  —  time's up")
        label.font = Theme.mono(13, .bold)
        label.textColor = Theme.textPrimary
        label.sizeToFit()

        let dismiss = FilledButton(title: "Dismiss")
        dismiss.onTap = { [weak self] in self?.dismiss() }
        dismiss.translatesAutoresizingMaskIntoConstraints = false

        let pad: CGFloat = 16
        let size = NSSize(width: label.frame.width + 100 + pad * 3, height: 52)
        let content = AlarmBannerView(frame: NSRect(origin: .zero, size: size))
        label.setFrameOrigin(NSPoint(x: pad, y: (size.height - label.frame.height) / 2))
        content.addSubview(label)
        content.addSubview(dismiss)
        NSLayoutConstraint.activate([
            dismiss.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            dismiss.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            dismiss.widthAnchor.constraint(equalToConstant: 90),
        ])

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                             y: screen.visibleFrame.maxY - size.height - 60)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = content
        panel.orderFrontRegardless()
        alertWindow = panel
    }

    func dismiss() {
        sound?.stop()
        sound = nil
        alertWindow?.orderOut(nil)
        alertWindow = nil
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        alarms = ((try? decoder.decode([Alarm].self, from: data)) ?? [])
            .filter { $0.fireDate > Date() } // drop stale ones
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(alarms) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

/// "in 1h 05m" / "in 45s"
func remainingText(until date: Date) -> String {
    let seconds = max(Int(date.timeIntervalSinceNow), 0)
    if seconds < 60 { return "in \(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "in \(minutes)m" }
    return String(format: "in %dh %02dm", minutes / 60, minutes % 60)
}

private final class AlarmBannerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 14, yRadius: 14)
        Theme.base.withAlphaComponent(0.97).setFill()
        path.fill()
        Theme.accent.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
