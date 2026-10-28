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
            Section {
                header
            }

            Section("General") {
                Toggle(isOn: $state.openAtLogin) { SettingLabel("Open Copycat at login", "power", .green) }
                    .onChange(of: state.openAtLogin) { _, on in
                        if on != LoginItem.isEnabled { LoginItem.set(on) }
                        state.refresh()
                    }
                Toggle(isOn: $showBadge) { SettingLabel("Show new copies on the Dock icon", "app.badge", .red) }
                LabeledContent {
                    Keycap("⌃ ⌘ V")
                } label: {
                    SettingLabel("Open Copycat from any app", "command", .gray)
                }
            }

            Section {
                Picker(selection: $keepHours) {
                    Text("1 hour").tag(1)
                    Text("1 day").tag(24)
                    Text("1 week").tag(24 * 7)
                    Text("1 month").tag(24 * 30)
                    Text("Until removed").tag(0)
                } label: {
                    SettingLabel("Keep items for", "clock", .blue)
                }
                Picker(selection: $maxItems) {
                    ForEach([25, 50, 100, 200, 500], id: \.self) { Text("\($0) items").tag($0) }
                } label: {
                    SettingLabel("Keep up to", "square.stack", .indigo)
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
                Toggle(isOn: $autoPaste) { SettingLabel("Paste right after choosing an item", "doc.on.clipboard", .orange) }
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
                SettingLabel("History stays on this Mac and is never sent anywhere.", "lock.fill", .teal)
                SettingLabel("Passwords copied from password managers are never saved.", "key.fill", .pink)
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

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 58, height: 58)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Copycat").font(.system(size: 17, weight: .semibold))
                Text("Version \(Self.version)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Link(destination: URL(string: "https://github.com/ChavdaUjjval/copycat")!) {
                Label("GitHub", systemImage: "arrow.up.right.square")
            }
            .font(.system(size: 12))
        }
        .padding(.vertical, 4)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

// A setting's title with a small coloured icon, like System Settings.
struct SettingLabel: View {
    let title: String
    let symbol: String
    let color: Color

    init(_ title: String, _ symbol: String, _ color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .top, endPoint: .bottom)))
            Text(title)
        }
    }
}
