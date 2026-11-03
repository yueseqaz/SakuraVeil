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
        installScrims()
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

    /// 顶部/底部渐暗压边：保证时钟与文案在亮色壁纸/视频上也可读。
    private func installScrims() {
        let b = container.bounds
        installScrim(frame: NSRect(x: 0, y: b.height - 300, width: b.width, height: 300),
                     from: NSColor.black.withAlphaComponent(0.45),
                     to: NSColor.black.withAlphaComponent(0))
        installScrim(frame: NSRect(x: 0, y: 0, width: b.width, height: 200),
                     from: NSColor.black.withAlphaComponent(0),
                     to: NSColor.black.withAlphaComponent(0.45))
    }

    private func installScrim(frame: NSRect, from: NSColor, to: NSColor) {
        let view = NSView(frame: frame)
        container.addSubview(view)
        view.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = view.bounds
        gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        gradient.colors = [from.cgColor, to.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer?.addSublayer(gradient)
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
        time.font = NSFont.monospacedDigitSystemFont(ofSize: 46, weight: .light)
        time.textColor = NSColor.white.withAlphaComponent(0.92)
        time.alignment = .center

        let info = NSTextField(labelWithString: "")
        info.font = .systemFont(ofSize: 15, weight: .regular)
        info.textColor = NSColor.white.withAlphaComponent(0.62)
        info.alignment = .center

        // 白字加阴影，任何背景都可读
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 5
        time.shadow = shadow
        info.shadow = shadow

        container.addSubview(time)
        container.addSubview(info)
        timeLabel = time
        infoLabel = info

        let b = container.bounds
        time.frame = NSRect(x: b.midX - 260, y: b.height - 138, width: 520, height: 58)
        info.frame = NSRect(x: b.midX - 260, y: b.height - 76, width: 520, height: 22)
    }

    private func updateClock() {
        let now = Date()
        timeLabel?.stringValue = timeFormatter.string(from: now)
        let minutes = max(0, Int(now.timeIntervalSince(startedAt) / 60))
        let durationText = minutes >= 1
            ? I18N.t("已遮屏 \(minutes) 分钟", "covered \(minutes) min")
            : I18N.t("刚刚开始", "just started")
        infoLabel?.stringValue = infoFormatter.string(from: now) + " · " + durationText
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
        label.maximumNumberOfLines = 2
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
        let maxWidth = min(680, b.width * 0.72) - 44

        // TextKit 测量（正确处理中英混排与字体回退），超宽自动折行
        let text = label.stringValue as NSString
        let bounding = text.boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let textWidth = min(maxWidth, ceil(bounding.width) + 4)
        let textHeight = max(ceil(bounding.height), 22)

        label.frame = NSRect(x: 22, y: 15, width: textWidth, height: textHeight)
        let capsuleWidth = textWidth + 44
        let capsuleHeight = textHeight + 30
        capsule.frame = NSRect(x: b.midX - capsuleWidth / 2, y: 44, width: capsuleWidth, height: capsuleHeight)
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
