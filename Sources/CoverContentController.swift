import Cocoa
import AVFoundation

/// 单块屏幕上的遮罩内容：背景（极光/视频/图片/壁纸）+ 顶部时钟 + 底部轮播文案。
final class CoverContentController {

    private let screen: NSScreen
    private let container: NSView

    // 背景
    private var backgroundView: NSView?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    // 顶部时钟
    private var timeLabel: NSTextField?
    private var infoLabel: NSTextField?

    // 底部文案轮播
    private var capsuleView: NSView?
    private var messageLabel: NSTextField?
    private var messageIndex = 0
    private let startedAt = Date()

    private var clockTimer: Timer?
    private var rotateTimer: Timer?
    private let timeFormatter: DateFormatter
    private let infoFormatter: DateFormatter

    init(screen: NSScreen, container: NSView) {
        self.screen = screen
        self.container = container
        timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        infoFormatter = DateFormatter()
        infoFormatter.dateFormat = I18N.t("M月d日 EEEE", "EEE, MMM d")
    }

    // MARK: - 生命周期

    func install() {
        installBackground()
        installClock()
        installMessageCapsule()
        startTimers()
    }

    func teardown() {
        clockTimer?.invalidate()
        clockTimer = nil
        rotateTimer?.invalidate()
        rotateTimer = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        backgroundView?.removeFromSuperview()
        backgroundView = nil
        timeLabel?.removeFromSuperview()
        timeLabel = nil
        infoLabel?.removeFromSuperview()
        infoLabel = nil
        capsuleView?.removeFromSuperview()
        capsuleView = nil
        messageLabel = nil
    }

    /// 系统唤醒后恢复播放与计时显示。
    func resumeIfNeeded() {
        player?.play()
        updateClock()
    }

    // MARK: - 背景

    private func installBackground() {
        switch Settings.shared.contentMode {
        case .aurora:
            installAurora()
        case .video:
            if !installVideo() { installAurora() }
        case .image:
            if !installImage(url: Settings.shared.imageURL) { installAurora() }
        case .wallpaper:
            let url = NSWorkspace.shared.desktopImageURL(for: screen)
            if !installImage(url: url) { installAurora() }
        }
    }

    private func installAurora() {
        let view = AuroraView(frame: container.bounds)
        container.addSubview(view)
        backgroundView = view
    }

    private func installVideo() -> Bool {
        guard let url = Settings.shared.videoURL,
              FileManager.default.fileExists(atPath: url.path) else {
            Log.cover.error("视频文件不可用，回退极光动画")
            return false
        }

        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player

        let wrapper = NSView(frame: container.bounds)
        container.addSubview(wrapper)
        wrapper.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        layer.frame = wrapper.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        wrapper.layer?.addSublayer(layer)

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }

