import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    private var shelf: ShelfController?
    private lazy var settings = SettingsWindowController(store: store)
    private var timers: [Timer] = []
    private var showWhenReady = false

    func applicationDidFinishLaunching(_ note: Notification) {
        if AppMover.moveToApplicationsIfNeeded() { return }
        buildMainMenu()
        let shelf = ShelfController(store: store)
        shelf.onCopied = { [weak self] in self?.afterCopy() }
        shelf.onOpenSettings = { [weak self] in self?.showSettings() }
        self.shelf = shelf
        HotKey.register()

        let poll = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let shelf = self.shelf else { return }
                self.store.poll(windowVisible: shelf.window.isVisible)
            }
        }
        poll.tolerance = 0.2
        let expire = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.expire() }
        }
        expire.tolerance = 10
        for t in [poll, expire] { RunLoop.main.add(t, forMode: .common) }
        timers = [poll, expire]

        // First launch: open the shelf.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "shownOnce") {
            defaults.set(true, forKey: "shownOnce")
            defaults.set(false, forKey: "loginItemSetUp")
            showWhenReady = true
        } else if defaults.object(forKey: "loginItemSetUp") == nil {
            defaults.set(true, forKey: "loginItemSetUp")   // set up by an earlier version
        }
        // Start at login, since Copycat can only catch copies while running. This waits until the
        // app is in Applications, so the login item never points at a disk image or Downloads.
        // Turn it off in Settings or the Dock icon's menu.
        if !defaults.bool(forKey: "loginItemSetUp"), AppMover.isInApplications() {
            defaults.set(true, forKey: "loginItemSetUp")
            try? SMAppService.mainApp.register()
        }
        if showWhenReady { show() }
    }

    func applicationWillTerminate(_ note: Notification) {
        store.flush(wait: true)
    }

    func show() {
        guard let shelf else {
            showWhenReady = true
            return
        }
        store.unseen = 0
        shelf.reload()   // refresh "x min ago" labels
        shelf.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hotKeyPressed() {
        guard let shelf else { return }
        if NSApp.isActive && shelf.window.isVisible {
            NSApp.hide(nil)
        } else {
            show()
            shelf.focusForKeyboard()
        }
    }

    // After copying: flash "Copied", then hide so focus returns to the previous app,
    // and paste there if that's turned on in Settings.
    private func afterCopy() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            MainActor.assumeIsolated {
                NSApp.hide(nil)
                self.store.flashed = nil
                guard Preferences.autoPaste else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { AutoPaste.paste() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    // Behaves like a popover: clicking another app puts the shelf away.
    func applicationDidResignActive(_ note: Notification) {
        shelf?.window.orderOut(nil)
    }

    // Files dropped onto the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        store.addFiles(urls, kept: false)
        show()
    }

    // MARK: Dock menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let recent = store.ordered.prefix(12)
        if recent.isEmpty {
            menu.addItem(NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: ""))
        }
        for clip in recent {
            let flat = clip.title.replacingOccurrences(of: "\n", with: " ")
            let label = (clip.fromDevice ? "📱 " : clip.pinned ? "📌 " : "")
                + (flat.count > 48 ? flat.prefix(48) + "…" : flat)
            let item = menuItem(label, #selector(copyFromMenu(_:)))
            item.representedObject = clip.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Wipe Clipboard", #selector(wipeClipboard)))
        menu.addItem(menuItem("Pause Capturing", #selector(togglePause), on: store.paused))
        menu.addItem(menuItem("Open at Login", #selector(toggleLogin), on: LoginItem.isEnabled))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(showSettings)))
        menu.addItem(menuItem("About Copycat", #selector(showAbout)))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "", on: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let clip = store.clips.first(where: { $0.id == id }) else { return }
        store.copy([clip])
    }

    @objc private func wipeClipboard() { store.wipeClipboard() }

    @objc private func togglePause() { store.paused.toggle() }

    @objc private func toggleLogin() { LoginItem.set(!LoginItem.isEnabled) }

    @objc private func showSettings() { settings.show() }

    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: "Everything you copy on your Mac or iPhone, kept on a shelf.\nOpen it anytime with ⌃⌘V.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Main menu

    private func buildMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(menuItem("About Copycat", #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Settings…", #selector(showSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Copycat", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Copycat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(menuItem("Find", #selector(focusSearch), key: "f"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for sub in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = sub
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    @objc private func focusSearch() {
        shelf?.showSearch()
    }
}
