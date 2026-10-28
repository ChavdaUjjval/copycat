import AppKit
import ApplicationServices
import Carbon
import ServiceManagement
import SwiftUI

enum Preferences {
    static let keepHoursKey = "keepHours"          // 0 keeps items until they're removed
    static let maxItemsKey = "maxItems"            // unpinned items kept on the shelf
    static let autoPasteKey = "pasteAfterChoosing"
    static let showBadgeKey = "showDockBadge"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [keepHoursKey: 24, maxItemsKey: 50, autoPasteKey: false, showBadgeKey: true])
    }

    static var keepHours: Int { UserDefaults.standard.integer(forKey: keepHoursKey) }
    static var maxItems: Int { max(1, UserDefaults.standard.integer(forKey: maxItemsKey)) }
    static var autoPaste: Bool { UserDefaults.standard.bool(forKey: autoPasteKey) }
    static var showBadge: Bool { UserDefaults.standard.bool(forKey: showBadgeKey) }
}

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

// Pastes into the frontmost app by sending ⌘V, which needs Accessibility access.
enum AutoPaste {
    static var isAllowed: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func paste() {
        guard isAllowed else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Settings window

@MainActor
final class SettingsWindowController {
    private let store: Store
    private var window: NSWindow?

    init(store: Store) { self.store = store }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store, state: SettingsState())))
            w.title = "Copycat Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Settings state that isn't stored in UserDefaults. (A model object rather than @State, which
// needs a compiler plugin that only ships with full Xcode.)
@MainActor
final class SettingsState: ObservableObject {
    @Published var openAtLogin = LoginItem.isEnabled
    @Published var pasteAllowed = AutoPaste.isAllowed
    @Published var confirmClear = false

    func refresh() {
        openAtLogin = LoginItem.isEnabled
        pasteAllowed = AutoPaste.isAllowed
    }
}

struct SettingsView: View {
    let store: Store
    @ObservedObject var state: SettingsState
    @AppStorage(Preferences.keepHoursKey) private var keepHours = 24
    @AppStorage(Preferences.maxItemsKey) private var maxItems = 50
    @AppStorage(Preferences.autoPasteKey) private var autoPaste = false
    @AppStorage(Preferences.showBadgeKey) private var showBadge = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Copycat at login", isOn: $state.openAtLogin)
                    .onChange(of: state.openAtLogin) { _, on in
                        if on != LoginItem.isEnabled { LoginItem.set(on) }
                        state.refresh()
                    }
                Toggle("Show the number of new copies on the Dock icon", isOn: $showBadge)
                LabeledContent("Open the shelf from anywhere") {
                    Text("⌃ ⌘ V")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                }
            }

            Section {
                Picker("Keep items for", selection: $keepHours) {
                    Text("1 hour").tag(1)
                    Text("1 day").tag(24)
                    Text("1 week").tag(24 * 7)
                    Text("1 month").tag(24 * 30)
                    Text("Until removed").tag(0)
                }
                Picker("Keep up to", selection: $maxItems) {
                    ForEach([25, 50, 100, 200, 500], id: \.self) { Text("\($0) items").tag($0) }
                }
            } header: {
                Text("History")
            } footer: {
                HStack {
                    Text("Pinned items are always kept.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History…", role: .destructive) { state.confirmClear = true }
                }
                .font(.callout)
            }

            Section {
                Toggle("Paste right after choosing an item", isOn: $autoPaste)
                    .onChange(of: autoPaste) { _, on in
                        if on && !AutoPaste.isAllowed { AutoPaste.requestAccess() }
                    }
                if autoPaste && !state.pasteAllowed {
                    HStack {
                        Label("Copycat needs Accessibility access to paste for you.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Allow…") { AutoPaste.requestAccess() }
                    }
                    .font(.callout)
                }
            } header: {
                Text("Pasting")
            } footer: {
                Text("Choose an item and it's pasted into the app you were using, with no need to press ⌘V.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Label("History stays on this Mac and is never sent anywhere.", systemImage: "lock.fill")
                Label("Copies that password managers mark as secret are never saved.", systemImage: "key.fill")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: keepHours) { store.applyPreferences() }
        .onChange(of: maxItems) { store.applyPreferences() }
        .onChange(of: showBadge) { store.applyPreferences() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refresh()
        }
        .confirmationDialog("Clear all history?", isPresented: $state.confirmClear) {
            Button("Clear History", role: .destructive) { store.clearAll() }
        } message: {
            Text("This removes every item on the shelf, including pinned ones.")
        }
    }
}
