import AppKit
import SwiftUI

// `Copycat --screenshot out.png [--dark] [--empty] [--width N]` renders the shelf filled with sample items,
// for the README and for checking design changes. It never touches the real history.
@MainActor
enum Screenshot {
    static func render(to path: String, dark: Bool, empty: Bool = false, width: CGFloat = 420) {
        let shelf = ShelfController(store: Store(demo: empty ? [] : sampleClips()))
        shelf.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        shelf.window.setFrame(NSRect(x: 0, y: 0, width: width, height: 720), display: false)
        shelf.reload()
        shelf.window.contentView?.layoutSubtreeIfNeeded()
        shelf.showDemoState()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let view = shelf.window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func renderSettings(to path: String) {
        let view = NSHostingView(rootView: SettingsView(store: Store(demo: []), state: SettingsState()))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func sampleClips() -> [Clip] {
        let now = Date()
        func clip(_ text: String, minutesAgo: Double, app: String? = nil, pinned: Bool = false,
                  fromDevice: Bool = false) -> Clip {
            var c = Clip(date: now.addingTimeInterval(-minutesAgo * 60), fromDevice: fromDevice, pinned: pinned,
                         key: "t:" + text, text: text, payload: [[PasteboardTypes.plainText: Data(text.utf8)]])
            c.sourceApp = app
            return c
        }

        let iconPath = FileManager.default.temporaryDirectory.appendingPathComponent("copycat-sample.png").path
        AppIcon.render(to: iconPath)
        var image = Clip(date: now.addingTimeInterval(-26 * 60), key: "h:sample-image")
        image.thumb = Images.thumbnail(file: URL(fileURLWithPath: iconPath))
        image.payload = [["public.png": image.thumb ?? Data()]]
        image.sourceApp = "com.apple.Preview"
        try? FileManager.default.removeItem(atPath: iconPath)

        var file = Clip(date: now.addingTimeInterval(-26 * 60 * 60), key: "f:sample-file")
        file.files = ["Quarterly report.pdf"]
        file.payload = [[PasteboardTypes.fileURL: Data("file:///tmp/Quarterly%20report.pdf".utf8)]]
        file.sourceApp = "com.apple.finder"

        return [
            clip("Thanks for the update! I'll review the draft tonight and send my notes first thing tomorrow.",
                 minutesAgo: 300, app: "com.apple.mail", pinned: true),
            clip("Meet at the north entrance at 6:30", minutesAgo: 1, fromDevice: true),
            clip("https://developer.apple.com/documentation/appkit", minutesAgo: 4, app: "com.apple.Safari"),
            clip("#F5568A", minutesAgo: 9, app: "com.apple.TextEdit"),
            clip("git commit -m \"Add filter chips and hover actions\"", minutesAgo: 15, app: "com.apple.Terminal"),
            image,
            file,
        ]
    }
}
