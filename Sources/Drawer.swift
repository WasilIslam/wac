import AppKit
import ApplicationServices
import ServiceManagement

/// Synthesize Cmd+V into the frontmost app. Needs the Accessibility
/// permission — requested HERE, before the paste, never after.
func performSystemPaste() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else { return } // prompt shown; user retries after granting
    let source = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // 'v'
    keyDown?.flags = .maskCommand
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

/// Builds and manages everything inside the slide-out drawer:
/// Actions (screenshot / record), Clips (clipboard history), Notes (CRUD).
final class DrawerController: NSObject {
    let view: SidebarView
    var onCollapse: (() -> Void)?
    var onScreenshot: (() -> Void)?
    var onToggleRecord: (() -> Void)?
    var onToggleAudio: (() -> Void)?
    var onDraw: (() -> Void)?
    var onPickColor: (() -> Void)?
    var onThemeChange: (() -> Void)?

    private let contentContainer = NSView()
    private var tabButtons: [PillTabButton] = []
    private var actionsView: NSView!
    private var clipsView: NSView!
    private var mediaView: NSView!
    private var actionsHome: NSView!
    private var notesHolder: NSView!
    private var recordOptionsHolder: NSView!
    private var cameraOptionsStack: NSStackView!
    private var isRecordingNow = false

    private var recordCard: ActionCard!
    private var audioCard: ActionCard!
    private var loginPill: PillTabButton!
    private var settingsHolder: NSView!
    private var downloadsHolder: NSView!
    private var downloadsStack: NSStackView!
    private var alarmHolder: NSView!
    private var alarmsStack: NSStackView!
    private var minutesField: NSTextField!
    private var alarmPicker: NSDatePicker!
    private var sysInfoLabel: NSTextField!
    private var sysInfoTimer: Timer?
    private var currentTabIndex = 0

    deinit { sysInfoTimer?.invalidate() }
    private var clipsStack: NSStackView!
    private var notesStack: NSStackView!
    private var mediaStack: NSStackView!

    // Notes editor state
    private var notesListView: NSView!
    private var notesEditorView: NSView!
    private var editingNoteId: String?
    private var titleField: NSTextField!
    private var bodyText: NSTextView!
    private var deleteButton: FilledButton!

    private let contentLeading: CGFloat = 38
    private let contentTrailing: CGFloat = 18

