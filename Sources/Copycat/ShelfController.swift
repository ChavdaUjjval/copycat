import AppKit
import Combine
import Quartz
import SwiftUI

// MARK: - Table: keyboard, ⌘C and Quick Look

final class ShelfTable: NSTableView {
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}
    var onDelete: () -> Void = {}
    var onSpace: () -> Void = {}
    var onType: (String) -> Void = { _ in }
    weak var previewSource: (any QLPreviewPanelDataSource & QLPreviewPanelDelegate)?

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 36, 76: onReturn()   // Return, Enter
        case 53: onEscape()       // Esc
        case 51, 117: onDelete()  // Delete, Forward Delete
        case 49: onSpace()        // Space
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

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    // Quick Look calls these on the main thread.
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = previewSource
            panel.delegate = previewSource
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

// MARK: - Shelf window

@MainActor
final class ShelfController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate,
                             NSMenuDelegate, NSWindowDelegate {
    private enum Row {
        case header(String)
        case clip(Clip, shortcut: Int?)

        var clip: Clip? {
            if case .clip(let c, _) = self { return c }
            return nil
        }
    }

    let store: Store
    let window: NSWindow
    let search = NSSearchField()
    var onCopied: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    private let table = ShelfTable()
    private let filterBar = NSHostingView(rootView: FilterBar())
    private let emptyView = NSHostingView(rootView: EmptyState())
    private var filter = Filter.all
    private var rows: [Row] = []
    private var shownSelection = IndexSet()
    private var previewURLs: [URL] = []
    private var reloadScheduled = false
    private var subscriptions: Set<AnyCancellable> = []
    private var keyMonitor: Any?
    private let measurer = NSHostingController(rootView: ClipRow(clip: Clip()))
    private var heightCache: [String: CGFloat] = [:]

    init(store: Store) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Copycat"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 420)
        window.delegate = self
        buildUI()
        if !window.setFrameUsingName("CopycatWindow") { window.center() }
        window.setFrameAutosaveName("CopycatWindow")
        store.objectWillChange
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.setNeedsReload() } }
            .store(in: &subscriptions)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleShortcut(event) ?? false }
            return handled ? nil : event
        }
        reload()
    }

    private func buildUI() {
        search.placeholderString = "Search your clipboard"
        search.sendsSearchStringImmediately = true
        search.controlSize = .large
        search.target = self
        search.action = #selector(searchChanged)
        search.delegate = self

        let column = NSTableColumn(identifier: .init("clip"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 8)
        table.selectionHighlightStyle = .none
        table.allowsMultipleSelection = true
        table.floatsGroupRows = false
        table.focusRingType = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.previewSource = self
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.registerForDraggedTypes([.fileURL, .URL, .string, .rtf, .html, .png, .tiff]
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        table.onReturn = { [weak self] in self?.copySelection() }
        table.onEscape = { NSApp.hide(nil) }
        table.onDelete = { [weak self] in guard let self else { return }; self.store.remove(self.targetClips()) }
        table.onSpace = { [weak self] in self?.togglePreview() }
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
        scroll.contentInsets = NSEdgeInsets(top: 4, left: 4, bottom: 10, right: 4)

        let footer = NSHostingView(rootView: FooterBar(store: store, openSettings: { [weak self] in self?.onOpenSettings() }))
        let header = NSStackView(views: [search, filterBar])
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
            filterBar.widthAnchor.constraint(equalTo: header.widthAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -4),
            divider.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 7),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            emptyView.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyView.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor),
        ])
        window.contentView = content
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { store.undoManager }

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
        let selectedIDs = Set(table.selectedRowIndexes.compactMap { clip(at: $0)?.id })
        let all = store.ordered
        var counts: [Filter: Int] = [:]
        for f in Filter.allCases { counts[f] = all.filter(f.matches).count }
        let q = search.stringValue
        let matches = all.filter { filter.matches($0) && (q.isEmpty || $0.title.localizedCaseInsensitiveContains(q)) }
        rows = Self.sections(matches)

        table.reloadData()
        table.selectRowIndexes(IndexSet(rows.indices.filter { rows[$0].clip.map { selectedIDs.contains($0.id) } ?? false }),
                               byExtendingSelection: false)
        shownSelection = table.selectedRowIndexes
        filterBar.rootView = FilterBar(counts: counts, selected: filter) { [weak self] in self?.select($0) }
        filterBar.isHidden = all.isEmpty

        emptyView.isHidden = !rows.isEmpty
        emptyView.rootView = EmptyState(
            title: store.clips.isEmpty ? "Nothing on the shelf yet"
                : !q.isEmpty ? "No matches for “\(q)”" : "Nothing in \(filter.label) yet",
            showTips: store.clips.isEmpty)
    }

    // Pinned items, then Today / Yesterday / Earlier. Headers only appear when there's more than one group.
    private static func sections(_ clips: [Clip]) -> [Row] {
        let calendar = Calendar.current
        func section(_ c: Clip) -> String {
            if c.pinned { return "Pinned" }
            if calendar.isDateInToday(c.date) { return "Today" }
            if calendar.isDateInYesterday(c.date) { return "Yesterday" }
            return "Earlier"
        }
        let titles = clips.map(section)
        let showHeaders = Set(titles).count > 1
        var rows: [Row] = []
        for (i, clip) in clips.enumerated() {
            if showHeaders && (i == 0 || titles[i] != titles[i - 1]) { rows.append(.header(titles[i])) }
            rows.append(.clip(clip, shortcut: i < 9 ? i + 1 : nil))
        }
        return rows
    }

    private func clip(at row: Int) -> Clip? { row >= 0 && row < rows.count ? rows[row].clip : nil }

    private var firstClipRow: Int? { rows.firstIndex { $0.clip != nil } }

    private func select(_ newFilter: Filter) {
        filter = newFilter
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { rows[row].clip == nil }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].clip != nil }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        proposed.filteredIndexSet { clip(at: $0) != nil }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PlainRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let cell = tableView.makeView(withIdentifier: HeaderCell.identifier, owner: nil) as? HeaderCell ?? HeaderCell()
            cell.title = title
            return cell
        case .clip(let clip, let shortcut):
            let cell = tableView.makeView(withIdentifier: HostCell.identifier, owner: nil) as? HostCell ?? HostCell()
            cell.configure(ClipRow(clip: clip, shortcut: shortcut, flashed: store.flashed == clip.id,
                                   selected: tableView.selectedRowIndexes.contains(row)))
            let id = clip.id
            cell.onAction = { [weak self] action in self?.perform(action, on: id) }
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let clip = clip(at: row) else { return row == 0 ? 18 : 26 }
        let width = max(200, (tableView.tableColumns.first?.width ?? 400) - 16)
        let key = "\(clip.id)-\(clip.thumb?.count ?? 0)-\(clip.title.count)-\(clip.fromDevice)-\(Int(width))"
        if let h = heightCache[key] { return h }
        measurer.rootView = ClipRow(clip: clip, shortcut: 1)
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
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { refreshPreview() }
    }

    // Selected rows, or the right-clicked row if it isn't part of the selection.
    private func targetClips() -> [Clip] {
        let clicked = table.clickedRow
        if let c = clip(at: clicked), !table.selectedRowIndexes.contains(clicked) { return [c] }
        return table.selectedRowIndexes.compactMap(clip(at:))
    }

    // MARK: Actions

    @objc private func rowClicked() {
        guard let c = clip(at: table.clickedRow) else { return }
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        if mods.contains(.command) || mods.contains(.shift) { return }   // building a multi-selection
        copyAndHide([c])
    }

    private func perform(_ action: RowAction, on id: UUID) {
        guard let clip = store.clips.first(where: { $0.id == id }) else { return }
        switch action {
        case .pin: store.togglePin([clip])
        case .remove: store.remove([clip])
        case .preview:
            guard let row = rows.firstIndex(where: { $0.clip?.id == id }) else { return }
            window.makeFirstResponder(table)
            table.selectRowIndexes([row], byExtendingSelection: false)
            showPreview()
        }
    }

    private func copySelection() {
        var list = table.selectedRowIndexes.compactMap(clip(at:))
        if list.isEmpty, let first = firstClipRow.flatMap(clip(at:)) { list = [first] }
        copyAndHide(list)
    }

    private func copyAndHide(_ list: [Clip]) {
        guard !list.isEmpty else { return }
        store.copy(list)
        store.flashed = list[0].id
        onCopied()
    }

    // ⌘1…⌘9 copy the first nine items shown.
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard event.window === window,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let n = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(n),
              let c = rows.lazy.compactMap({ row -> Clip? in
                  if case .clip(let c, let s) = row, s == n { return c }
                  return nil
              }).first
        else { return false }
        copyAndHide([c])
        return true
    }

    @objc private func searchChanged() { reload() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            guard let first = firstClipRow else { return true }
            window.makeFirstResponder(table)
            if table.selectedRowIndexes.isEmpty { table.selectRowIndexes([first], byExtendingSelection: false) }
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
        if let first = firstClipRow {
            table.selectRowIndexes([first], byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
    }

    // MARK: Quick Look

    private func togglePreview() {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else {
            showPreview()
        }
    }

    private func showPreview() {
        refreshPreview()
        guard !previewURLs.isEmpty else { return }
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    private func refreshPreview() {
        previewURLs = table.selectedRowIndexes.compactMap(clip(at:)).compactMap(store.fileForClip)
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared().reloadData() }
    }

    // MARK: Right-click menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let list = targetClips()
        guard let first = list.first else { return }
        func add(_ title: String, _ action: Selector, symbol: String) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        let single = list.count == 1
        add(single ? "Copy" : "Copy \(list.count) Items", #selector(menuCopy), symbol: "doc.on.doc")
        if list.contains(where: { $0.text?.isEmpty == false }) {
            add("Copy as Plain Text", #selector(menuCopyPlain), symbol: "textformat")
        }
        if single, first.kind == .text { add("Edit Before Copying…", #selector(menuEdit), symbol: "pencil") }
        menu.addItem(.separator())
        if single { add("Preview", #selector(menuPreview), symbol: "eye") }
        if single, first.link != nil { add("Open Link", #selector(menuOpenLink), symbol: "safari") }
        if single, first.kind != .text, !first.files.isEmpty { add("Show in Finder", #selector(menuShowInFinder), symbol: "folder") }
        menu.addItem(.separator())
        add(list.allSatisfy(\.pinned) ? "Unpin" : "Pin to Top", #selector(menuPin), symbol: "pin")
        add(single ? "Remove from Shelf" : "Remove \(list.count) Items", #selector(menuRemove), symbol: "trash")
    }

    @objc private func menuCopy() { copyAndHide(targetClips()) }

    @objc private func menuCopyPlain() {
        store.copyPlainText(targetClips())
        store.flash(notice: "Copied as plain text")
    }

    @objc private func menuPin() { store.togglePin(targetClips()) }
    @objc private func menuRemove() { store.remove(targetClips()) }

    @objc private func menuPreview() {
        if let id = targetClips().first?.id { perform(.preview, on: id) }
    }

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
        clip(at: row).map(store.dragItem)
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

    // MARK: Screenshots

    // Shows a selected item and a hovered one, for `--screenshot`.
    func showDemoState() {
        let clipRows = rows.indices.filter { rows[$0].clip != nil }
        guard clipRows.count > 2 else { return }
        table.selectRowIndexes([clipRows[2]], byExtendingSelection: false)
        (table.view(atColumn: 0, row: clipRows[1], makeIfNecessary: true) as? HostCell)?.setHovered(true)
    }
}

// MARK: - Quick Look

extension ShelfController: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs[index] as NSURL
    }

    // Arrow keys and Space keep working while the preview is in front.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        table.keyDown(with: event)
        return true
    }
}
