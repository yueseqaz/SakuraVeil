import Cocoa

enum StatusBarIcon {
    /// awake = 保持唤醒激活时显示闪电；否则显示眼睛斜杠。
    static func makeImage(awake: Bool = false) -> NSImage {
        let symbol = awake ? "bolt.fill" : "eye.slash"
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "SakuraVeil"
        ) ?? makeFallbackImage(bolt: awake)
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    /// SF Symbol 不可用时的手绘兜底：眼睛斜杠 / 闪电。
    static func makeFallbackImage(bolt: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            if bolt {
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: 10, y: 17))
                bolt.line(to: NSPoint(x: 5, y: 10))
                bolt.line(to: NSPoint(x: 8.5, y: 10))
                bolt.line(to: NSPoint(x: 7, y: 1))
                bolt.line(to: NSPoint(x: 13, y: 9))
                bolt.line(to: NSPoint(x: 9.5, y: 9))
                bolt.close()
                bolt.fill()
                return true
            }
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
