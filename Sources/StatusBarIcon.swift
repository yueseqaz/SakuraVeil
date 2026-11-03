import Cocoa

enum StatusBarIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(
            systemSymbolName: "eye.slash",
            accessibilityDescription: "SakuraVeil"
        ) ?? makeFallbackImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    /// SF Symbol 不可用时的手绘兜底：一只眼睛 + 斜杠。
    static func makeFallbackImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let eye = NSBezierPath()
            eye.appendArc(withCenter: NSPoint(x: 9, y: 6.5), radius: 7.5, startAngle: 200, endAngle: -20)
            eye.lineWidth = 1.2
            eye.stroke()

            let pupil = NSBezierPath(ovalIn: NSRect(x: 7, y: 4.5, width: 4, height: 4))
            pupil.fill()

            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: 3, y: 2))
            slash.line(to: NSPoint(x: 15, y: 16))
            slash.lineWidth = 1.5
            slash.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
