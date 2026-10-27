import AppKit
import Combine
import SwiftUI

// MARK: - Table: keyboard and ⌘C

final class ShelfTable: NSTableView {
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}
    var onDelete: () -> Void = {}
    var onType: (String) -> Void = { _ in }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 36, 76: onReturn()   // Return, Enter
        case 53: onEscape()       // Esc
        case 51, 117: onDelete()  // Delete, Forward Delete
        default:
            if mods.isEmpty, let chars = event.characters, !chars.isEmpty,
               chars.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) {
                onType(chars)     // start typing to search
            } else {
                super.keyDown(with: event)
            }
        }
    }

    @objc func copy(_ sender: Any?) { onReturn() }
}

// MARK: - Filters

enum Filter: Int, CaseIterable {
    case all, text, media, files, iPhone

    var label: String { ["All", "Text", "Media", "Files", "iPhone"][rawValue] }
    var symbol: String { ["square.grid.2x2", "text.alignleft", "photo", "doc", "iphone"][rawValue] }

    func matches(_ c: Clip) -> Bool {
        switch self {
        case .all: return true
        case .text: return c.kind == .text
        case .media: return c.kind == .media
        case .files: return c.kind == .files
        case .iPhone: return c.fromDevice
        }
    }
}

// MARK: - Shelf window