    init(width: CGFloat) {
        view = SidebarView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        super.init()
        build()
        ClipboardStore.shared.onChange = { [weak self] in self?.reloadClips() }
        NotesStore.shared.onChange = { [weak self] in self?.reloadNotes() }
        AlarmManager.shared.onChange = { [weak self] in self?.reloadAlarms() }
        reloadClips()
        reloadNotes()
        selectTab(0)
        // Keep the footer clocks current while the drawer is up
        sysInfoTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sysInfoLabel.stringValue = SysInfo.summary()
            if let holder = self.alarmHolder, !holder.isHidden { self.reloadAlarms() } // countdowns
        }
    }

    // MARK: Skeleton

    private func build() {
        // Close caret, merged into the drawer surface (no separate border)
        let close = IconButton(symbol: "chevron.right")
        close.onTap = { [weak self] in self?.onCollapse?() }
        close.translatesAutoresizingMaskIntoConstraints = false

        // Header
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = Theme.accent.cgColor
        dot.layer?.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let title = NSTextField(labelWithString: "wac_")
        title.font = Theme.mono(20, .bold)
        title.textColor = Theme.textPrimary

        let byline = NSTextField(labelWithString: "by wasil")
        byline.font = Theme.mono(9)
        byline.textColor = Theme.textTertiary

        let headerRow = NSStackView(views: [dot, title, byline])
        headerRow.orientation = .horizontal
        headerRow.alignment = .lastBaseline
        headerRow.spacing = 9
        headerRow.setCustomSpacing(6, after: title)
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        // Tabs (Notes lives inside Actions now)
        let tabTitles = ["Actions", "Clips", "Files"]
        let tabsRow = NSStackView()
        tabsRow.orientation = .horizontal
        tabsRow.spacing = 4
        tabsRow.translatesAutoresizingMaskIntoConstraints = false
        for (index, tabTitle) in tabTitles.enumerated() {
            let button = PillTabButton(title: tabTitle)
            button.onTap = { [weak self] in self?.selectTab(index) }
            tabButtons.append(button)
            tabsRow.addArrangedSubview(button)
        }

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        // Settings cog, aligned with the tab row
        let cog = IconButton(symbol: "gearshape", pointSize: 11)
        cog.onTap = { [weak self] in self?.showSettings() }
        cog.translatesAutoresizingMaskIntoConstraints = false

        // System glance line above the footer
        sysInfoLabel = NSTextField(wrappingLabelWithString: SysInfo.summary())
        sysInfoLabel.font = Theme.mono(8.5)
        sysInfoLabel.textColor = Theme.textTertiary
        sysInfoLabel.maximumNumberOfLines = 2
        sysInfoLabel.cell?.truncatesLastVisibleLine = true
        sysInfoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sysInfoLabel.isSelectable = false
        sysInfoLabel.translatesAutoresizingMaskIntoConstraints = false

        // Footer: compact quit + launch-at-login toggle
        let footerDivider = dividerLine()
        let quit = PillTabButton(title: "⏻  quit wac")
        quit.onTap = { NSApp.terminate(nil) }
        quit.translatesAutoresizingMaskIntoConstraints = false

        let login = PillTabButton(title: "launch at login")
        loginPill = login
        login.onTap = { [weak self] in
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    Toast.show("login item removed")
                } else {
                    try SMAppService.mainApp.register()
                    Toast.show("will launch at login ✓")
                }
            } catch {
                Toast.show("login item failed: \(error.localizedDescription)")
            }
            self?.refreshLoginPill()
        }
        login.translatesAutoresizingMaskIntoConstraints = false
        refreshLoginPill()

        view.addSubview(close)
        view.addSubview(headerRow)
        view.addSubview(tabsRow)
        view.addSubview(cog)
        view.addSubview(contentContainer)
        view.addSubview(sysInfoLabel)
        view.addSubview(footerDivider)
        view.addSubview(quit)
        view.addSubview(login)

        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            close.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 26),
            close.heightAnchor.constraint(equalToConstant: 52),

            headerRow.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),
            headerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentLeading),

            tabsRow.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 16),
            tabsRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentLeading),
            cog.centerYAnchor.constraint(equalTo: tabsRow.centerYAnchor),
            cog.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentTrailing),
            cog.widthAnchor.constraint(equalToConstant: 24),
            cog.heightAnchor.constraint(equalToConstant: 24),

            contentContainer.topAnchor.constraint(equalTo: tabsRow.bottomAnchor, constant: 16),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentLeading),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentTrailing),
            contentContainer.bottomAnchor.constraint(equalTo: sysInfoLabel.topAnchor, constant: -8),

            sysInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentLeading),
            sysInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -contentTrailing),
            sysInfoLabel.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -8),

            footerDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentLeading),
            footerDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentTrailing),
            footerDivider.bottomAnchor.constraint(equalTo: quit.topAnchor, constant: -8),
            quit.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentLeading),
            quit.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            login.centerYAnchor.constraint(equalTo: quit.centerYAnchor),
            login.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentTrailing),
        ])

        actionsView = buildActionsTab()
        clipsView = buildClipsTab()
        mediaView = buildMediaTab()
        settingsHolder = buildSettings()
        settingsHolder.isHidden = true
        for tab in [actionsView!, clipsView!, mediaView!, settingsHolder!] {
            tab.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(tab)
            NSLayoutConstraint.activate([
                tab.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                tab.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                tab.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                tab.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            ])
        }
    }

    private func selectTab(_ index: Int) {
        currentTabIndex = index
        for (i, button) in tabButtons.enumerated() { button.isSelected = i == index }
        actionsView.isHidden = index != 0
        clipsView.isHidden = index != 1
        mediaView.isHidden = index != 2
        settingsHolder.isHidden = true
        if index == 2 { refreshMedia() }
    }

    // MARK: Actions tab

    private func buildActionsTab() -> NSView {
        let container = NSView()
        actionsHome = buildActionsHome()
        notesHolder = buildNotesSection()
        recordOptionsHolder = buildRecordOptionsSection()
        downloadsHolder = buildDownloadsSection()
        alarmHolder = buildAlarmSection()
        notesHolder.isHidden = true
        recordOptionsHolder.isHidden = true
        downloadsHolder.isHidden = true
        alarmHolder.isHidden = true
        for sub in [actionsHome!, notesHolder!, recordOptionsHolder!, downloadsHolder!, alarmHolder!] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(sub)
            NSLayoutConstraint.activate([
                sub.topAnchor.constraint(equalTo: container.topAnchor),
                sub.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                sub.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                sub.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        return container
    }

    private func buildActionsHome() -> NSView {
        let container = NSView()

        let shotCard = ActionCard(symbol: "camera.viewfinder",
                                  tint: Theme.foam,
                                  title: "Screenshot", keycap: "⌃⌥S")
        shotCard.onTap = { [weak self] in
            self?.onCollapse?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.onScreenshot?() }
        }

        recordCard = ActionCard(symbol: "record.circle", tint: Theme.danger,
                                title: "Record", keycap: "⌃⌥R")
        recordCard.onTap = { [weak self] in
            guard let self else { return }
            if self.isRecordingNow {
                // Stop directly — no options detour
                self.onCollapse?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.onToggleRecord?() }
            } else {
                self.showRecordOptions(true)
            }
        }

        audioCard = ActionCard(symbol: "waveform", tint: Theme.iris, title: "Audio")
        audioCard.onTap = { [weak self] in
            self?.onCollapse?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.onToggleAudio?() }
        }

        let notesCard = ActionCard(symbol: "note.text",
                                   tint: Theme.accent,
                                   title: "Notes")
        notesCard.onTap = { [weak self] in self?.showNotes(true) }

        let drawCard = ActionCard(symbol: "pencil.and.outline",
                                  tint: Theme.rose,
                                  title: "Draw")
        drawCard.onTap = { [weak self] in
            self?.onCollapse?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.onDraw?() }
        }

        let pickCard = ActionCard(symbol: "eyedropper.halffull",
                                  tint: NSColor(red: 0.192, green: 0.455, blue: 0.561, alpha: 1) /* pine */,
                                  title: "Pick Color")
        pickCard.onTap = { [weak self] in
            self?.onCollapse?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.onPickColor?() }
        }

        let downloadsCard = ActionCard(symbol: "arrow.down.circle",
                                       tint: Theme.foam,
                                       title: "Downloads")
        downloadsCard.onTap = { [weak self] in self?.showDownloads(true) }

        let alarmCard = ActionCard(symbol: "alarm",
                                   tint: NSColor(red: 1.0, green: 0.62, blue: 0.30, alpha: 1),
                                   title: "Alarm")
        alarmCard.onTap = { [weak self] in self?.showAlarms(true) }

        let row1 = NSStackView(views: [shotCard, recordCard])
        let row2 = NSStackView(views: [audioCard, notesCard])
        let row3 = NSStackView(views: [drawCard, pickCard])
        let row4 = NSStackView(views: [downloadsCard, alarmCard])
        for row in [row1, row2, row3, row4] {
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 8
        }
        let grid = NSStackView(views: [row1, row2, row3, row4])
        grid.orientation = .vertical
        grid.spacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false

        let caption = NSTextField(labelWithString: "⌃⌥W toggles wac  ·  → ~/Pictures/wac")
        caption.font = Theme.mono(8.5)
        caption.textColor = Theme.textTertiary
        caption.lineBreakMode = .byTruncatingTail
        // Truncate — never force the WINDOW to grow to fit the text
        caption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        caption.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(grid)
        container.addSubview(caption)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row1.widthAnchor.constraint(equalTo: grid.widthAnchor),
            row2.widthAnchor.constraint(equalTo: grid.widthAnchor),
            row3.widthAnchor.constraint(equalTo: grid.widthAnchor),
            row4.widthAnchor.constraint(equalTo: grid.widthAnchor),
            caption.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),
            caption.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            caption.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        return container
    }

    // MARK: Settings (behind the cog)

    private func buildSettings() -> NSView {
        let container = NSView()

        let back = IconButton(symbol: "chevron.left", pointSize: 10)
        back.onTap = { [weak self] in
            guard let self else { return }
            self.selectTab(self.currentTabIndex)
        }
        back.translatesAutoresizingMaskIntoConstraints = false

        let label = sectionLabel("Settings")
        label.translatesAutoresizingMaskIntoConstraints = false

        let themeLabel = sectionLabel("Theme")
        themeLabel.translatesAutoresizingMaskIntoConstraints = false

        let themeRow = NSStackView()
        themeRow.orientation = .horizontal
        themeRow.spacing = 6
        themeRow.translatesAutoresizingMaskIntoConstraints = false
        for palette in Theme.palettes {
            let dot = SwatchButton(color: palette.accent)
            dot.isSelected = palette.name == Theme.current.name
            dot.toolTip = palette.name
            dot.onTap = { [weak self] in
                Theme.select(palette.name)
                Toast.show("theme: \(palette.name)")
                self?.onThemeChange?()
            }
            themeRow.addArrangedSubview(dot)
        }

        let themeName = NSTextField(labelWithString: Theme.current.name)
        themeName.font = Theme.mono(9)
        themeName.textColor = Theme.textTertiary
        themeName.translatesAutoresizingMaskIntoConstraints = false

        // Which world clocks to show in the footer line
        let clocksLabel = sectionLabel("Clocks")
        clocksLabel.translatesAutoresizingMaskIntoConstraints = false
        let clocksRow = NSStackView()
        clocksRow.orientation = .horizontal
        clocksRow.spacing = 3
        clocksRow.translatesAutoresizingMaskIntoConstraints = false
        for (code, _) in SysInfo.clockOptions {
            let pill = PillTabButton(title: code)
            pill.isSelected = SysInfo.selectedClocks().contains(code)
            pill.onTap = { [weak self, weak pill] in
                guard let pill else { return }
                var selected = SysInfo.selectedClocks()
                if let index = selected.firstIndex(of: code) {
                    selected.remove(at: index)
                } else {
                    selected.append(code)
                }
                UserDefaults.standard.set(selected, forKey: SysInfo.clocksDefaultsKey)
                pill.isSelected.toggle()
                self?.sysInfoLabel.stringValue = SysInfo.summary()
            }
            clocksRow.addArrangedSubview(pill)
        }

        container.addSubview(back)
        container.addSubview(label)
        container.addSubview(themeLabel)
        container.addSubview(themeRow)
        container.addSubview(themeName)
        container.addSubview(clocksLabel)
        container.addSubview(clocksRow)
        NSLayoutConstraint.activate([
            clocksLabel.topAnchor.constraint(equalTo: themeRow.bottomAnchor, constant: 20),
            clocksLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            clocksRow.topAnchor.constraint(equalTo: clocksLabel.bottomAnchor, constant: 8),
            clocksRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            clocksRow.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            back.topAnchor.constraint(equalTo: container.topAnchor),
            back.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            back.widthAnchor.constraint(equalToConstant: 22),
            back.heightAnchor.constraint(equalToConstant: 22),
            label.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 6),
            themeLabel.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 18),
            themeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            themeRow.topAnchor.constraint(equalTo: themeLabel.bottomAnchor, constant: 8),
            themeRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            themeName.centerYAnchor.constraint(equalTo: themeRow.centerYAnchor),
            themeName.leadingAnchor.constraint(equalTo: themeRow.trailingAnchor, constant: 10),
        ])
        return container
    }

    private func showSettings() {
        actionsView.isHidden = true
        clipsView.isHidden = true
        mediaView.isHidden = true
        settingsHolder.isHidden = false
    }

    /// Shown when the Record card is tapped: choose options, then start.
    private func buildRecordOptionsSection() -> NSView {
        let container = NSView()

        let back = IconButton(symbol: "chevron.left", pointSize: 10)
        back.onTap = { [weak self] in self?.showRecordOptions(false) }
        back.translatesAutoresizingMaskIntoConstraints = false

        let label = sectionLabel("Record options")
        label.translatesAutoresizingMaskIntoConstraints = false

        // Native checkboxes, short titles
        func checkbox(_ title: String, key: String, defaultOn: Bool) -> NSButton {
            let box = NSButton(checkboxWithTitle: title, target: self,
                               action: #selector(recordOptionToggled(_:)))
            box.identifier = NSUserInterfaceItemIdentifier(key)
            box.font = .systemFont(ofSize: 12)
            box.state = (UserDefaults.standard.object(forKey: key) as? Bool ?? defaultOn) ? .on : .off
            return box
        }

        let cameraBox = checkbox("Camera bubble", key: "wac.rec.camera", defaultOn: false)

        // Camera sub-options — only visible while the camera box is ticked
        func segmentRow(_ name: String, options: [String], key: String, defaultIndex: Int) -> NSStackView {
            let tag = NSTextField(labelWithString: name)
            tag.font = Theme.mono(9)
            tag.textColor = Theme.textSecondary
            tag.translatesAutoresizingMaskIntoConstraints = false
            tag.widthAnchor.constraint(equalToConstant: 46).isActive = true
            let segment = NSSegmentedControl(labels: options, trackingMode: .selectOne,
                                             target: self, action: #selector(recordSegmentChanged(_:)))
            segment.identifier = NSUserInterfaceItemIdentifier(key)
            segment.selectedSegment = UserDefaults.standard.object(forKey: key) as? Int ?? defaultIndex
            let row = NSStackView(views: [tag, segment])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            return row
        }

        let cameraStack = NSStackView(views: [
            segmentRow("size", options: ["S", "M", "L"], key: "wac.rec.camsize", defaultIndex: 1),
            segmentRow("shape", options: ["circle", "square"], key: "wac.rec.camshape", defaultIndex: 0),
            segmentRow("corner", options: ["\u{2199}", "\u{2198}", "\u{2196}", "\u{2197}"],
                       key: "wac.rec.camcorner", defaultIndex: 1),
        ])
        cameraStack.orientation = .vertical
        cameraStack.alignment = .leading
        cameraStack.spacing = 8
        cameraStack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        cameraStack.isHidden = cameraBox.state != .on
        cameraOptionsStack = cameraStack

        let stack = NSStackView(views: [
            checkbox("Select region", key: "wac.rec.region", defaultOn: false),
            checkbox("Microphone", key: "wac.rec.mic", defaultOn: true),
            checkbox("Show clicks", key: "wac.rec.clicks", defaultOn: false),
            cameraBox,
            cameraStack,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let start = FilledButton(title: "\u{25CF}  Start Recording", color: Theme.danger)
        start.onTap = { [weak self] in
            guard let self else { return }
            self.showRecordOptions(false)
            self.onCollapse?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.onToggleRecord?() }
        }
        start.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(back)
        container.addSubview(label)
        container.addSubview(stack)
        container.addSubview(start)
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: container.topAnchor),
            back.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            back.widthAnchor.constraint(equalToConstant: 22),
            back.heightAnchor.constraint(equalToConstant: 22),
            label.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 6),
            stack.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            start.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 20),
            start.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            start.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
        return container
    }

    @objc private func recordOptionToggled(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: key)
        if key == "wac.rec.camera" {
            cameraOptionsStack.isHidden = sender.state != .on
        }
    }

    @objc private func recordSegmentChanged(_ sender: NSSegmentedControl) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.selectedSegment, forKey: key)
    }

    private func showRecordOptions(_ show: Bool) {
        actionsHome.isHidden = show
        recordOptionsHolder.isHidden = !show
        if show {
            notesHolder.isHidden = true
            downloadsHolder.isHidden = true
            alarmHolder.isHidden = true
        }
    }

    // MARK: Downloads section (inside Actions)

    private func buildDownloadsSection() -> NSView {
        let container = NSView()

        let back = IconButton(symbol: "chevron.left", pointSize: 10)
        back.onTap = { [weak self] in self?.showDownloads(false) }
        back.translatesAutoresizingMaskIntoConstraints = false

        let label = sectionLabel("Recent downloads")
        label.translatesAutoresizingMaskIntoConstraints = false

        let openFolder = IconButton(symbol: "folder", pointSize: 10)
        openFolder.onTap = {
            NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory,
                                                             in: .userDomainMask)[0])
        }
        openFolder.translatesAutoresizingMaskIntoConstraints = false

        let (scroll, stack) = makeScrollList()
        downloadsStack = stack

        container.addSubview(back)
        container.addSubview(label)
        container.addSubview(openFolder)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: container.topAnchor),
            back.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            back.widthAnchor.constraint(equalToConstant: 22),
            back.heightAnchor.constraint(equalToConstant: 22),
            label.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 6),
            openFolder.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            openFolder.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            openFolder.widthAnchor.constraint(equalToConstant: 24),
            openFolder.heightAnchor.constraint(equalToConstant: 20),
            scroll.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func showDownloads(_ show: Bool) {
        actionsHome.isHidden = show
        downloadsHolder.isHidden = !show
        if show {
            notesHolder.isHidden = true
            recordOptionsHolder.isHidden = true
            alarmHolder.isHidden = true
            reloadDownloads()
        }
    }

    // MARK: Alarm section (inside Actions)

    private func buildAlarmSection() -> NSView {
        let container = NSView()

        let back = IconButton(symbol: "chevron.left", pointSize: 10)
        back.onTap = { [weak self] in self?.showAlarms(false) }
        back.translatesAutoresizingMaskIntoConstraints = false

        let label = sectionLabel("Alarm & timer")
        label.translatesAutoresizingMaskIntoConstraints = false

        // -- Timer: one-tap presets + custom minutes --
        let timerLabel = sectionLabel("Timer")
        timerLabel.translatesAutoresizingMaskIntoConstraints = false

        minutesField = NSTextField()
        minutesField.placeholderString = "25"
        minutesField.font = Theme.mono(12)
        minutesField.textColor = Theme.textPrimary
        minutesField.isBordered = false
        minutesField.drawsBackground = true
        minutesField.backgroundColor = Theme.fieldBg
        minutesField.wantsLayer = true
        minutesField.layer?.cornerRadius = 7
        minutesField.focusRingType = .none
        minutesField.alignment = .center
        minutesField.target = self
        minutesField.action = #selector(startTimerTapped)
        minutesField.translatesAutoresizingMaskIntoConstraints = false
        minutesField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        minutesField.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let minutesTag = NSTextField(labelWithString: "minutes")
        minutesTag.font = Theme.mono(9)
        minutesTag.textColor = Theme.textSecondary

        let startTimer = FilledButton(title: "Start")
        startTimer.onTap = { [weak self] in self?.startTimerTapped() }

        let customRow = NSStackView(views: [minutesField, minutesTag, startTimer])
        customRow.orientation = .horizontal
        customRow.alignment = .centerY
        customRow.spacing = 8
        customRow.translatesAutoresizingMaskIntoConstraints = false

        // -- Alarm: native time picker with steppers --
        let alarmLabel = sectionLabel("Alarm")
        alarmLabel.translatesAutoresizingMaskIntoConstraints = false

        alarmPicker = NSDatePicker()
        alarmPicker.datePickerStyle = .textFieldAndStepper
        alarmPicker.datePickerElements = .hourMinute
        alarmPicker.dateValue = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        alarmPicker.font = Theme.mono(12)
        alarmPicker.translatesAutoresizingMaskIntoConstraints = false

        let atTag = NSTextField(labelWithString: "rings at")
        atTag.font = Theme.mono(9)
        atTag.textColor = Theme.textSecondary

        let setAlarm = FilledButton(title: "Set")
        setAlarm.onTap = { [weak self] in self?.setAlarmTapped() }

        let alarmRow = NSStackView(views: [atTag, alarmPicker, setAlarm])
        alarmRow.orientation = .horizontal
        alarmRow.alignment = .centerY
        alarmRow.spacing = 8
        alarmRow.translatesAutoresizingMaskIntoConstraints = false

        let pendingLabel = sectionLabel("Pending")
        pendingLabel.translatesAutoresizingMaskIntoConstraints = false

        let (scroll, stack) = makeScrollList()
        alarmsStack = stack

        container.addSubview(back)
        container.addSubview(label)
        container.addSubview(timerLabel)
        container.addSubview(customRow)
        container.addSubview(alarmLabel)
        container.addSubview(alarmRow)
        container.addSubview(pendingLabel)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: container.topAnchor),
            back.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            back.widthAnchor.constraint(equalToConstant: 22),
            back.heightAnchor.constraint(equalToConstant: 22),
            label.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 6),

            timerLabel.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 16),
            timerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            customRow.topAnchor.constraint(equalTo: timerLabel.bottomAnchor, constant: 8),
            customRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),

            alarmLabel.topAnchor.constraint(equalTo: customRow.bottomAnchor, constant: 20),
            alarmLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            alarmRow.topAnchor.constraint(equalTo: alarmLabel.bottomAnchor, constant: 8),
            alarmRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),

            pendingLabel.topAnchor.constraint(equalTo: alarmRow.bottomAnchor, constant: 20),
            pendingLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            scroll.topAnchor.constraint(equalTo: pendingLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    @objc private func startTimerTapped() {
        guard let minutes = Double(minutesField.stringValue.trimmingCharacters(in: .whitespaces)),
              minutes > 0 else {
            Toast.show("enter minutes, e.g. 25")
            return
        }
        AlarmManager.shared.addTimer(minutes: minutes)
        minutesField.stringValue = ""
        Toast.show("timer set — rings \(remainingText(until: Date().addingTimeInterval(minutes * 60)))")
    }

    @objc private func setAlarmTapped() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmPicker.dateValue)
        let hour = comps.hour ?? 9
        let minute = comps.minute ?? 0
        AlarmManager.shared.addAlarm(hour: hour, minute: minute)
        Toast.show(String(format: "alarm set for %02d:%02d", hour, minute))
    }

    private func showAlarms(_ show: Bool) {
        actionsHome.isHidden = show
        alarmHolder.isHidden = !show
        if show {
            notesHolder.isHidden = true
            recordOptionsHolder.isHidden = true
            downloadsHolder.isHidden = true
            reloadAlarms()
        }
    }

    private func reloadAlarms() {
        guard let alarmsStack else { return }
        alarmsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let alarms = AlarmManager.shared.alarms
        if alarms.isEmpty {
            alarmsStack.addArrangedSubview(emptyLabel("nothing scheduled"))
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        for alarm in alarms {
            let card = RowCard()
            let title = NSTextField(labelWithString: "⏰  \(formatter.string(from: alarm.fireDate))")
            title.font = Theme.mono(12, .semibold)
            title.textColor = Theme.textPrimary
            card.configure(content: title,
                           meta: remainingText(until: alarm.fireDate),
                           onDelete: { AlarmManager.shared.cancel(id: alarm.id) })
            alarmsStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: alarmsStack.widthAnchor).isActive = true
        }
    }

    private func reloadDownloads() {
        downloadsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = MediaStore.shared.recentDownloads(limit: 15)
        if items.isEmpty {
            downloadsStack.addArrangedSubview(emptyLabel("nothing in ~/Downloads yet"))
            return
        }
        for item in items {
            let cell = MediaCell(item: item)
            cell.onChanged = { [weak self] in self?.reloadDownloads() }
            downloadsStack.addArrangedSubview(cell)
            cell.widthAnchor.constraint(equalTo: downloadsStack.widthAnchor).isActive = true
        }
    }

    /// Notes section inside Actions: back button + the notes list/editor.
    private func buildNotesSection() -> NSView {
        let container = NSView()

        let back = IconButton(symbol: "chevron.left", pointSize: 10)
        back.onTap = { [weak self] in self?.showNotes(false) }
        back.translatesAutoresizingMaskIntoConstraints = false

        let label = sectionLabel("Notes")
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = buildNotesTab()
        content.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(back)
        container.addSubview(label)
        container.addSubview(content)
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: container.topAnchor),
            back.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            back.widthAnchor.constraint(equalToConstant: 22),
            back.heightAnchor.constraint(equalToConstant: 22),
            label.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 6),
            content.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func showNotes(_ show: Bool) {
        if !show { saveDraftIfEditing() }
        actionsHome.isHidden = show
        notesHolder.isHidden = !show
        if show {
            recordOptionsHolder.isHidden = true
            downloadsHolder.isHidden = true
            alarmHolder.isHidden = true
        }
    }

    func setRecording(_ recording: Bool) {
        isRecordingNow = recording
        recordCard.update(symbol: recording ? "stop.fill" : "record.circle",
                          title: recording ? "Stop & Save" : "Record")
    }

    func setAudioRecording(_ recording: Bool) {
        audioCard.update(symbol: recording ? "stop.fill" : "waveform",
                         title: recording ? "Stop Audio" : "Audio")
    }

    // MARK: Clips tab

    private func buildClipsTab() -> NSView {
        let container = NSView()

        let header = sectionLabel("Clipboard · last \(ClipboardStore.maxItems)")
        header.translatesAutoresizingMaskIntoConstraints = false

        let clear = IconButton(symbol: "trash", pointSize: 10)
        clear.onTap = {
            ClipboardStore.shared.clearAll()
            Toast.show("clipboard history cleared")
        }
        clear.translatesAutoresizingMaskIntoConstraints = false

        let (scroll, stack) = makeScrollList()
        clipsStack = stack

        container.addSubview(header)
        container.addSubview(clear)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            clear.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            clear.widthAnchor.constraint(equalToConstant: 24),
            clear.heightAnchor.constraint(equalToConstant: 20),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func reloadClips() {
        clipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = ClipboardStore.shared.items
        if items.isEmpty {
            clipsStack.addArrangedSubview(emptyLabel("copy something and it shows up here"))
            return
        }
        for item in items {
            let cell = makeClipCell(item)
            clipsStack.addArrangedSubview(cell)
            cell.widthAnchor.constraint(equalTo: clipsStack.widthAnchor).isActive = true
        }
    }

    private func makeClipCell(_ item: ClipItem) -> NSView {
        let cell = RowCard()
        // Click = copy to clipboard AND paste into the app you came from.
        cell.onClick = { [weak self] in
            ClipboardStore.shared.copyToPasteboard(item)
            Toast.show("copied ✓ pasting…")
            self?.onCollapse?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { performSystemPaste() }
        }
        // Drag = pull the clip out into any app
        cell.dragProvider = {
            switch item.kind {
            case .text: return (item.text ?? "") as NSString
            case .image: return ClipboardStore.shared.imageURL(for: item) as NSURL?
            }
        }

        let content: NSView
        switch item.kind {
        case .text:
            let label = NSTextField(wrappingLabelWithString: item.text ?? "")
            label.font = .systemFont(ofSize: 11.5)
            label.textColor = Theme.textPrimary
            label.maximumNumberOfLines = 2
            label.cell?.truncatesLastVisibleLine = true // "…" on long text
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            content = label
        case .image:
            let imageView = NSImageView()
            if let url = ClipboardStore.shared.imageURL(for: item) {
                imageView.image = NSImage(contentsOf: url)
            }
            imageView.imageScaling = .scaleProportionallyDown
            imageView.imageAlignment = .alignLeft
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 6
            imageView.layer?.masksToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            content = imageView
        }

        cell.configure(content: content,
                       meta: "\(item.kind == .image ? "image · " : "")\(clipDateFormatter.string(from: item.date))",
                       onDelete: { ClipboardStore.shared.delete(item) })
        return cell
    }

    // MARK: Files tab (screenshots + recordings by date)

    private func buildMediaTab() -> NSView {
        let container = NSView()

        let header = sectionLabel("Captures")
        header.translatesAutoresizingMaskIntoConstraints = false

        let openFolder = IconButton(symbol: "folder", pointSize: 10)
        openFolder.onTap = { NSWorkspace.shared.open(MediaStore.shared.baseDir) }
        openFolder.translatesAutoresizingMaskIntoConstraints = false

        let (scroll, stack) = makeScrollList()
        mediaStack = stack

        container.addSubview(header)
        container.addSubview(openFolder)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            openFolder.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            openFolder.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            openFolder.widthAnchor.constraint(equalToConstant: 24),
            openFolder.heightAnchor.constraint(equalToConstant: 20),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func refreshMedia() {
        guard let mediaStack else { return }
        mediaStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let groups = MediaStore.shared.groupedByDay()
        if groups.isEmpty {
            mediaStack.addArrangedSubview(emptyLabel("no captures yet — take a screenshot"))
            return
        }
        for (day, items) in groups {
            let label = sectionLabel(day)
            mediaStack.addArrangedSubview(label)
            mediaStack.setCustomSpacing(6, after: label)
            for item in items {
                let cell = MediaCell(item: item)
                cell.onChanged = { [weak self] in self?.refreshMedia() }
                mediaStack.addArrangedSubview(cell)
                cell.widthAnchor.constraint(equalTo: mediaStack.widthAnchor).isActive = true
            }
            if let last = mediaStack.arrangedSubviews.last {
                mediaStack.setCustomSpacing(14, after: last)
            }
        }
    }

    // MARK: Notes tab

    private func buildNotesTab() -> NSView {
        let container = NSView()

        // -- List mode --
        notesListView = NSView()
        notesListView.translatesAutoresizingMaskIntoConstraints = false

        let newNote = FilledButton(title: "+  New Note")
        newNote.onTap = { [weak self] in self?.openEditor(note: nil) }
        newNote.translatesAutoresizingMaskIntoConstraints = false

        let (scroll, stack) = makeScrollList()
        notesStack = stack

        notesListView.addSubview(newNote)
        notesListView.addSubview(scroll)
        NSLayoutConstraint.activate([
            newNote.topAnchor.constraint(equalTo: notesListView.topAnchor),
            newNote.leadingAnchor.constraint(equalTo: notesListView.leadingAnchor),
            newNote.trailingAnchor.constraint(equalTo: notesListView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: newNote.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: notesListView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: notesListView.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: notesListView.bottomAnchor),
        ])

        // -- Editor mode --
        notesEditorView = NSView()
        notesEditorView.translatesAutoresizingMaskIntoConstraints = false
        notesEditorView.isHidden = true

        let back = IconButton(symbol: "chevron.left", pointSize: 10)
        back.onTap = { [weak self] in self?.closeEditor(save: true) }
        back.translatesAutoresizingMaskIntoConstraints = false

        titleField = NSTextField()
        titleField.placeholderString = "Title"
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = Theme.textPrimary
        titleField.isBordered = false
        titleField.drawsBackground = true
        titleField.backgroundColor = Theme.fieldBg
        titleField.wantsLayer = true
        titleField.layer?.cornerRadius = 8
        titleField.focusRingType = .none
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let bodyCard = NSView()
        bodyCard.wantsLayer = true
        bodyCard.layer?.backgroundColor = Theme.cardBg.cgColor
        bodyCard.layer?.cornerRadius = 10
        bodyCard.layer?.borderWidth = 1
        bodyCard.layer?.borderColor = Theme.hairline.cgColor
        bodyCard.translatesAutoresizingMaskIntoConstraints = false

        let bodyScroll = NSScrollView()
        bodyScroll.drawsBackground = false
        bodyScroll.hasVerticalScroller = true
        bodyScroll.scrollerStyle = .overlay
        bodyScroll.translatesAutoresizingMaskIntoConstraints = false

        bodyText = NSTextView()
        bodyText.drawsBackground = false
        bodyText.font = .systemFont(ofSize: 12)
        bodyText.textColor = Theme.textPrimary
        bodyText.insertionPointColor = Theme.accent
        bodyText.isRichText = false
        bodyText.autoresizingMask = [.width]
        bodyText.textContainerInset = NSSize(width: 6, height: 8)
        bodyScroll.documentView = bodyText
        bodyCard.addSubview(bodyScroll)

        let save = FilledButton(title: "Save")
        save.onTap = { [weak self] in
            self?.closeEditor(save: true)
            Toast.show("note saved ✓")
        }
        save.translatesAutoresizingMaskIntoConstraints = false

        deleteButton = FilledButton(title: "Delete", color: Theme.danger)
        deleteButton.onTap = { [weak self] in
            guard let self else { return }
            if let id = self.editingNoteId { NotesStore.shared.delete(id: id) }
            self.closeEditor(save: false)
        }
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        notesEditorView.addSubview(back)
        notesEditorView.addSubview(titleField)
        notesEditorView.addSubview(bodyCard)
        notesEditorView.addSubview(save)
        notesEditorView.addSubview(deleteButton)
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: notesEditorView.topAnchor),
            back.leadingAnchor.constraint(equalTo: notesEditorView.leadingAnchor),
            back.widthAnchor.constraint(equalToConstant: 24),
            back.heightAnchor.constraint(equalToConstant: 24),

            titleField.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            titleField.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: notesEditorView.trailingAnchor),
            titleField.heightAnchor.constraint(equalToConstant: 28),

            bodyCard.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 10),
            bodyCard.leadingAnchor.constraint(equalTo: notesEditorView.leadingAnchor),
            bodyCard.trailingAnchor.constraint(equalTo: notesEditorView.trailingAnchor),

            bodyScroll.topAnchor.constraint(equalTo: bodyCard.topAnchor, constant: 4),
            bodyScroll.leadingAnchor.constraint(equalTo: bodyCard.leadingAnchor, constant: 4),
            bodyScroll.trailingAnchor.constraint(equalTo: bodyCard.trailingAnchor, constant: -4),
            bodyScroll.bottomAnchor.constraint(equalTo: bodyCard.bottomAnchor, constant: -4),

            save.topAnchor.constraint(equalTo: bodyCard.bottomAnchor, constant: 10),
            save.leadingAnchor.constraint(equalTo: notesEditorView.leadingAnchor),
            save.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            save.bottomAnchor.constraint(equalTo: notesEditorView.bottomAnchor),

            deleteButton.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: notesEditorView.trailingAnchor),
            deleteButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])

        container.addSubview(notesListView)
        container.addSubview(notesEditorView)
        for sub in [notesListView!, notesEditorView!] {
            NSLayoutConstraint.activate([
                sub.topAnchor.constraint(equalTo: container.topAnchor),
                sub.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                sub.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                sub.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        return container
    }

    private func reloadNotes() {
        notesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let notes = NotesStore.shared.items
        if notes.isEmpty {
            notesStack.addArrangedSubview(emptyLabel("no notes yet — create one above"))
            return
        }
        for note in notes {
            let cell = RowCard()
            let label = NSTextField(labelWithString: note.title.isEmpty ? "Untitled" : note.title)
            label.font = .systemFont(ofSize: 12.5, weight: .semibold)
            label.textColor = Theme.textPrimary
            label.lineBreakMode = .byTruncatingTail
            cell.configure(content: label,
                           meta: clipDateFormatter.string(from: note.modified),
                           onDelete: { NotesStore.shared.delete(id: note.id) })
            cell.onClick = { [weak self] in self?.openEditor(note: note) }
            notesStack.addArrangedSubview(cell)
            cell.widthAnchor.constraint(equalTo: notesStack.widthAnchor).isActive = true
        }
    }

    private func openEditor(note: Note?) {
        editingNoteId = note?.id
        titleField.stringValue = note?.title ?? ""
        bodyText.string = note?.body ?? ""
        deleteButton.isHidden = note == nil
        notesListView.isHidden = true
        notesEditorView.isHidden = false
        view.window?.makeKey()
        view.window?.makeFirstResponder(note == nil ? titleField : bodyText)
    }

    private func closeEditor(save: Bool) {
        if save { saveDraftIfEditing() }
        editingNoteId = nil
        notesEditorView.isHidden = true
        notesListView.isHidden = false
    }

    /// Called on Save/back and when the drawer collapses, so typed text
    /// is never lost.
    func saveDraftIfEditing() {
        guard !notesEditorView.isHidden else { return }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyText.string
        if let id = editingNoteId {
            NotesStore.shared.update(id: id, title: title, body: body)
        } else if !title.isEmpty || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let note = NotesStore.shared.create(title: title, body: body)
            editingNoteId = note.id
        }
    }

    /// Sync UI that reflects external state (login item can change in
    /// System Settings behind our back).
    func drawerWillExpand() {
        refreshLoginPill()
        sysInfoLabel.stringValue = SysInfo.summary()
    }

    private func refreshLoginPill() {
        let enabled = SMAppService.mainApp.status == .enabled
        loginPill.isSelected = enabled
        loginPill.setTitle(enabled ? "✓ launches at login" : "launch at login")
    }

    func drawerWillCollapse() {
        saveDraftIfEditing()
        // Transient views reset to the cards for next open
        if let holder = recordOptionsHolder, !holder.isHidden { showRecordOptions(false) }
        if let holder = downloadsHolder, !holder.isHidden { showDownloads(false) }
        if let holder = alarmHolder, !holder.isHidden { showAlarms(false) }
    }

    private func emptyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = Theme.textTertiary
        return label
    }
}

