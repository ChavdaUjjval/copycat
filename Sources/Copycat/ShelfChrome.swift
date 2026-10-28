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

// Filter chips with item counts. Filters with nothing in them are hidden.
struct FilterBar: View {
    var counts: [Filter: Int] = [:]
    var selected = Filter.all
    var onSelect: (Filter) -> Void = { _ in }

    var body: some View {
        // In a narrow window the chips drop their icons, then their counts.
        ViewThatFits(in: .horizontal) {
            chips(icons: true, counts: true)
            chips(icons: false, counts: true)
            chips(icons: false, counts: false)
        }
    }

    private func chips(icons: Bool, counts showCounts: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases.filter { $0 == .all || $0 == selected || counts[$0, default: 0] > 0 }) { filter in
                chip(filter, icon: icons, count: showCounts)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ filter: Filter, icon: Bool, count: Bool) -> some View {
        let on = filter == selected
        return Button { onSelect(filter) } label: {
            HStack(spacing: 4) {
                if icon { Image(systemName: filter.symbol).font(.system(size: 10, weight: .semibold)) }
                Text(filter.label)
                if count {
                    Text("\(counts[filter, default: 0])")
                        .foregroundStyle(on ? Color.white.opacity(0.75) : Color.secondary)
                }
            }
            .fixedSize()
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.07)))
            .foregroundStyle(on ? Color.white : Color.primary)
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
        HStack(spacing: 8) {
            Button { store.paused.toggle() } label: {
                Image(systemName: store.paused ? "play.circle.fill" : "pause.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(store.paused ? Color.orange : Color.secondary)
            }
            .help(store.paused ? "Resume capturing copies" : "Pause capturing copies")
            Text(store.clips.count == 1 ? "1 item" : "\(store.clips.count) items")
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 4)
            status
            Spacer(minLength: 4)
            Button(action: openSettings) {
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .help("Settings (⌘,)")
            Button { store.wipeClipboard() } label: {
                Label("Wipe", systemImage: "eraser")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Empty the Mac's clipboard and the shelf (pinned items stay)")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .lineLimit(1)
    }

    @ViewBuilder private var status: some View {
        if let notice = store.notice {
            HStack(spacing: 6) {
                Text(notice).foregroundStyle(store.canUndo ? Color.secondary : Color.green)
                if store.canUndo {
                    Button("Undo") { store.undo() }
                        .buttonStyle(.link)
                        .help("Undo (⌘Z)")
                }
            }
            .transition(.opacity)
        } else if store.paused {
            Label("Capturing paused", systemImage: "pause.fill").foregroundStyle(.orange)
        } else {
            Text("⏎ copy · Space preview · ⌘1–9").foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Empty state

struct EmptyState: View {
    var title = "Nothing on the shelf yet"
    var showTips = true

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showTips {
                Text("Copy something on your Mac or iPhone, or drop text, photos and videos here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    tip("⌃⌘V", "Open the shelf from any app")
                    tip("⌘1–9", "Copy one of the first nine items")
                    tip("Space", "Preview the selected item")
                    tip("⌘Z", "Bring back something you removed")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                .padding(.top, 6)
            }
        }
        .padding(20)
    }

    private func tip(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .frame(width: 46)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.18)))
            Text(text).font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }
}
