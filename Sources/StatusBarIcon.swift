import Cocoa

enum StatusBarIcon {
    /// awake = 保持唤醒激活时显示闪电；未激活显示 moon.zzz（会睡）。
    static func makeImage(awake: Bool = false) -> NSImage {
        let symbol = awake ? "bolt.fill" : "moon.zzz"
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "SakuraVeil"
        ) ?? makeFallbackImage(bolt: awake)
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    /// SF Symbol 不可用时的手绘兜底：月亮 zzz / 闪电。
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
            // 月亮
            let moon = NSBezierPath()
            moon.appendArc(withCenter: NSPoint(x: 8, y: 9), radius: 7, startAngle: 70, endAngle: -250)
            moon.appendArc(withCenter: NSPoint(x: 3.4, y: 10.6), radius: 5.6, startAngle: -250, endAngle: 70)
            moon.close()
            moon.fill()
            // zzz
            let z = NSBezierPath()
            z.lineWidth = 1.1
            z.move(to: NSPoint(x: 12, y: 17))
            z.line(to: NSPoint(x: 16, y: 17))
            z.line(to: NSPoint(x: 12, y: 12.5))
            z.line(to: NSPoint(x: 16, y: 12.5))
            z.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