        backgroundView = wrapper
        player.play()
        return true
    }

    private func installImage(url: URL?) -> Bool {
        guard let url, let image = NSImage(contentsOf: url) else {
            if url != nil {
                Log.cover.error("图片加载失败，回退极光动画")
            }
            return false
        }

        let clip = NSView(frame: container.bounds)
        container.addSubview(clip)
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true

        // 等比铺满（aspect fill）：图片按比例放大到覆盖容器，超出部分裁掉
        let imageView = NSImageView(frame: Self.aspectFillRect(for: image.size, in: clip.bounds))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        clip.addSubview(imageView)

        backgroundView = clip
        return true
    }

    private static func aspectFillRect(for imageSize: NSSize, in bounds: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(x: bounds.midX - size.width / 2,
                      y: bounds.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    // MARK: - 顶部时钟

    private func installClock() {
        let time = NSTextField(labelWithString: "")
        time.alignment = .center

        let info = NSTextField(labelWithString: "")
        info.alignment = .center

        // 描边之外再叠一层柔和阴影
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 10
        time.shadow = shadow
        info.shadow = shadow

        container.addSubview(time)
        container.addSubview(info)
        timeLabel = time
        infoLabel = info

        // 时钟组整体往下放：顶部留白约为屏高的 13%，视觉更居中
        let b = container.bounds
        let topPad = max(96, b.height * 0.13)
        time.frame = NSRect(x: b.midX - 260, y: b.height - topPad - 58, width: 520, height: 58)
        info.frame = NSRect(x: b.midX - 260, y: b.height - topPad - 58 - 16 - 22, width: 520, height: 22)
    }

    /// 字幕式文字：白字 + 浓黑外描边（YouTube 字幕级别），亮壁纸/视频上也清晰，无需整片压边。
    private static func subtitleString(_ text: String, fontSize: CGFloat, alpha: CGFloat,
                                       strokeDivider: CGFloat = 8) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: fontSize > 20 ? .light : .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .strokeColor: NSColor.black.withAlphaComponent(0.8),
            .strokeWidth: -fontSize / strokeDivider,  // 负值 = 外描边
        ])
    }

    private func updateClock() {
        let now = Date()
        timeLabel?.attributedStringValue = Self.subtitleString(
            timeFormatter.string(from: now), fontSize: 46, alpha: 0.95
        )
        let minutes = max(0, Int(now.timeIntervalSince(startedAt) / 60))
        let durationText = minutes >= 1
            ? I18N.t("已遮屏 \(minutes) 分钟", "covered \(minutes) min")
            : I18N.t("刚刚开始", "just started")
        infoLabel?.attributedStringValue = Self.subtitleString(
            infoFormatter.string(from: now) + " · " + durationText,
            fontSize: 15, alpha: 0.92, strokeDivider: 5.5  // 小字用更粗的描边才扛得住亮背景
        )
    }

    // MARK: - 底部轮播文案

    private func installMessageCapsule() {
        let capsule = NSView(frame: .zero)
        container.addSubview(capsule)
        capsule.wantsLayer = true
        capsule.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        capsule.layer?.cornerRadius = 16
        capsuleView = capsule

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.95)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0  // 文案必须展示全：不限行数
        capsule.addSubview(label)
        messageLabel = label

        messageIndex = 0
        showCurrentMessage(immediate: true)
    }

    private func showCurrentMessage(immediate: Bool) {
        let messages = Settings.shared.messages
        guard !messages.isEmpty, let label = messageLabel else { return }
        let message = messages[messageIndex % messages.count]
        if immediate {
            label.stringValue = message
            layoutCapsule()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            label.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.messageLabel != nil else { return }
            self.messageLabel?.stringValue = message
            self.layoutCapsule()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                self.messageLabel?.animator().alphaValue = 1
            }
        })
    }

    private func layoutCapsule() {
        guard let capsule = capsuleView, let label = messageLabel else { return }
        let b = container.bounds
        let font = label.font ?? NSFont.systemFont(ofSize: 17)
        let text = label.stringValue as NSString
        guard text.length > 0 else { return }

        // 文案必须展示全：测量值偏小（emoji/字体回退）时靠余量兜底，
        // label 宽度始终给足，文字居中渲染，宁可胶囊略宽也不截字。
        let padding: CGFloat = 22   // 胶囊左右内边距
        let slack: CGFloat = 16     // 测量安全余量
        let maxWidth = min(680, b.width * 0.72) - padding * 2
        let singleSize = text.size(withAttributes: [.font: font])

        if ceil(singleSize.width) <= maxWidth {
            // 单行完整展示
            let textWidth = min(maxWidth, ceil(singleSize.width) + slack)
            let textHeight = ceil(singleSize.height) + 4
            label.frame = NSRect(x: padding, y: 15, width: textWidth, height: textHeight)
            let capsuleWidth = textWidth + padding * 2
            let capsuleHeight = textHeight + 30
            capsule.frame = NSRect(x: b.midX - capsuleWidth / 2, y: 44, width: capsuleWidth, height: capsuleHeight)
        } else {
            // 折行完整展示（不限行数）
            let bounding = text.boundingRect(
                with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            let textWidth = maxWidth + slack
            let textHeight = ceil(bounding.height) + 8
            label.frame = NSRect(x: padding, y: 15, width: textWidth, height: textHeight)
            let capsuleWidth = textWidth + padding * 2 + slack
            let capsuleHeight = textHeight + 30
            capsule.frame = NSRect(x: b.midX - capsuleWidth / 2, y: 44, width: capsuleWidth, height: capsuleHeight)
        }
    }

    // MARK: - 定时器

    private func startTimers() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateClock()
        }
        rotateTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.messageIndex = (self.messageIndex + 1) % max(1, Settings.shared.messages.count)
            self.showCurrentMessage(immediate: false)
        }
        updateClock()
    }
}
