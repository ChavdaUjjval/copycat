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

// MARK: - Row

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
        case .media: return clip.isVideo ? "play.rectangle.fill" : "photo.fill"
        case .files: return "doc.fill"
        case .text: return "text.alignleft"
        }
    }

    private var tint: Color {
        if clip.link != nil { return Color(red: 0.2, green: 0.5, blue: 1) }
        switch clip.kind {
        case .media: return Color(red: 0.62, green: 0.36, blue: 0.95)
        case .files: return Color(red: 1, green: 0.58, blue: 0.16)
        case .text: return Color(red: 0.13, green: 0.62, blue: 0.74)
        }
    }

    // Selected rows use white text on the accent colour, like Spotlight.
    private var primary: Color { selected ? .white : .primary }
    private var secondary: Color { selected ? .white.opacity(0.78) : .secondary }

    private var fill: Color {
        if flashed { return Color.green.opacity(0.2) }
        if selected { return Color.accentColor }
        return Color.primary.opacity(hovered ? 0.06 : 0)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            tile
            VStack(alignment: .leading, spacing: 4) {
                content
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
        .animation(.easeOut(duration: 0.1), value: hovered)
    }

    @ViewBuilder private var content: some View {
        if let image = ThumbnailCache.image(for: clip) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Image(nsImage: image).resizable()
                    if clip.isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, .black.opacity(0.45))
                    }
                }
                .frame(width: Self.fit(image.size).width, height: Self.fit(image.size).height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .padding(.top, 2)
                if !clip.files.isEmpty {
                    Text(clip.title).font(.system(size: 12)).foregroundStyle(secondary).lineLimit(1)
                }
            }
        } else if let url = clip.link {
            VStack(alignment: .leading, spacing: 1) {
                Text(url.host ?? url.absoluteString).font(.system(size: 13, weight: .semibold)).foregroundStyle(primary)
                Text(url.absoluteString).font(.system(size: 11.5)).foregroundStyle(secondary).truncationMode(.middle)
            }
            .lineLimit(1)
        } else {
            Text(clip.color != nil ? clip.title.uppercased() : clip.title)
                .font(clip.color != nil ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 13))
                .foregroundStyle(primary)
                .lineLimit(clip.kind == .files ? 2 : 3)
                .lineSpacing(1.5)
                .frame(minHeight: 17, alignment: .leading)
        }
    }

    // Thumbnail size: at most 220 × 124 points, keeping the image's shape.
    private static func fit(_ size: NSSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 124, height: 124) }
        let scale = min(220 / size.width, 124 / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    // A coloured tile for the kind of item, with the source app's icon tucked in the corner.
    private var tile: some View {
        ZStack(alignment: .bottomTrailing) {
            if let color = clip.color {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: color))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [tint.opacity(0.78), tint], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(selected ? 0.7 : 0), lineWidth: 1))
                    .shadow(color: tint.opacity(0.3), radius: 2, y: 1)
            }
            source.offset(x: 5, y: 5)
        }
        .frame(width: 37, height: 37, alignment: .topLeading)
    }

    @ViewBuilder private var source: some View {
        if clip.fromDevice {
            Image(systemName: "iphone")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Color.black.opacity(0.75)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
        } else if let id = clip.sourceApp, let app = AppInfo.lookup(id) {
            Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
        }
    }

    private var meta: some View {
        HStack(spacing: 5) {
            if clip.pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(selected ? .white : .orange)
            }
            if clip.fromDevice {
                Text("iPhone")
            } else if let id = clip.sourceApp, let app = AppInfo.lookup(id) {
                Text(app.name)
            }
            if clip.fromDevice || clip.sourceApp != nil { Text("·") }
            Text(Self.relative.localizedString(for: clip.date, relativeTo: Date()))
            if clip.isVideo { Text("· Video") }
            Spacer(minLength: 6)
            trailing
        }
        .font(.system(size: 11))
        .foregroundStyle(secondary)
        .lineLimit(1)
        .frame(height: 18)
    }

    @ViewBuilder private var trailing: some View {
        if flashed {
            Label("Copied", systemImage: "checkmark")
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.green))
                .foregroundStyle(.white)
        } else if let shortcut, !hovered {
            Keycap("⌘\(shortcut)", inverted: selected)
        }
    }
}

// A small key label, like ⌘1 or ⏎.
struct Keycap: View {
    let keys: String
    var inverted = false

    init(_ keys: String, inverted: Bool = false) {
        self.keys = keys
        self.inverted = inverted
    }

    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(inverted ? Color.white : Color.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 17)
            .background(RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(inverted ? Color.white.opacity(0.2) : Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(inverted ? Color.white.opacity(0.3) : Color.primary.opacity(0.12), lineWidth: 0.5))
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
        buttons.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        actions.material = .popover
        actions.state = .active
        actions.wantsLayer = true
        actions.layer?.cornerRadius = 7
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
            actions.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ newRow: ClipRow) {
        // A reused cell (after pinning, removing or filtering) is hovered if the mouse is over it now.
        if newRow.clip.id != row.clip.id { hovered = mouseIsInside }
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

    private var mouseIsInside: Bool {
        guard let window, window.isVisible else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
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
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 21).isActive = true
        return button
    }

    @objc private func pinClicked() { onAction(.pin) }
    @objc private func previewClicked() { onAction(.preview) }
    @objc private func removeClicked() { onAction(.remove) }
}

// Section title ("Pinned", "Today"…) between groups of rows.
final class HeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("header")
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
}

// Table rows draw nothing themselves: the hosted rows and headers do.
final class PlainRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
}
