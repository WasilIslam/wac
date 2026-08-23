import AppKit
import AVFoundation

// MARK: - Media library (screenshots + recordings on disk)

struct MediaItem {
    enum Kind { case screenshot, recording, audio, file }
    let url: URL
    let kind: Kind
    let date: Date
    let size: Int64

    var baseName: String { url.deletingPathExtension().lastPathComponent }
}

final class MediaStore {
    static let shared = MediaStore()

    let baseDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/wac", isDirectory: true)
    private var shotsDir: URL { baseDir.appendingPathComponent("screenshots", isDirectory: true) }
    private var recsDir: URL { baseDir.appendingPathComponent("recordings", isDirectory: true) }
    private var audioDir: URL { baseDir.appendingPathComponent("audio", isDirectory: true) }
    private var drawingsDir: URL { baseDir.appendingPathComponent("drawings", isDirectory: true) }

    func scan() -> [MediaItem] {
        var items: [MediaItem] = []
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        for (dir, kind) in [(shotsDir, MediaItem.Kind.screenshot), (recsDir, .recording),
                            (audioDir, .audio), (drawingsDir, .screenshot)] {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for url in urls {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                items.append(MediaItem(url: url, kind: kind, date: date,
                                       size: Int64(values?.fileSize ?? 0)))
            }
        }
        return items.sorted { $0.date > $1.date }
    }

    /// Newest first, grouped by calendar day ("Today", "Yesterday", "22 Aug 2026").
    func groupedByDay() -> [(String, [MediaItem])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        var groups: [(String, [MediaItem])] = []
        for item in scan() {
            let title: String
            if calendar.isDateInToday(item.date) { title = "Today" }
            else if calendar.isDateInYesterday(item.date) { title = "Yesterday" }
            else { title = formatter.string(from: item.date) }
            if groups.last?.0 == title {
                groups[groups.count - 1].1.append(item)
            } else {
                groups.append((title, [item]))
            }
        }
        return groups
    }

    /// Newest files in ~/Downloads (first access shows the standard macOS
    /// Downloads-folder permission prompt — at feature use, not at launch).
    func recentDownloads(limit: Int = 3) -> [MediaItem] {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey,
                                      .fileSizeKey, .isDirectoryKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var items: [MediaItem] = []
        for url in urls where url.pathExtension != "download" { // skip in-progress
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            let date = values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast
            items.append(MediaItem(url: url, kind: .file, date: date,
                                   size: Int64(values?.fileSize ?? 0)))
        }
        return Array(items.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Rename keeping the extension; avoids clobbering an existing file.
    func rename(_ item: MediaItem, to newBase: String) {
        let cleaned = newBase
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != item.baseName else { return }
        let ext = item.url.pathExtension
        var dest = item.url.deletingLastPathComponent()
            .appendingPathComponent(cleaned).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = item.url.deletingLastPathComponent()
                .appendingPathComponent("\(cleaned) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        try? FileManager.default.moveItem(at: item.url, to: dest)
    }

    func trash(_ item: MediaItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
    }
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

let mediaTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

// MARK: - Media cell (thumbnail + name + inline rename)

final class MediaCell: HoverView, NSTextFieldDelegate, NSDraggingSource {
    var onChanged: (() -> Void)?
    private let item: MediaItem
    private let thumb = NSImageView()
    private let nameLabel: NSTextField
    private let nameField = NSTextField()
    private let metaLabel: NSTextField
    private let renameButton = IconButton(symbol: "pencil", pointSize: 9)
    private let annotateButton: IconButton // paintbrush for images, scissors for videos
    private let deleteButton = IconButton(symbol: "xmark", pointSize: 8)
    private var didDragOut = false

    init(item: MediaItem) {
        self.item = item
        annotateButton = IconButton(symbol: item.kind == .recording ? "scissors" : "paintbrush.pointed",
                                    pointSize: 9)
        nameLabel = NSTextField(labelWithString: item.baseName)
        let tag: String
        switch item.kind {
        case .screenshot: tag = ""
        case .recording: tag = " · video"
        case .audio: tag = " · audio"
        case .file: tag = " · download"
        }
        metaLabel = NSTextField(labelWithString:
            "\(mediaTimeFormatter.string(from: item.date)) · \(formatBytes(item.size))\(tag)")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.cardBg.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = Theme.hairline.cgColor

        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = Theme.cardBg.cgColor
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.translatesAutoresizingMaskIntoConstraints = false
        loadThumbnail()

        nameLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        nameField.font = .systemFont(ofSize: 11.5, weight: .semibold)
        nameField.textColor = Theme.textPrimary
        nameField.isBordered = false
        nameField.drawsBackground = true
        nameField.backgroundColor = Theme.fieldBg
        nameField.focusRingType = .none
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(commitRename)
        nameField.isHidden = true
        nameField.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.font = Theme.mono(8.5)
        metaLabel.textColor = Theme.textTertiary
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        renameButton.isHidden = true
        renameButton.onTap = { [weak self] in self?.beginRename() }
        renameButton.translatesAutoresizingMaskIntoConstraints = false
        annotateButton.isHidden = true
        annotateButton.onTap = { [weak self] in
            guard let self else { return }
            if self.item.kind == .recording {
                VideoEditor.shared.open(fileURL: self.item.url)
            } else {
                Annotator.shared.open(fileURL: self.item.url)
            }
        }
        annotateButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isHidden = true
        deleteButton.onTap = { [weak self] in
            guard let self else { return }
            MediaStore.shared.trash(self.item)
            Toast.show("moved to trash")
            self.onChanged?()
        }
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(thumb)
        addSubview(nameLabel)
        addSubview(nameField)
        addSubview(metaLabel)
        addSubview(annotateButton)
        addSubview(renameButton)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            thumb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumb.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 34),
            thumb.heightAnchor.constraint(equalToConstant: 34),

            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 9),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: renameButton.leadingAnchor, constant: -6),

            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: renameButton.leadingAnchor, constant: -6),

            metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),

