import Cocoa
import UniformTypeIdentifiers

/// 通用设置页：遮屏内容模式、保持亮屏、开机自启、自定义轮播文案。
final class GeneralSettingsViewController: NSViewController, NSTextViewDelegate {

    private var modeButtons: [NSButton] = []
    private var keepAwakeCheck: NSButton!
    private var launchCheck: NSButton!
    private var messagesTextView: NSTextView!
    private var saveButton: NSButton!

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 480))

        // MARK: 遮屏内容
        addLabel(I18N.t("遮屏内容", "Cover content"), to: view,
                 frame: NSRect(x: 24, y: 440, width: 200, height: 18), bold: true)

        let modes: [(ContentMode, String)] = [
            (.aurora, I18N.t("内置极光动画（默认）", "Built-in aurora (default)")),
            (.video, I18N.t("自选视频（循环静音播放）", "Choose video (loops, muted)")),
            (.image, I18N.t("自选图片", "Choose image")),
            (.wallpaper, I18N.t("当前桌面壁纸", "Current wallpaper")),
        ]
        for (index, entry) in modes.enumerated() {
            let button = NSButton(radioButtonWithTitle: entry.1, target: self, action: #selector(modeChanged(_:)))
            button.frame = NSRect(x: 44, y: 410 - index * 26, width: 320, height: 20)
            button.identifier = NSUserInterfaceItemIdentifier(entry.0.rawValue)
            view.addSubview(button)
            modeButtons.append(button)
        }

        addSeparator(to: view, y: 300)

        // MARK: 行为开关
        let keepAwake = NSButton(checkboxWithTitle: I18N.t("遮屏期间保持亮屏", "Keep display awake while covered"),
                                 target: self, action: #selector(toggleKeepAwake(_:)))
        keepAwake.frame = NSRect(x: 24, y: 266, width: 320, height: 20)
        view.addSubview(keepAwake)
        keepAwakeCheck = keepAwake

        addLabel(I18N.t("关闭时遮屏展示会随显示器正常熄屏（其实更隐私）", "When off, the display may sleep normally (arguably more private)"),
                 to: view, frame: NSRect(x: 44, y: 248, width: 460, height: 14), small: true)

        let launch = NSButton(checkboxWithTitle: I18N.t("开机自启", "Launch at login"),
                              target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launch.frame = NSRect(x: 24, y: 218, width: 320, height: 20)
        view.addSubview(launch)
        launchCheck = launch

        addSeparator(to: view, y: 202)

        // MARK: 自定义文案
        addLabel(I18N.t("自定义轮播文案", "Cover messages"), to: view,
                 frame: NSRect(x: 24, y: 172, width: 200, height: 18), bold: true)
        addLabel(I18N.t("每行一句，遮屏时在屏幕底部轮播；清空保存则恢复默认。", "One line per message, rotated at the bottom. Save empty to restore defaults."),
                 to: view, frame: NSRect(x: 24, y: 152, width: 480, height: 14), small: true)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 56, width: 492, height: 90))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 490, height: 88))
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.delegate = self
        scroll.documentView = textView
        view.addSubview(scroll)
        messagesTextView = textView

        let reset = NSButton(title: I18N.t("恢复默认", "Defaults"), target: self, action: #selector(resetMessages))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: 24, y: 18, width: 88, height: 28)
        view.addSubview(reset)

        let save = NSButton(title: I18N.t("保存", "Save"), target: self, action: #selector(saveMessages))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 428, y: 18, width: 88, height: 28)
        save.isEnabled = false
        view.addSubview(save)
        saveButton = save

        self.view = view
        refresh()
    }

    // MARK: - 状态刷新

    private func refresh() {
        refreshModeButtons()
        keepAwakeCheck.state = Settings.shared.keepAwakeWhileCovered ? .on : .off
        launchCheck.state = LaunchAtLogin.isEnabled ? .on : .off
        let custom = Settings.shared.customMessages
        messagesTextView.string = (custom.isEmpty ? Settings.shared.messages : custom).joined(separator: "\n")
        saveButton.isEnabled = false
    }

    private func refreshModeButtons() {
        let mode = Settings.shared.contentMode
        for button in modeButtons {
            guard let raw = button.identifier?.rawValue,
                  let m = ContentMode(rawValue: raw) else { continue }
            button.state = m == mode ? .on : .off
        }
    }

    // MARK: - 动作

    @objc private func modeChanged(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let mode = ContentMode(rawValue: raw) else { return }
        switch mode {
        case .video:
            if let url = Settings.shared.videoURL, FileManager.default.fileExists(atPath: url.path) {
                Settings.shared.contentMode = .video
            } else if let url = pickFile(allowed: [.movie, .video],
                                         message: I18N.t("选择遮屏时循环播放的视频", "Pick a video to loop while covered")) {
                Settings.shared.videoURL = url
                Settings.shared.contentMode = .video
            } else {
                refreshModeButtons()  // 用户取消 → 回退到原模式
                return
            }
        case .image:
            if let url = Settings.shared.imageURL, NSImage(contentsOf: url) != nil {
                Settings.shared.contentMode = .image
            } else if let url = pickFile(allowed: [.image],
                                         message: I18N.t("选择遮屏壁纸图片", "Pick an image for the cover")) {
                Settings.shared.imageURL = url
                Settings.shared.contentMode = .image
            } else {
                refreshModeButtons()
                return
            }
        default:
            Settings.shared.contentMode = mode
        }
        refreshModeButtons()
    }

    private func pickFile(allowed: [UTType], message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowed
        panel.message = message
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @objc private func toggleKeepAwake(_ sender: NSButton) {
        Settings.shared.keepAwakeWhileCovered = sender.state == .on
        if CoverController.shared.isCovered {
            if Settings.shared.keepAwakeWhileCovered {
                KeepAwake.begin()
            } else {
                KeepAwake.end()
            }
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        let target = sender.state == .on
        if LaunchAtLogin.setEnabled(target) {
            // 系统接受后再同步勾选状态
        }
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func saveMessages() {
        let lines = messagesTextView.string
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        Settings.shared.customMessages = lines
        saveButton.isEnabled = false
        Log.app.info("轮播文案已保存（\(lines.count) 条）")
    }

    @objc private func resetMessages() {
        messagesTextView.string = Settings.shared.messages.joined(separator: "\n")
        saveButton.isEnabled = true
    }

    func textDidChange(_ notification: Notification) {
        saveButton.isEnabled = true
    }

    // MARK: - 布局工具

    private func addLabel(_ text: String, to view: NSView, frame: NSRect, bold: Bool = false, small: Bool = false) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        if bold {
            label.font = .systemFont(ofSize: 13, weight: .semibold)
        } else if small {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        view.addSubview(label)
    }

    private func addSeparator(to view: NSView, y: CGFloat) {
        let box = NSBox(frame: NSRect(x: 24, y: y, width: 492, height: 4))
        box.boxType = .separator
        view.addSubview(box)
    }
}