@MainActor
final class ShelfController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    let store: Store
    let window: NSWindow
    let search = NSSearchField()
    var onCopied: () -> Void = {}

    private let table = ShelfTable()
    private let filterControl = NSSegmentedControl()
    private let noticeLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyView = NSStackView()
    private var rows: [Clip] = []
    private var shownSelection = IndexSet()
    private var reloadScheduled = false
    private var subscriptions: Set<AnyCancellable> = []
    private let measurer = NSHostingController(rootView: ClipRow(clip: Clip(), flashed: false, selected: false))
    private var heightCache: [String: CGFloat] = [:]

    init(store: Store) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Copycat"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 340, height: 380)
        buildUI()
        if !window.setFrameUsingName("CopycatWindow") { window.center() }
        window.setFrameAutosaveName("CopycatWindow")
        store.objectWillChange
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.setNeedsReload() } }
            .store(in: &subscriptions)
        reload()
    }

    private func buildUI() {
        search.placeholderString = "Search"
        search.sendsSearchStringImmediately = true
        search.controlSize = .large
        search.target = self
        search.action = #selector(searchChanged)
        search.delegate = self

        filterControl.segmentCount = Filter.allCases.count
        filterControl.trackingMode = .selectOne
        for filter in Filter.allCases {
            let i = filter.rawValue
            filterControl.setLabel(filter.label, forSegment: i)
            filterControl.setImage(NSImage(systemSymbolName: filter.symbol, accessibilityDescription: filter.label), forSegment: i)
            filterControl.setImageScaling(.scaleProportionallyDown, forSegment: i)
        }
        filterControl.selectedSegment = Filter.all.rawValue
        filterControl.segmentDistribution = .fillEqually
        filterControl.target = self
        filterControl.action = #selector(filterChanged)

        let column = NSTableColumn(identifier: .init("clip"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 8)
        table.selectionHighlightStyle = .none
        table.allowsMultipleSelection = true
        table.focusRingType = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.registerForDraggedTypes([.fileURL, .URL, .string, .rtf, .html, .png, .tiff]
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        table.onReturn = { [weak self] in self?.copySelection() }
        table.onEscape = { NSApp.hide(nil) }
        table.onDelete = { [weak self] in guard let self else { return }; self.store.remove(self.targetClips()) }
        table.onType = { [weak self] chars in
            guard let self else { return }
            self.window.makeFirstResponder(self.search)
            self.search.currentEditor()?.insertText(chars)
            self.reload()
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 10, left: 4, bottom: 10, right: 4)

        // Empty state
        let emptyIcon = NSImageView()
        emptyIcon.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: nil)
        emptyIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .light)
        emptyIcon.contentTintColor = .tertiaryLabelColor
        emptyTitle.font = .systemFont(ofSize: 13, weight: .medium)
        emptyTitle.textColor = .secondaryLabelColor
        let emptyHint = NSTextField(wrappingLabelWithString: "Copy on your Mac or iPhone, or drop text, photos and videos here.")
        emptyHint.font = .systemFont(ofSize: 11)
        emptyHint.textColor = .tertiaryLabelColor
        emptyHint.alignment = .center
        emptyHint.preferredMaxLayoutWidth = 240
        for v in [emptyIcon, emptyTitle, emptyHint] { emptyView.addArrangedSubview(v) }
        emptyView.orientation = .vertical
        emptyView.alignment = .centerX
        emptyView.spacing = 6

        // Footer: item count · hints / notices · Wipe Clipboard
        let wipe = NSButton(title: "Wipe Clipboard", target: self, action: #selector(wipeClipboard))
        wipe.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: nil)
        wipe.imagePosition = .imageLeading
        wipe.bezelStyle = .push
        wipe.controlSize = .small
        wipe.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        wipe.toolTip = "Empty the Mac's clipboard and the shelf (pinned items stay)"
        for label in [countLabel, noticeLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        noticeLabel.alignment = .center
        noticeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [countLabel, noticeLabel, wipe])
        footer.distribution = .fill
        footer.spacing = 8

        let header = NSStackView(views: [search, filterControl])
        header.orientation = .vertical
        header.spacing = 10
        header.alignment = .leading

        let divider = NSBox()
        divider.boxType = .separator

        // Translucent window background, like Control Center and Spotlight.
        let content = NSVisualEffectView()
        content.material = .sidebar
        content.blendingMode = .behindWindow
        content.state = .followsWindowActiveState
        for v in [header, scroll, divider, footer, emptyView] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            search.widthAnchor.constraint(equalTo: header.widthAnchor),
            filterControl.widthAnchor.constraint(equalTo: header.widthAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -4),
            divider.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            emptyView.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyView.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor, constant: -40),
        ])
        window.contentView = content
    }

    // MARK: Data

    // Several store changes in a row (copy, flash, save) reload the table once.
    private func setNeedsReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.reloadScheduled = false
                self.reload()
            }
        }
    }

    func reload() {
        let selectedIDs = Set(table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].id : nil })
        let filter = Filter(rawValue: filterControl.selectedSegment) ?? .all
        let q = search.stringValue
        rows = store.ordered.filter { filter.matches($0) && (q.isEmpty || $0.title.localizedCaseInsensitiveContains(q)) }
        table.reloadData()
        table.selectRowIndexes(IndexSet(rows.indices.filter { selectedIDs.contains(rows[$0].id) }), byExtendingSelection: false)
        shownSelection = table.selectedRowIndexes
        emptyView.isHidden = !rows.isEmpty
        emptyTitle.stringValue = store.clips.isEmpty ? "Nothing on the shelf yet"
            : !q.isEmpty ? "No matches for “\(q)”" : "Nothing here yet"
        let n = store.clips.count
        countLabel.stringValue = n == 1 ? "1 item" : "\(n) items"
        noticeLabel.stringValue = store.notice ?? (store.paused ? "Capturing paused" : "⏎ copy · drag to share · ⌃⌘V")
        noticeLabel.textColor = store.notice != nil ? .systemGreen : store.paused ? .systemOrange : .tertiaryLabelColor
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: HostCell.identifier, owner: nil) as? HostCell ?? HostCell()
        let clip = rows[row]
        cell.host.rootView = ClipRow(clip: clip, flashed: store.flashed == clip.id,
                                     selected: tableView.selectedRowIndexes.contains(row))
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let clip = rows[row]
        let width = max(200, (tableView.tableColumns.first?.width ?? 380) - 16)
        let key = "\(clip.id)-\(clip.thumb?.count ?? 0)-\(clip.title.count)-\(clip.fromDevice)-\(Int(width))"
        if let h = heightCache[key] { return h }
        measurer.rootView = ClipRow(clip: clip, flashed: false, selected: false)
        let h = ceil(measurer.sizeThatFits(in: CGSize(width: width, height: 10_000)).height)
        heightCache[key] = h
        return h
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        heightCache.removeAll()
        table.noteHeightOfRows(withIndexesChanged: IndexSet(rows.indices))
    }

    // Redraws only the rows whose selection changed.
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selection = table.selectedRowIndexes
        let changed = shownSelection.symmetricDifference(selection).filteredIndexSet { $0 < rows.count }
        shownSelection = selection
        if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: [0]) }
    }

    // Selected rows, or the right-clicked row if it isn't part of the selection.
    private func targetClips() -> [Clip] {
        let clicked = table.clickedRow
        if clicked >= 0 && clicked < rows.count && !table.selectedRowIndexes.contains(clicked) {
            return [rows[clicked]]
        }
        return table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0] : nil }
    }

    // MARK: Actions

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard row >= 0, row < rows.count else { return }
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        if mods.contains(.command) || mods.contains(.shift) { return }   // building a multi-selection
        copyAndHide([rows[row]])
    }

    private func copySelection() {
        var list = table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0] : nil }
        if list.isEmpty, let first = rows.first { list = [first] }
        copyAndHide(list)
    }

    private func copyAndHide(_ list: [Clip]) {
        guard !list.isEmpty else { return }
        store.copy(list)
        store.flashed = list[0].id
        onCopied()
    }

    @objc private func searchChanged() { reload() }
    @objc private func filterChanged() { reload() }
    @objc private func wipeClipboard() { store.wipeClipboard() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            guard !rows.isEmpty else { return true }
            window.makeFirstResponder(table)
            if table.selectedRowIndexes.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            copySelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if search.stringValue.isEmpty { NSApp.hide(nil) } else { search.stringValue = ""; reload() }
            return true
        default:
            return false
        }
    }

    func focusForKeyboard() {
        search.stringValue = ""
        reload()
        window.makeFirstResponder(table)
        if !rows.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
    }

    // MARK: Right-click menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let list = targetClips()
        guard let first = list.first else { return }
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let single = list.count == 1
        add(single ? "Copy" : "Copy \(list.count) Items", #selector(menuCopy))
        if list.contains(where: { $0.text?.isEmpty == false }) { add("Copy as Plain Text", #selector(menuCopyPlain)) }
        if single, first.kind == .text { add("Edit Before Copying…", #selector(menuEdit)) }
        if single, first.link != nil { add("Open Link", #selector(menuOpenLink)) }
        if single, first.kind != .text, !first.files.isEmpty { add("Show in Finder", #selector(menuShowInFinder)) }
        menu.addItem(.separator())
        add(list.allSatisfy(\.pinned) ? "Unpin" : "Pin to Top", #selector(menuPin))
        add(single ? "Remove from Shelf" : "Remove \(list.count) Items", #selector(menuRemove))
    }

    @objc private func menuCopy() { copyAndHide(targetClips()) }

    @objc private func menuCopyPlain() {
        store.copyPlainText(targetClips())
        store.flash(notice: "Copied as plain text")
    }

    @objc private func menuPin() { store.togglePin(targetClips()) }
    @objc private func menuRemove() { store.remove(targetClips()) }

    @objc private func menuOpenLink() {
        if let url = targetClips().first?.link { NSWorkspace.shared.open(url) }
    }

    @objc private func menuShowInFinder() {
        if let clip = targetClips().first, let url = store.fileForClip(clip) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func menuEdit() {
        guard let clip = targetClips().first else { return }
        let alert = NSAlert()
        alert.messageText = "Edit before copying"
        alert.informativeText = "Saving replaces this item on the shelf with your edited text."
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 380, height: 200)
        scroll.borderType = .bezelBorder
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.string = clip.text ?? ""
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = textView
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn,
              let updated = store.updateText(clip, to: textView.string) else { return }
        if response == .alertFirstButtonReturn { copyAndHide([updated]) }
    }

    // MARK: Drag out

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        store.dragItem(for: rows[row])
    }

    // MARK: Drag in

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if (info.draggingSource as? NSTableView) === table { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let pb = info.draggingPasteboard
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty, let promises = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !promises.isEmpty {
            store.receive(promises)
            return true
        }
        guard let clip = Clip.capture(pb) else { return false }
        store.add(clip, countUnseen: false)
        store.flash(notice: "Added to shelf")
        return true
    }
}