            annotateButton.trailingAnchor.constraint(equalTo: renameButton.leadingAnchor, constant: -2),
            annotateButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            annotateButton.widthAnchor.constraint(equalToConstant: 20),
            annotateButton.heightAnchor.constraint(equalToConstant: 20),
            renameButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -2),
            renameButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            renameButton.widthAnchor.constraint(equalToConstant: 20),
            renameButton.heightAnchor.constraint(equalToConstant: 20),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),
        ])

        onHoverChange = { [weak self] hovering in
            guard let self else { return }
            self.layer?.backgroundColor = (hovering ? Theme.rowHover : Theme.cardBg).cgColor
            let editing = !self.nameField.isHidden
            self.renameButton.isHidden = !hovering || editing
            self.deleteButton.isHidden = !hovering || editing
            let editable = self.item.kind == .screenshot || self.item.kind == .recording
            self.annotateButton.isHidden = !hovering || editing || !editable
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func loadThumbnail() {
        switch item.kind {
        case .screenshot:
            thumb.image = NSImage(contentsOf: item.url)
        case .file:
            thumb.image = NSWorkspace.shared.icon(forFile: item.url.path)
        case .audio:
            thumb.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "audio")?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            thumb.contentTintColor = Theme.accent
        case .recording:
            // Placeholder while the first video frame renders
            thumb.image = NSImage(systemSymbolName: "film", accessibilityDescription: "video")?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            thumb.contentTintColor = Theme.textSecondary
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: item.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 120)
            generator.generateCGImageAsynchronously(for: CMTime(seconds: 0.1, preferredTimescale: 600)) {
                [weak self] cgImage, _, _ in
                guard let cgImage else { return }
                DispatchQueue.main.async {
                    self?.thumb.image = NSImage(cgImage: cgImage,
                                                size: NSSize(width: cgImage.width, height: cgImage.height))
                }
            }
        }
    }

    // MARK: Rename

    private func beginRename() {
        nameField.stringValue = item.baseName
        nameField.isHidden = false
        nameLabel.isHidden = true
        renameButton.isHidden = true
        deleteButton.isHidden = true
        window?.makeKey()
        window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    @objc private func commitRename() {
        window?.makeFirstResponder(nil) // triggers controlTextDidEndEditing
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !nameField.isHidden else { return }
        nameField.isHidden = true
        nameLabel.isHidden = false
        let newBase = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newBase.isEmpty, newBase != item.baseName {
            MediaStore.shared.rename(item, to: newBase)
            Toast.show("renamed ✓")
        }
        onChanged?()
    }

    // MARK: Drag out of the drawer (into Finder, Slack, mail, …)

    override func mouseDown(with event: NSEvent) {
        didDragOut = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard nameField.isHidden, !didDragOut else { return }
        didDragOut = true
        let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let dragImage = thumb.image ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil)!
        draggingItem.setDraggingFrame(thumb.frame, contents: dragImage)
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false // no fly-back shrink
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func mouseUp(with event: NSEvent) {
        guard nameField.isHidden, !didDragOut else { return }
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            NSWorkspace.shared.open(item.url)
        }
    }
}
