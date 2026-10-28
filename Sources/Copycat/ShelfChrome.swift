import AppKit
import SwiftUI

// MARK: - Filters

enum Filter: Int, CaseIterable, Identifiable {
    case all, text, media, files, iPhone

    var id: Int { rawValue }
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

// Filter tabs with item counts, drawn like a segmented control. Filters with nothing in them are hidden.
struct FilterBar: View {
    var counts: [Filter: Int] = [:]
    var selected = Filter.all
    var onSelect: (Filter) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // In a narrow window the tabs drop their icons, then their counts.
        ViewThatFits(in: .horizontal) {
            tabs(icons: true, counts: true)
            tabs(icons: false, counts: true)
            tabs(icons: false, counts: false)
        }
    }

    private func tabs(icons: Bool, counts showCounts: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Filter.allCases.filter { $0 == .all || $0 == selected || counts[$0, default: 0] > 0 }) { filter in
                    tab(filter, icon: icons, count: showCounts)
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06)))
            Spacer(minLength: 0)
        }
    }

    private func tab(_ filter: Filter, icon: Bool, count: Bool) -> some View {
        let on = filter == selected
        return Button { onSelect(filter) } label: {
            HStack(spacing: 4) {
                if icon { Image(systemName: filter.symbol).font(.system(size: 10, weight: .semibold)) }
                Text(filter.label)
                if count {
                    Text("\(counts[filter, default: 0])")
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .fixedSize()
            .font(.system(size: 11.5, weight: on ? .semibold : .medium))
            .foregroundStyle(on ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                if on {
                    Capsule()
                        .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.12), radius: 1.5, y: 0.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show \(filter == .all ? "everything" : filter.label.lowercased())")
    }
}

// MARK: - Footer

struct FooterBar: View {
    @ObservedObject var store: Store
    var openSettings: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Button { store.paused.toggle() } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.paused ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: (store.paused ? Color.orange : Color.green).opacity(0.6), radius: 2)
                    Text(store.paused ? "Paused" : store.clips.count == 1 ? "1 item" : "\(store.clips.count) items")
                        .foregroundStyle(store.paused ? Color.orange : Color.secondary)
                        .monospacedDigit()
                }
                .fixedSize()
                .contentShape(Rectangle())
            }
            .accessibilityLabel(store.paused ? "Resume saving copies" : "Pause saving copies")
            .help(store.paused ? "Resume saving copies" : "Pause saving copies")
            Spacer(minLength: 4)
            status
            iconButton("trash", label: "Wipe Clipboard", help: "Wipe the Mac's clipboard and the shelf. Pinned items stay.") {
                store.wipeClipboard()
            }
            iconButton("gearshape", label: "Settings", help: "Settings (⌘,)", action: openSettings)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5))
        .lineLimit(1)
    }

    @ViewBuilder private var status: some View {
        if let notice = store.notice {
            HStack(spacing: 6) {
                Image(systemName: store.canUndo ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(store.canUndo ? Color.secondary : Color.green)
                Text(notice).foregroundStyle(.secondary)
                if store.canUndo {
                    Button("Undo") { store.undo() }
                        .buttonStyle(.link)
                        .help("Undo (⌘Z)")
                }
            }
            .fixedSize()
            .transition(.opacity)
        } else if !store.clips.isEmpty {
            ViewThatFits(in: .horizontal) {
                hints(preview: true)
                hints(preview: false)
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    private func hints(preview: Bool) -> some View {
        HStack(spacing: 10) {
            hint("⏎", "Copy")
            if preview { hint("Space", "Preview") }
        }
        .fixedSize()
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Keycap(key)
        }
    }

    private func iconButton(_ symbol: String, label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .help(help)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    var title = "Your clipboard history"
    var showTips = true

    var body: some View {
        VStack(spacing: 0) {
            if showTips {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.bottom, 12)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 10)
            }
            Text(title)
                .font(.system(size: showTips ? 15 : 13, weight: .semibold))
                .foregroundStyle(showTips ? .primary : .secondary)
                .multilineTextAlignment(.center)
            if showTips {
                Text("Copy anything on your Mac or iPhone and it shows up here. You can also drop text, photos and files in.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 270)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                VStack(spacing: 0) {
                    tip("⌃⌘V", "Open Copycat from any app")
                    Divider().padding(.leading, 12)
                    tip("⌘1–9", "Copy one of the first nine items")
                    Divider().padding(.leading, 12)
                    tip("Space", "Preview the selected item")
                    Divider().padding(.leading, 12)
                    tip("⌘Z", "Bring back something you removed")
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                .frame(maxWidth: 290)
                .padding(.top, 20)
            }
        }
        .padding(24)
    }

    private func tip(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Keycap(keys)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
