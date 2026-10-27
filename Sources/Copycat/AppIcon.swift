import AppKit

// The app icon, a cat peeking over a stack of copied cards. build.sh renders it
// with `Copycat --icon out.png` and turns it into AppIcon.icns.
enum AppIcon {
    static func render(to path: String) {
        let px = 1024
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
        }
        func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h))
        }
        func shadowed(_ blur: CGFloat, _ dy: CGFloat, _ alpha: CGFloat, _ draw: () -> Void) {
            NSGraphicsContext.saveGraphicsState()
            let s = NSShadow()
            s.shadowBlurRadius = blur
            s.shadowOffset = NSSize(width: 0, height: -dy)
            s.shadowColor = NSColor(white: 0, alpha: alpha)
            s.set()
            draw()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Background: warm sunset squircle.
        let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGradient(colors: [rgb(255, 196, 87), rgb(255, 128, 102), rgb(245, 86, 130)])!.draw(in: body, angle: -90)
        NSGraphicsContext.saveGraphicsState()
        body.addClip()

        let fur = rgb(46, 42, 58)
        let furLight = rgb(78, 72, 96)
        let pink = rgb(255, 150, 170)

        // Ears (behind the head).
        for side: CGFloat in [-1, 1] {
            let ear = NSBezierPath()
            ear.move(to: NSPoint(x: 512 + side * 205, y: 700))
            ear.line(to: NSPoint(x: 512 + side * 175, y: 872))
            ear.line(to: NSPoint(x: 512 + side * 60, y: 790))
            ear.close()
            ear.lineJoinStyle = .round
            ear.lineWidth = 44
            fur.setFill(); fur.setStroke()
            ear.fill(); ear.stroke()
            let inner = NSBezierPath()
            inner.move(to: NSPoint(x: 512 + side * 180, y: 735))
            inner.line(to: NSPoint(x: 512 + side * 168, y: 832))
            inner.line(to: NSPoint(x: 512 + side * 100, y: 786))
            inner.close()
            inner.lineJoinStyle = .round
            inner.lineWidth = 18
            pink.setFill(); pink.setStroke()
            inner.fill(); inner.stroke()
        }

        // Head.
        shadowed(30, 10, 0.25) {
            fur.setFill()
            oval(512, 610, 470, 380).fill()
        }

        // Eyes: big and shiny.
        for side: CGFloat in [-1, 1] {
            let x = 512 + side * 98
            NSColor.white.setFill()
            oval(x, 660, 116, 128).fill()
            rgb(30, 26, 40).setFill()
            oval(x + side * 6, 650, 70, 86).fill()
            NSColor.white.setFill()
            oval(x + side * 6 - 16, 672, 26, 28).fill()
            oval(x + side * 6 + 14, 628, 11, 11).fill()
        }

        // Nose, mouth and whiskers.
        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: 486, y: 590))
        nose.line(to: NSPoint(x: 538, y: 590))
        nose.line(to: NSPoint(x: 512, y: 562))
        nose.close()
        nose.lineJoinStyle = .round
        nose.lineWidth = 14
        pink.setFill(); pink.setStroke()
        nose.fill(); nose.stroke()
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: 512, y: 558))
        mouth.curve(to: NSPoint(x: 470, y: 540), controlPoint1: NSPoint(x: 508, y: 536), controlPoint2: NSPoint(x: 484, y: 530))
        mouth.move(to: NSPoint(x: 512, y: 558))
        mouth.curve(to: NSPoint(x: 554, y: 540), controlPoint1: NSPoint(x: 516, y: 536), controlPoint2: NSPoint(x: 540, y: 530))
        mouth.lineWidth = 10
        mouth.lineCapStyle = .round
        (furLight.blended(withFraction: 0.5, of: .white) ?? .white).setStroke()
        mouth.stroke()
        let whiskers = NSBezierPath()
        for side: CGFloat in [-1, 1] {
            for (dy, spread) in [(CGFloat(18), CGFloat(34)), (0, 0), (-18, -34)] {
                whiskers.move(to: NSPoint(x: 512 + side * 120, y: 570 + dy))
                whiskers.line(to: NSPoint(x: 512 + side * 262, y: 570 + dy + spread))
            }
        }
        whiskers.lineWidth = 9
        whiskers.lineCapStyle = .round
        NSColor(white: 1, alpha: 0.75).setStroke()
        whiskers.stroke()

        // The stack of copied cards the cat is holding.
        let back = NSBezierPath(roundedRect: NSRect(x: 262, y: 176, width: 500, height: 330), xRadius: 52, yRadius: 52)
        var t = AffineTransform(translationByX: 512, byY: 320)
        t.rotate(byDegrees: -9)
        t.translate(x: -512, y: -320)
        back.transform(using: t)
        shadowed(24, 8, 0.18) {
            NSColor(white: 1, alpha: 0.7).setFill()
            back.fill()
        }
        let card = NSBezierPath(roundedRect: NSRect(x: 244, y: 170, width: 536, height: 340), xRadius: 52, yRadius: 52)
        shadowed(36, 14, 0.28) {
            NSColor.white.setFill()
            card.fill()
        }
        // Text lines on the card.
        for (i, w) in [CGFloat(330), 400, 260].enumerated() {
            let y = 398 - CGFloat(i) * 70
            rgb(255, 150, 120, 0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: 312, y: y, width: w, height: 30), xRadius: 15, yRadius: 15).fill()
        }

        // Paws over the top edge of the card.
        for side: CGFloat in [-1, 1] {
            let x = 512 + side * 118
            shadowed(10, 4, 0.2) {
                fur.setFill()
                oval(x, 500, 132, 96).fill()
            }
            furLight.setStroke()
            let toes = NSBezierPath()
            for dx: CGFloat in [-22, 22] {
                toes.move(to: NSPoint(x: x + dx, y: 470))
                toes.line(to: NSPoint(x: x + dx, y: 498))
            }
            toes.lineWidth = 9
            toes.lineCapStyle = .round
            toes.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()   // clip
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
