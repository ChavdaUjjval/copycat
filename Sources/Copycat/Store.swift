import AppKit
import Combine
import os
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
final class Store: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    @Published var flashed: UUID?
    @Published var paused = false
    @Published private(set) var notice: String?
    @Published private(set) var canUndo = false
    var unseen = 0 { didSet { updateBadge() } }
    let undoManager = UndoManager()
    let pasteboard: NSPasteboard

    private let persistent: Bool
    private var lastChangeCount: Int
    private var receiving: Set<UUID> = []   // clips whose dropped files are still arriving
    private var undoable: Set<UUID> = []    // removed clips whose files are kept while they can be restored
    private var undoExpiry: DispatchWorkItem?
    private var noticeExpiry: DispatchWorkItem?
    private var saveScheduled = false
    private let writer = DispatchQueue(label: "Copycat.store", qos: .utility)
    private let promiseQueue = OperationQueue()

    init() {
        persistent = true
        pasteboard = .general
        lastChangeCount = pasteboard.changeCount
        load()
        expire()
    }

    // A shelf with the given clips that is never read from or written to disk, and copies to a
    // private pasteboard instead of the Mac's clipboard.
    init(demo clips: [Clip]) {
        persistent = false
        pasteboard = .withUniqueName()
        lastChangeCount = pasteboard.changeCount
        self.clips = clips
    }

    var ordered: [Clip] { clips.filter(\.pinned) + clips.filter { !$0.pinned } }

    // MARK: Capturing

    func poll(windowVisible: Bool) {
        let pb = pasteboard
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard !paused, var clip = Clip.capture(pb) else { return }
        if !clip.fromDevice, let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           app != Bundle.main.bundleIdentifier {
            clip.sourceApp = app
        }
        add(clip, countUnseen: !windowVisible)
    }

    func add(_ clip: Clip, countUnseen: Bool) {
        var entry = clip
        if let i = clips.firstIndex(where: { $0.key == clip.key }) {
            entry = clips.remove(at: i)
            entry.date = Date()
            entry.fromDevice = entry.fromDevice || clip.fromDevice
            if entry.thumb == nil { entry.thumb = clip.thumb }
        }
        clips.insert(entry, at: 0)
        if countUnseen { unseen += 1 }
        trim()
        save()
        makeFileThumbnail(for: entry)
    }

    // Saves files as a clip: files dropped onto the Dock icon (kept where they are),
    // or photos dragged in from apps like Photos (already received into the shelf's storage).
    func addFiles(_ urls: [URL], id: UUID = UUID(), kept: Bool) {
        guard !urls.isEmpty else { return }
        var clip = Clip(id: id)
        clip.payload = urls.map { [PasteboardTypes.fileURL: Data($0.absoluteString.utf8)] }
        clip.files = urls.map(\.lastPathComponent)
        clip.key = Clip.fileKey(urls)
        if kept { clip.keptBytes = urls.reduce(0) { $0 + min($1.fileSize, Limits.keptFileBytes) } }
        clip.attachImageData()
        add(clip, countUnseen: false)
        flash(notice: urls.count == 1 ? "Added to shelf" : "Added \(urls.count) items")
    }

    // Photos and some other apps hand over dragged pictures as "promised" files written on request.
    func receive(_ promises: [NSFilePromiseReceiver]) {
        let id = UUID()
        let dir = Storage.keptFiles.appendingPathComponent(id.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        receiving.insert(id)
        let group = DispatchGroup()
        let received = OSAllocatedUnfairLock(initialState: [URL]())
        for promise in promises {
            for _ in promise.fileNames { group.enter() }
            promise.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: promiseQueue) { url, error in
                if error == nil { received.withLock { $0.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                self.receiving.remove(id)
                self.addFiles(received.withLock { $0 }, id: id, kept: true)
            }
        }
    }

    // Video frames, PDF pages and other file previews, generated in the background.
    private func makeFileThumbnail(for clip: Clip) {
        guard clip.thumb == nil, let url = clip.fileURLs.first,
              FileManager.default.fileExists(atPath: url.path) else { return }
        let side = CGFloat(Images.thumbnailSize / 2)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: 2, representationTypes: .thumbnail)
        let id = clip.id
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let thumb = rep.flatMap({ Images.png($0.cgImage) }) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let i = self.clips.firstIndex(where: { $0.id == id }) else { return }
                    self.clips[i].thumb = thumb
                    self.save()
                }
            }
        }
    }

    // MARK: Copying

    func copy(_ list: [Clip]) {
        guard !list.isEmpty else { return }
        let pb = pasteboard
        pb.clearContents()
        if list.count > 1 && list.allSatisfy({ $0.kind == .text }) {
            pb.setString(list.compactMap(\.text).joined(separator: "\n"), forType: .string)
        } else {
            pb.writeObjects(list.flatMap { Self.writable($0).map(Self.pasteboardItem) })
        }
        lastChangeCount = pb.changeCount
        if list.count == 1, let i = clips.firstIndex(where: { $0.id == list[0].id }) {
            var c = clips.remove(at: i)
            c.date = Date()
            clips.insert(c, at: 0)
            save()
        }
    }

    func copyPlainText(_ list: [Clip]) {
        let text = list.compactMap(\.text).joined(separator: "\n")
        guard !text.isEmpty else { return }
        let pb = pasteboard
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
    }

    // Empties the Mac's clipboard and the shelf. Pinned items stay, since pinning means "keep this".
    func wipeClipboard() {
        pasteboard.clearContents()
        lastChangeCount = pasteboard.changeCount
        let removed = clips.filter { !$0.pinned }
        clips.removeAll { !$0.pinned }
        unseen = 0
        save()
        offerUndo(removed, notice: "Clipboard wiped")
    }

    func flash(notice text: String, seconds: Double = 1.5) {
        notice = text
        noticeExpiry?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { self.notice = nil } }
        noticeExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Undo

    // Removed items can be put back for a few seconds, from the footer or with ⌘Z.
    private func offerUndo(_ removed: [Clip], notice text: String) {
        guard !removed.isEmpty else { return }
        undoManager.removeAllActions(withTarget: self)
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restore(removed) }
        }
        undoManager.setActionName(text)
        undoable = Set(removed.map(\.id))
        canUndo = true
        flash(notice: text, seconds: 8)
        undoExpiry?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { self.dropUndo() } }
        undoExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func undo() {
        if undoManager.canUndo { undoManager.undo() }
    }

    private func restore(_ removed: [Clip]) {
        let present = Set(clips.map(\.id))
        clips += removed.filter { !present.contains($0.id) }
        clips.sort { $0.date > $1.date }
        dropUndo()
        flash(notice: removed.count == 1 ? "Item restored" : "\(removed.count) items restored")
    }

    private func dropUndo() {
        undoExpiry?.cancel()
        undoManager.removeAllActions(withTarget: self)
        undoable = []
        canUndo = false
        save()
    }

    private static func pasteboardItem(_ dict: [String: Data]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (t, d) in dict { item.setData(d, forType: NSPasteboard.PasteboardType(t)) }
        return item
    }

    // Text goes out without its RTFD version: Messages, Finder and others would otherwise
    // turn it into an .rtfd attachment instead of text.
    private static func writable(_ clip: Clip) -> [[String: Data]] {
        guard clip.kind == .text else { return clip.payload }
        return clip.payload.map { dict in
            dict[PasteboardTypes.plainText] == nil ? dict : dict.filter { !PasteboardTypes.rtfd.contains($0.key) }
        }
    }

    // MARK: Editing

    func updateText(_ clip: Clip, to text: String) -> Clip? {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return nil }
        clips[i].text = text
        clips[i].payload = [[PasteboardTypes.plainText: Data(text.utf8)]]
        clips[i].key = "t:" + text
        save()
        return clips[i]
    }

    func togglePin(_ list: [Clip]) {
        let pin = !list.allSatisfy(\.pinned)
        for c in list { if let i = clips.firstIndex(where: { $0.id == c.id }) { clips[i].pinned = pin } }
        save()
    }

    func remove(_ list: [Clip]) {
        let ids = Set(list.map(\.id))
        let removed = clips.filter { ids.contains($0.id) }
        clips.removeAll { ids.contains($0.id) }
        save()
        offerUndo(removed, notice: removed.count == 1 ? "Item removed" : "\(removed.count) items removed")
    }

    // Removes everything, pinned items included.
    func clearAll() {
        clips.removeAll()
        unseen = 0
        dropUndo()
        flash(notice: "History cleared")
    }

    func expire() {
        let hours = Preferences.keepHours
        guard hours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let before = clips.count
        clips.removeAll { !$0.pinned && $0.date < cutoff }
        if clips.count != before { save() }
    }

    // Applies changed settings right away rather than at the next copy.
    func applyPreferences() {
        expire()
        let before = clips.count
        trim()
        if clips.count != before { save() }
        updateBadge()
    }

    private func updateBadge() {
        NSApp.dockTile.badgeLabel = unseen > 0 && Preferences.showBadge ? "\(unseen)" : nil
    }

    // MARK: Files for drag-out

    // A real file for the clip: the file itself, or the image/text written out to the shelf's storage.
    func fileForClip(_ clip: Clip) -> URL? {
        if !clip.files.isEmpty {
            return clip.fileURLs.first { FileManager.default.fileExists(atPath: $0.path) }
        }
        let stamp = Self.stampFormatter.string(from: clip.date)
        let name: String, data: Data
        if let image = clip.imageData {
            name = "Clip \(stamp).\(UTType(image.type)?.preferredFilenameExtension ?? "png")"
            data = image.data
        } else if let t = clip.text {
            name = "Clip \(stamp).txt"
            data = Data(t.utf8)
        } else {
            return nil
        }
        let dir = Storage.exports.appendingPathComponent(clip.id.uuidString)
        let url = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return url
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    // What gets dragged out of the shelf: text stays text; photos, videos and files go as real files.
    func dragItem(for clip: Clip) -> NSPasteboardItem {
        if clip.kind == .text {
            return Self.pasteboardItem(Self.writable(clip).first ?? [:])
        }
        let item = NSPasteboardItem()
        if let url = fileForClip(clip) { item.setString(url.absoluteString, forType: .fileURL) }
        if let image = clip.imageData { item.setData(image.data, forType: NSPasteboard.PasteboardType(image.type)) }
        return item
    }

    // MARK: Persistence

    private func trim() {
        var unpinned = 0, total = 0
        clips = clips.filter { c in
            total += c.bytes
            if c.pinned { return true }
            unpinned += 1
            return unpinned <= Preferences.maxItems && total <= Limits.storeBytes
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Storage.history),
              var saved = try? PropertyListDecoder().decode([Clip].self, from: data) else { return }
        for i in saved.indices { saved[i].normalize() }
        clips = saved
    }

    // Changes are batched and written in the background, so a burst of edits costs one write.
    private func save() {
        guard persistent, !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated { self.flush() }
        }
    }

    // Writes any pending changes; `wait` blocks until they're on disk (used when quitting).
    func flush(wait: Bool = false) {
        guard saveScheduled else { return }
        saveScheduled = false
        removeOrphanedFiles()
        let snapshot = clips
        if wait {
            writer.sync { Self.write(snapshot) }
        } else {
            writer.async { Self.write(snapshot) }
        }
    }

    nonisolated private static func write(_ clips: [Clip]) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(clips) else { return }
        try? data.write(to: Storage.history, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Storage.history.path)
    }

    // Deletes stored files whose clip is no longer on the shelf.
    private func removeOrphanedFiles() {
        let live = Set((clips.map(\.id) + receiving + undoable).map(\.uuidString))
        let fm = FileManager.default
        for base in [Storage.keptFiles, Storage.exports] {
            for name in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] where !live.contains(name) {
                try? fm.removeItem(at: base.appendingPathComponent(name))
            }
        }
    }
}
