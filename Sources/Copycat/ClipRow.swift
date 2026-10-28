import AppKit
import SwiftUI

// Name and icon of the Mac app a clip came from.
@MainActor
enum AppInfo {
    private static var cache: [String: (name: String, icon: NSImage)] = [:]

    static func lookup(_ bundleID: String) -> (name: String, icon: NSImage)? {
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let info = (name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        cache[bundleID] = info
        return info
    }
}

// Decoded thumbnails, so redrawing a row doesn't decode its PNG again.
@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()

    static func image(for clip: Clip) -> NSImage? {
        guard let data = clip.thumb else { return nil }
        let key = "\(clip.id)-\(data.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Card

struct ClipRow: View {
    let clip: Clip
    var shortcut: Int?   // 1–9 when the item can be copied with ⌘1…⌘9
    var flashed = false
    var selected = false
    var hovered = false

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var symbol: String {
        if clip.link != nil { return "link" }
        switch clip.kind {
        case .media: return clip.isVideo ? "video.fill" : "photo.fill"
        case .files: return "doc.fill"
        case .text: return "text.alignleft"
        }
    }

    private var tint: Color {
        if clip.link != nil { return .blue }
        switch clip.kind {
        case .media: return .purple
        case .files: return .orange
        case .text: return .teal
        }
    }

    private var fill: Color {
        if flashed { return Color.green.opacity(0.18) }
        if selected { return Color.accentColor.opacity(0.14) }
        return Color.primary.opacity(hovered ? 0.085 : 0.05)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            meta
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.14 : 0.08),
                              lineWidth: selected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) { badge.padding(8) }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    @ViewBuilder private var content: some View {
        if let image = ThumbnailCache.image(for: clip) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    ZStack {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        if clip.isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white, .black.opacity(0.45))
                        }
                    }
                    .frame(maxHeight: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    Spacer(minLength: 0)
                }
                if !clip.files.isEmpty {
                    Text(clip.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } else if let url = clip.link {
            HStack(spacing: 10) {
                tile
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.host ?? url.absoluteString).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(url.absoluteString).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .padding(.trailing, 76)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                tile
                Text(clip.color != nil ? clip.title.uppercased() : clip.title)
                    .font(clip.color != nil ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 13))
                    .lineLimit(clip.kind == .files ? 2 : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.trailing, 76)
            }
        }
    }

    @ViewBuilder private var tile: some View {
        if let color = clip.color {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: color))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                .frame(width: 26, height: 26)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.16)))
        }
    }

    private var meta: some View {
        HStack(spacing: 5) {
            if clip.fromDevice {
                Label("iPhone", systemImage: "iphone")
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                    .foregroundStyle(Color.primary)
            } else if let id = clip.sourceApp, let app = AppInfo.lookup(id) {
                Image(nsImage: app.icon).resizable().frame(width: 13, height: 13)
                Text(app.name)
            }
            if clip.fromDevice || clip.sourceApp != nil { Text("·") }
            Text(Self.relative.localizedString(for: clip.date, relativeTo: Date()))
            if clip.isVideo { Text("· Video") }
            Spacer(minLength: 6)
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.18)))
                    .opacity(hovered || selected ? 1 : 0.7)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder private var badge: some View {
        if flashed {
            Label("Copied", systemImage: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.green))
                .foregroundStyle(.white)
        } else if clip.pinned && !hovered {
            Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(.orange)
        }
    }
}

// MARK: - Cells

enum RowAction { case pin, preview, remove }

// Table cell hosting a ClipRow, with Pin / Preview / Remove buttons that appear on hover.
// The buttons are AppKit controls so clicks on them don't also count as clicking the row.
final class HostCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("cell")
    let host = NSHostingView(rootView: ClipRow(clip: Clip()))
    var onAction: (RowAction) -> Void = { _ in }

    private var row = ClipRow(clip: Clip())
    private var hovered = false
    private let actions = NSVisualEffectView()
    private lazy var pinButton = makeButton("pin", #selector(pinClicked))
    private lazy var previewButton = makeButton("eye", #selector(previewClicked))
    private lazy var removeButton = makeButton("trash", #selector(removeClicked))

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)

        previewButton.toolTip = "Preview (Space)"
        removeButton.toolTip = "Remove (Delete)"
        let buttons = NSStackView(views: [pinButton, previewButton, removeButton])
        buttons.spacing = 0
        buttons.edgeInsets = NSEdgeInsets(top: 0, left: 3, bottom: 0, right: 3)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        actions.material = .popover
        actions.state = .active
        actions.wantsLayer = true
        actions.layer?.cornerRadius = 8
        actions.layer?.borderWidth = 0.5
        actions.layer?.borderColor = NSColor.separatorColor.cgColor
        actions.isHidden = true
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.addSubview(buttons)
        addSubview(actions)

        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: actions.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: actions.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: actions.topAnchor),
            buttons.bottomAnchor.constraint(equalTo: actions.bottomAnchor),
            actions.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ newRow: ClipRow) {
        if newRow.clip.id != row.clip.id { hovered = false }
        row = newRow
        render()
    }

    func setHovered(_ on: Bool) {
        hovered = on
        render()
    }

    private func render() {
        var r = row
        r.hovered = hovered
        host.rootView = r
        actions.isHidden = !hovered || row.flashed
        pinButton.image = NSImage(systemSymbolName: row.clip.pinned ? "pin.slash" : "pin", accessibilityDescription: nil)
        pinButton.toolTip = row.clip.pinned ? "Unpin" : "Pin to Top"
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            actions.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    private func makeButton(_ symbol: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(),
                              target: self, action: action)
        button.isBordered = false
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    @objc private func pinClicked() { onAction(.pin) }
    @objc private func previewClicked() { onAction(.preview) }
    @objc private func removeClicked() { onAction(.remove) }
}

// Section title ("Pinned", "Today"…) between groups of cards.
final class HeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("header")
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue.uppercased() }
    }
}

// Rows draw nothing themselves: the cards and headers do.
final class PlainRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
}
