import Cocoa
import QuartzCore

/// 内置极光背景：深夜渐变底 + 数团缓慢漂移的彩色光晕 + 上升微粒。
/// 全部用 Core Animation，渲染在 Render Server 上进行，App 端开销极低、零素材。
final class AuroraView: NSView {

    private var installed = false
    private var installedSize: NSSize = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        wantsLayer = true
        layer?.masksToBounds = true
        installLayers()
    }

    override func layout() {
        super.layout()
        // 尺寸明显变化（换屏/改分辨率）时重建，让动画按新尺寸铺开。
        if installed,
           abs(bounds.width - installedSize.width) > 1 || abs(bounds.height - installedSize.height) > 1 {
            rebuild()
        }
    }

    private func rebuild() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        installed = false
        installLayers()
    }

    private func installLayers() {
        guard !installed, bounds.width > 1, bounds.height > 1 else { return }
        installed = true
        installedSize = bounds.size

        // 底色：深夜蓝紫
        let base = CAGradientLayer()
        base.frame = bounds
        base.colors = [
            NSColor(calibratedRed: 0.016, green: 0.024, blue: 0.078, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.043, green: 0.016, blue: 0.11, alpha: 1).cgColor,
        ]
        base.startPoint = CGPoint(x: 0.5, y: 0)
        base.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(base)

        // 光晕：三团颜色缓慢往返漂移（紫 / 樱粉 / 青）
        // 注：macOS 上 CAGradientLayer 的 radial 渲染不可靠，改用 NSGradient
        // 径向绘制预生成贴图，交给普通 CALayer.contents，必定可见。
        let blobs: [(NSColor, CGPoint, CGPoint, Double)] = [
            (NSColor(calibratedRed: 0.62, green: 0.28, blue: 1.0, alpha: 1),
             CGPoint(x: 0.25, y: 0.75), CGPoint(x: 0.62, y: 0.55), 17),
            (NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.62, alpha: 1),
             CGPoint(x: 0.75, y: 0.30), CGPoint(x: 0.35, y: 0.42), 21),
            (NSColor(calibratedRed: 0.15, green: 0.65, blue: 1.0, alpha: 1),
             CGPoint(x: 0.60, y: 0.85), CGPoint(x: 0.80, y: 0.20), 25),
        ]
        let blobSize = max(bounds.width, bounds.height) * 0.72
        for (index, blob) in blobs.enumerated() {
            guard let contents = Self.blobImage(blob.0) else { continue }
            let blobLayer = CALayer()
            blobLayer.frame = NSRect(x: 0, y: 0, width: blobSize, height: blobSize)
            blobLayer.contents = contents
            blobLayer.contentsGravity = .resize
            layer?.addSublayer(blobLayer)

            let p0 = point(from: blob.1)
            let p1 = point(from: blob.2)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: p0)
            move.toValue = NSValue(point: p1)
            move.duration = blob.3
            move.autoreverses = true
            move.repeatCount = .infinity
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            move.timeOffset = Double(index) * 4.5
            blobLayer.position = p0
            blobLayer.add(move, forKey: "drift")
        }

        installParticles()
    }

    private func point(from fraction: CGPoint) -> CGPoint {
        CGPoint(x: fraction.x * bounds.width, y: fraction.y * bounds.height)
    }

    /// 径向光晕贴图：中心着色、边缘透明（缓存一份，多团光晕各自着色）。
    private static func blobImage(_ color: NSColor) -> CGImage? {
        let size: CGFloat = 512
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let oval = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size))
            NSGradient(colors: [
                color.withAlphaComponent(0),
                color.withAlphaComponent(0.10),
                color.withAlphaComponent(0.22),
                color.withAlphaComponent(0.36),
                color.withAlphaComponent(0.50),
            ])?.draw(in: oval, relativeCenterPosition: .zero)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }

    private func installParticles() {
        for _ in 0..<26 {
            let radius = CGFloat.random(in: 1.5...5)
            let particle = CALayer()
            particle.frame = NSRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            particle.cornerRadius = radius
            particle.backgroundColor = NSColor.white
                .withAlphaComponent(CGFloat.random(in: 0.15...0.5)).cgColor
            layer?.addSublayer(particle)

            let startX = CGFloat.random(in: 0...bounds.width)
            let startY = CGFloat.random(in: 0...(bounds.height * 0.6))
            let endX = min(max(startX + CGFloat.random(in: -60...60), 0), bounds.width)
            let endY = startY + bounds.height * CGFloat.random(in: 0.35...0.85)
            particle.position = CGPoint(x: startX, y: startY)

            let rise = CABasicAnimation(keyPath: "position")
            rise.fromValue = NSValue(point: CGPoint(x: startX, y: startY))
            rise.toValue = NSValue(point: CGPoint(x: endX, y: endY))
            rise.duration = Double.random(in: 9...24)
            rise.repeatCount = .infinity
            rise.timingFunction = CAMediaTimingFunction(name: .linear)
            particle.add(rise, forKey: "rise")

            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = 0.1
            twinkle.toValue = 0.7
            twinkle.duration = Double.random(in: 1.8...4.2)
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            particle.add(twinkle, forKey: "twinkle")
        }
    }
}
