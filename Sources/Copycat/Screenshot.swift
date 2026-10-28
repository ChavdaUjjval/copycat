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
        // The window frame view, so the title bar buttons are included.
        guard let frame = shelf.window.contentView?.superview else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let lights = buttons.compactMap { type in
            shelf.window.standardWindowButton(type).map { $0.convert($0.bounds, to: nil) }
        }
        save(framed(snapshot(frame), dark: dark, lights: lights), to: path)
    }

    static func renderSettings(to path: String) {
        let view = NSHostingView(rootView: SettingsView(store: Store(demo: []), state: SettingsState()))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        save(snapshot(view), to: path)
    }

    private static func snapshot(_ view: NSView) -> NSBitmapImageRep {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private static func save(_ rep: NSBitmapImageRep, to path: String) {
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    // The window with rounded corners and a shadow, on a soft backdrop. An offscreen window is never
    // active, so its close/minimise/zoom buttons are drawn in their active colours.
    private static func framed(_ window: NSBitmapImageRep, dark: Bool, lights: [NSRect]) -> NSBitmapImageRep {
        let scale = CGFloat(window.pixelsWide) / window.size.width
        let margin: CGFloat = 44
        let size = NSSize(width: window.size.width + margin * 2, height: window.size.height + margin * 2)
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        let colors = dark
            ? [NSColor(srgbRed: 0.16, green: 0.12, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.07, green: 0.07, blue: 0.12, alpha: 1)]
            : [NSColor(srgbRed: 1, green: 0.86, blue: 0.72, alpha: 1), NSColor(srgbRed: 0.98, green: 0.76, blue: 0.84, alpha: 1)]
        NSGradient(colors: colors)!.draw(in: NSRect(origin: .zero, size: size), angle: -60)
        let rect = NSRect(x: margin, y: margin, width: window.size.width, height: window.size.height)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowColor = NSColor(white: 0, alpha: dark ? 0.55 : 0.28)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        window.draw(in: rect)
        let lightColors = [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                      NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)]
        for (light, color) in zip(lights, lightColors) {
            let side = min(light.width, light.height) - 2
            let dot = NSRect(x: margin + light.midX - side / 2, y: margin + light.midY - side / 2, width: side, height: side)
            color.setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor(white: 0, alpha: 0.12).setStroke()
            NSBezierPath(ovalIn: dot.insetBy(dx: 0.25, dy: 0.25)).stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: dark ? 1 : 0, alpha: dark ? 0.18 : 0.12).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 14, yRadius: 14)
        border.lineWidth = 0.5
        border.stroke()
        NSGraphicsContext.restoreGraphicsState()
        return out
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