// MARK: - Card cell (clips + notes lists)

final class RowCard: HoverView, NSDraggingSource {
    var onClick: (() -> Void)?
    /// When set, the card can be dragged out (into other apps/Finder).
    var dragProvider: (() -> NSPasteboardWriting?)?
    private let deleteButton = IconButton(symbol: "xmark", pointSize: 8)
    private let metaLabel = NSTextField(labelWithString: "")
    private var metaText = ""
    private var didDragOut = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.cardBg.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = Theme.hairline.cgColor
        onHoverChange = { [weak self] hovering in
            self?.layer?.backgroundColor = (hovering ? Theme.rowHover : Theme.cardBg).cgColor
            self?.deleteButton.isHidden = !hovering
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(content: NSView, meta: String, onDelete: @escaping () -> Void) {
        metaText = meta
        metaLabel.stringValue = meta
        metaLabel.font = Theme.mono(9)
        metaLabel.textColor = Theme.textTertiary
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isHidden = true
        deleteButton.onTap = onDelete
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(content)
        addSubview(metaLabel)
        addSubview(deleteButton)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            metaLabel.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 4),
            metaLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            metaLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            deleteButton.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            deleteButton.widthAnchor.constraint(equalToConstant: 18),
            deleteButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    func flash(_ text: String) {
        metaLabel.stringValue = text
        metaLabel.textColor = Theme.accent
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.metaLabel.stringValue = self.metaText
            self.metaLabel.textColor = Theme.textTertiary
        }
    }

    override func mouseDown(with event: NSEvent) {
        didDragOut = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDragOut, let writer = dragProvider?() else { return }
        didDragOut = true
        let item = NSDraggingItem(pasteboardWriter: writer)
        // Snapshot of the card as the drag image
        let snapshot = NSImage(data: dataWithPDF(inside: bounds))
        item.setDraggingFrame(bounds, contents: snapshot)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        // No fly-back shrink animation when the drag ends
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDragOut else { didDragOut = false; return }
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}
