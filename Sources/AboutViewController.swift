import Cocoa

/// 关于页：图标、版本、简介、GitHub 链接。内容整体居中，高度贴合内容。
final class AboutViewController: NSViewController {

    static let repoURL = URL(string: "https://github.com/yueseqaz/SakuraVeil")!

    /// 页面固定尺寸（设置窗口按此自适应高度）
    static let pageSize = NSSize(width: 500, height: 252)

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: Self.pageSize))

        // 应用图标
        let icon = NSImageView(frame: NSRect(x: 214, y: 158, width: 72, height: 72))
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(icon)

        // 名称
        let name = NSTextField(labelWithString: "SakuraVeil 樱幕")
        name.frame = NSRect(x: 24, y: 118, width: 452, height: 26)
        name.alignment = .center
        name.font = .systemFont(ofSize: 19, weight: .semibold)
        view.addSubview(name)

        // 版本
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "100"
        let versionLabel = NSTextField(labelWithString: I18N.t("版本 \(version) (\(build))", "Version \(version) (\(build))"))
        versionLabel.frame = NSRect(x: 24, y: 98, width: 452, height: 14)
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        view.addSubview(versionLabel)

        // 简介
        let intro = NSTextField(wrappingLabelWithString: I18N.t(
            "跑任务离开时的一键隐私幕布：动画 / 视频 / 壁纸盖住屏幕，任务在后台照常运行，只有快捷键或密码能解开。",
            "A one-key privacy curtain: cover the screen with an aurora, video or wallpaper while your tasks keep running. Unlock only with the hotkey or your password."
        ))
        intro.frame = NSRect(x: 56, y: 52, width: 388, height: 40)
        intro.alignment = .center
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        view.addSubview(intro)

        // GitHub 链接
        let link = NSButton(target: self, action: #selector(openRepo))
        link.isBordered = false
        link.frame = NSRect(x: 24, y: 26, width: 452, height: 18)
        link.attributedTitle = NSAttributedString(
            string: "github.com/yueseqaz/SakuraVeil",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        view.addSubview(link)

        // 版权
        let copyright = NSTextField(labelWithString: I18N.t("© 2026 Sakura · 用 swiftc 和零依赖打造", "© 2026 Sakura · Made with swiftc and zero dependencies"))
        copyright.frame = NSRect(x: 24, y: 6, width: 452, height: 12)
        copyright.alignment = .center
        copyright.font = .systemFont(ofSize: 10)
        copyright.textColor = .tertiaryLabelColor
        view.addSubview(copyright)

        self.view = view
    }

    @objc private func openRepo() {
        NSWorkspace.shared.open(Self.repoURL)
    }
}
