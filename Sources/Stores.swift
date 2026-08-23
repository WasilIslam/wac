import AppKit

// MARK: - Clipboard history

struct ClipItem: Codable {
    enum Kind: String, Codable { case text, image }
    let id: String
    let kind: Kind
    var text: String?
    var imageFile: String? // filename inside clips/
    var hash: Int
    let date: Date
}

final class ClipboardStore {
    static let shared = ClipboardStore()
    private(set) var items: [ClipItem] = []
    var onChange: (() -> Void)?

    static let maxItems = 100
    /// Marker type stamped on pasteboard writes that wac itself makes,
    /// so re-copying a clip doesn't re-add it to history.
    private let internalType = NSPasteboard.PasteboardType("com.cuthours.wac.internal")

    private let jsonURL = wacDataDirectory().appendingPathComponent("clipboard.json")
    private let clipsDir: URL = {
        let dir = wacDataDirectory().appendingPathComponent("clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    private init() { load() }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard pb.types?.contains(internalType) != true else { return } // our own write

        // Prefer image content, fall back to text
        if let png = pngData(from: pb) {
            let hash = png.hashValue
            if let first = items.first, first.kind == .image, first.hash == hash { return }
            let id = UUID().uuidString
            let filename = "\(id).png"
            try? png.write(to: clipsDir.appendingPathComponent(filename))
            insert(ClipItem(id: id, kind: .image, text: nil, imageFile: filename, hash: hash, date: Date()))
        } else if let string = pb.string(forType: .string),
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hash = string.hashValue
            if let first = items.first, first.kind == .text, first.hash == hash { return }
            insert(ClipItem(id: UUID().uuidString, kind: .text, text: string, imageFile: nil,
                            hash: hash, date: Date()))
        }
    }

    /// Extract PNG data from whatever image form the pasteboard holds:
    /// raw tiff/png (browsers, screenshots-to-clipboard) or copied image
    /// FILES (Finder), which arrive as file URLs, not bitmap data.
    private func pngData(from pb: NSPasteboard) -> Data? {
        var image: NSImage?
        if pb.data(forType: .tiff) != nil || pb.data(forType: .png) != nil {
            image = NSImage(pasteboard: pb)
        } else if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL],
                  let url = urls.first,
                  ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"]
                      .contains(url.pathExtension.lowercased()) {
            image = NSImage(contentsOf: url)
        }
        guard let tiff = image?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func insert(_ item: ClipItem) {
        items.insert(item, at: 0)
        while items.count > Self.maxItems {
            let dropped = items.removeLast()
            removeFile(of: dropped)
        }
        save()
        onChange?()
    }

    func imageURL(for item: ClipItem) -> URL? {
        guard let file = item.imageFile else { return nil }
        return clipsDir.appendingPathComponent(file)
    }

    func copyToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.declareTypes([.string, internalType], owner: nil)
            pb.setString(item.text ?? "", forType: .string)
            pb.setString("1", forType: internalType)
        case .image:
            // writeObjects publishes every representation apps expect
            // (TIFF and friends) — raw PNG-only data makes many apps beep.
            guard let url = imageURL(for: item), let image = NSImage(contentsOf: url) else { return }
            pb.writeObjects([image])
            pb.addTypes([internalType], owner: nil)
            pb.setString("1", forType: internalType)
        }
        lastChangeCount = pb.changeCount
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        removeFile(of: item)
        save()
        onChange?()
    }

    func clearAll() {
        for item in items { removeFile(of: item) }
        items.removeAll()
        save()
        onChange?()
    }

    private func removeFile(of item: ClipItem) {
        if let url = imageURL(for: item) { try? FileManager.default.removeItem(at: url) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: jsonURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([ClipItem].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) { try? data.write(to: jsonURL) }
    }
}

// MARK: - Notes

struct Note: Codable {
    let id: String
    var title: String
    var body: String
    let created: Date
    var modified: Date
}

final class NotesStore {
    static let shared = NotesStore()
    private(set) var items: [Note] = []
    var onChange: (() -> Void)?

    private let jsonURL = wacDataDirectory().appendingPathComponent("notes.json")

    private init() { load() }

    @discardableResult
    func create(title: String, body: String) -> Note {
        let note = Note(id: UUID().uuidString, title: title, body: body, created: Date(), modified: Date())
        items.insert(note, at: 0)
        save()
        onChange?()
        return note
    }

    func update(id: String, title: String, body: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = title
        items[index].body = body
        items[index].modified = Date()
        // Most-recently-edited first
        let note = items.remove(at: index)
        items.insert(note, at: 0)
        save()
        onChange?()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        save()
        onChange?()
    }

    private func load() {
        guard let data = try? Data(contentsOf: jsonURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([Note].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) { try? data.write(to: jsonURL) }
    }
}

// MARK: - Shared date formatting

let clipDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM, HH:mm"
    return formatter
}()
