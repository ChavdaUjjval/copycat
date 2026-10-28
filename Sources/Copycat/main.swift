// Copycat: clipboard history that lives in the Dock.
//
// • Open it from the Dock icon or with ⌃⌘V from anywhere. Single-click an item (or pick it with
//   the arrow keys and press Return) to copy it; the shelf then hides so you can paste as usual.
// • ⌘-click / ⇧-click to select several items, then drag them out into any app, or press Return to copy them all.
// • Drag text, photos or videos onto the shelf (or files onto its Dock icon) to keep them for later.
// • Right-click for Copy as Plain Text, Edit Before Copying, Pin, Remove.
// • Universal Clipboard copies from iPhone/iPad are read the moment they arrive and kept,
//   including photos/files, which macOS otherwise deletes shortly after.
// • Web images in formats many apps can't take (WebP, AVIF…) get a PNG copy, and text copied
//   from iPhone photos (Live Text) is pasted/dragged as plain text rather than an .rtfd attachment.
// • Unpinned items expire after 24 hours. "Wipe Clipboard" empties the system clipboard and the shelf (pinned items stay).
// • Items marked secret by password managers (nspasteboard.org Concealed/Transient) are never saved.
import AppKit

let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--icon"), i + 1 < arguments.count {
    AppIcon.render(to: arguments[i + 1])
    exit(0)
}
if let i = arguments.firstIndex(of: "--dmg-background"), i + 1 < arguments.count {
    let scale = arguments.firstIndex(of: "--scale").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil }
    InstallerArt.render(to: arguments[i + 1], scale: CGFloat(scale ?? 1))
    exit(0)
}

Preferences.registerDefaults()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    if let i = arguments.firstIndex(of: "--settings-screenshot"), i + 1 < arguments.count {
        Screenshot.renderSettings(to: arguments[i + 1])
        exit(0)
    }
    if let i = arguments.firstIndex(of: "--screenshot"), i + 1 < arguments.count {
        let width = arguments.firstIndex(of: "--width").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil }
        Screenshot.render(to: arguments[i + 1], dark: arguments.contains("--dark"),
                          empty: arguments.contains("--empty"), width: CGFloat(width ?? 420))
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
