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

struct ClipRow: View {
    let clip: Clip
    let flashed: Bool
    let selected: Bool

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            meta
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(flashed ? Color.green.opacity(0.18) : selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) { badge.padding(8) }
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
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                tile
                Text(clip.title)
                    .font(.system(size: 13))
                    .lineLimit(clip.kind == .files ? 2 : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.trailing, 44)
            }
        }
    }

    private var tile: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.16)))
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
        } else if clip.pinned {
            Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(.orange)
        }
    }
}

// Table cell hosting a ClipRow.
final class HostCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("cell")
    let host = NSHostingView(rootView: ClipRow(clip: Clip(), flashed: false, selected: false))

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
