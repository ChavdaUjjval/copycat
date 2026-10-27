import AppKit

// The background of the installer disk image window: a soft card with an arrow from the app to
// Applications. build.sh renders it with `Copycat --dmg-background out.png --scale 2`.
// Icon positions here must match the ones build.sh gives Finder.
enum InstallerArt {
    static let size = NSSize(width: 640, height: 420)
    static let appIconCenter = NSPoint(x: 170, y: 200)    // Finder coordinates, top-left origin
    static let appsIconCenter = NSPoint(x: 470, y: 200)

    static func render(to path: String, scale: CGFloat) {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
        }
        // Finder coordinates have y going down; AppKit's go up.
        func flip(_ p: NSPoint) -> NSPoint { NSPoint(x: p.x, y: size.height - p.y) }

        // Background: the icon's sunset colours, washed out to a soft cream.
        let bounds = NSRect(origin: .zero, size: size)
        NSGradient(colors: [rgb(255, 247, 236), rgb(255, 236, 228), rgb(253, 228, 236)])!.draw(in: bounds, angle: -60)

        // Large faint circles for depth.
        for (center, radius, color) in [(NSPoint(x: 40, y: 380), 190.0, rgb(255, 196, 87, 0.16)),
                                        (NSPoint(x: 610, y: 40), 230.0, rgb(245, 86, 130, 0.10)),
                                        (NSPoint(x: 560, y: 400), 120.0, rgb(255, 128, 102, 0.10))] {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
        }

        // Soft wells behind the two icons.
        for c in [appIconCenter, appsIconCenter].map(flip) {
            let well = NSBezierPath(roundedRect: NSRect(x: c.x - 92, y: c.y - 92, width: 184, height: 184),
                                    xRadius: 42, yRadius: 42)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.shadowColor = rgb(160, 80, 60, 0.12)
            shadow.set()
            NSColor(white: 1, alpha: 0.65).setFill()
            well.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 1, alpha: 0.9).setStroke()
            well.lineWidth = 1.5
            well.stroke()
        }

        // Arrow from the app to Applications.
        let tip = flip(NSPoint(x: appsIconCenter.x - 108, y: appsIconCenter.y))
        let from = flip(NSPoint(x: appIconCenter.x + 112, y: appIconCenter.y))
        let end = NSPoint(x: tip.x - 16, y: tip.y)
        let arrow = NSBezierPath()
        arrow.move(to: from)
        arrow.curve(to: end, controlPoint1: NSPoint(x: from.x + 20, y: from.y + 34),
                    controlPoint2: NSPoint(x: end.x - 34, y: end.y + 8))
        arrow.lineWidth = 5
        arrow.lineCapStyle = .round
        arrow.setLineDash([0.1, 12], count: 2, phase: 0)
        rgb(240, 104, 110).setStroke()
        arrow.stroke()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: tip.x - 13, y: tip.y + 13))
        head.line(to: tip)
        head.line(to: NSPoint(x: tip.x - 13, y: tip.y - 13))
        head.lineWidth = 5
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.stroke()

        // Title and first-launch hint.
        func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let string = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color, .paragraphStyle: paragraph,
            ])
            string.draw(in: NSRect(x: 20, y: flip(NSPoint(x: 0, y: y)).y - size * 1.4, width: self.size.width - 40, height: size * 1.6))
        }
        draw("Drag Copycat to Applications", size: 20, weight: .semibold, color: rgb(70, 52, 64), y: 34)
        draw("First launch: if macOS can't verify the app, open System Settings › Privacy & Security",
             size: 11.5, weight: .regular, color: rgb(120, 96, 108), y: 340)
        draw("and click “Open Anyway”. Copycat then starts at login and lives in your Dock.",
             size: 11.5, weight: .regular, color: rgb(120, 96, 108), y: 358)

        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
