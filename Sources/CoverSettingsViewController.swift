import Cocoa
import UniformTypeIdentifiers

/// 遮屏设置页：内容模式、遮屏联动、自定义轮播文案。
final class CoverSettingsViewController: NSViewController {

    private var modeButtons: [NSButton] = []
    private var coverSleepCheck: NSButton!
    private var coverDisplayCheck: NSButton!
    private var messagesTextView: NSTextView!
    private var saveButton: NSButton!

    /// 页面固定尺寸（设置窗口按此自适应高度）
    static let pageSize = NSSize(width: 500, height: 430)

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: Self.pageSize))

        // MARK: 遮屏联动
        addLabel(I18N.t("遮屏联动", "Cover link"), to: view,
                 frame: NSRect(x: 24, y: 392, width: 200, height: 18), bold: true)

        coverSleepCheck = NSButton(checkboxWithTitle: I18N.t("遮屏时防止系统睡眠（任务不断线）", "Prevent system sleep while covered (keep tasks running)"),
                                   target: self, action: #selector(toggleCoverSleep(_:)))
        coverSleepCheck.frame = NSRect(x: 24, y: 364, width: 452, height: 20)
        view.addSubview(coverSleepCheck)

        coverDisplayCheck = NSButton(checkboxWithTitle: I18N.t("遮屏期间保持亮屏", "Keep display awake while covered"),
                                     target: self, action: #selector(toggleCoverDisplay(_:)))
        coverDisplayCheck.frame = NSRect(x: 24, y: 338, width: 452, height: 20)
        view.addSubview(coverDisplayCheck)

        addSeparator(to: view, y: 322)

        // MARK: 遮屏内容
        addLabel(I18N.t("遮屏内容", "Cover content"), to: view,
                 frame: NSRect(x: 24, y: 294, width: 200, height: 18), bold: true)

        let modes: [(ContentMode, String)] = [
            (.aurora, I18N.t("内置极光动画（默认）", "Built-in aurora (default)")),
            (.video, I18N.t("自选视频（循环、静音）", "Choose video (loops, muted)")),
            (.image, I18N.t("自选图片", "Choose image")),
            (.wallpaper, I18N.t("当前桌面壁纸", "Current wallpaper")),
        ]
        for (index, entry) in modes.enumerated() {
            let button = NSButton(radioButtonWithTitle: entry.1, target: self, action: #selector(modeChanged(_:)))
            button.frame = NSRect(x: 42, y: 266 - index * 26, width: 360, height: 20)
            button.identifier = NSUserInterfaceItemIdentifier(entry.0.rawValue)
            view.addSubview(button)
            modeButtons.append(button)
        }

        addSeparator(to: view, y: 156)

        // MARK: 自定义文案
        addLabel(I18N.t("自定义轮播文案", "Cover messages"), to: view,
                 frame: NSRect(x: 24, y: 128, width: 200, height: 18), bold: true)
        addLabel(I18N.t("每行一句，遮屏时在屏幕底部轮播；清空保存则恢复默认。", "One line per message, rotated at the bottom. Save empty to restore defaults."),
                 to: view, frame: NSRect(x: 24, y: 110, width: 460, height: 14), small: true)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 40, width: 452, height: 64))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 450, height: 62))
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.delegate = self
        scroll.documentView = textView
        view.addSubview(scroll)
        messagesTextView = textView

        let reset = NSButton(title: I18N.t("恢复默认", "Defaults"), target: self, action: #selector(resetMessages))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: 24, y: 8, width: 86, height: 26)
        view.addSubview(reset)

        saveButton = NSButton(title: I18N.t("保存", "Save"), target: self, action: #selector(saveMessages))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 390, y: 8, width: 86, height: 26)
        saveButton.isEnabled = false
        view.addSubview(saveButton)

        self.view = view
        preferredContentSize = Self.pageSize
        refresh()
    }

    // MARK: - 状态刷新

    private func refresh() {
        refreshModeButtons()
        coverSleepCheck.state = Settings.shared.coverPreventSystemSleep ? .on : .off
        coverDisplayCheck.state = Settings.shared.keepAwakeWhileCovered ? .on : .off
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
            } else if let picked = pickFile(allowed: [.movie, .video],
                                            message: I18N.t("选择遮屏时循环播放的视频", "Pick a video to loop while covered")),
                      let persisted = Self.persistMedia(from: picked, kind: "video") {
                Settings.shared.videoURL = persisted
                Settings.shared.contentMode = .video
            } else {
                refreshModeButtons()  // 用户取消 / 拷贝失败 → 回退到原模式
                return
            }
        case .image:
            if let url = Settings.shared.imageURL, NSImage(contentsOf: url) != nil {
                Settings.shared.contentMode = .image
            } else if let picked = pickFile(allowed: [.image],
                                            message: I18N.t("选择遮屏壁纸图片", "Pick an image for the cover")),
                      let persisted = Self.persistMedia(from: picked, kind: "image") {
                Settings.shared.imageURL = persisted
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

    /// 把用户选的媒体拷进 Application Support：之后播放/壁纸只读自己的目录，
    /// 不再反复触发「下载文件夹」的 TCC 授权（重建后也不会重弹）。
    private static func persistMedia(from source: URL, kind: String) -> URL? {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SakuraVeil/media", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Log.app.error("媒体目录创建失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
        let ext = source.pathExtension.isEmpty ? (kind == "video" ? "mp4" : "png") : source.pathExtension
        let dest = dir.appendingPathComponent("\(kind).\(ext)")
        try? FileManager.default.removeItem(at: dest)  // 覆盖旧的
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            Log.app.info("媒体已入库：\(dest.lastPathComponent, privacy: .public)")
            return dest
        } catch {
            Log.app.error("媒体拷贝失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @objc private func toggleCoverSleep(_ sender: NSButton) {
        Settings.shared.coverPreventSystemSleep = sender.state == .on
        if CoverController.shared.isCovered {
            StayAwakeEngine.shared.setTrigger(.cover, active: sender.state == .on)
        }
    }

    @objc private func toggleCoverDisplay(_ sender: NSButton) {
        Settings.shared.keepAwakeWhileCovered = sender.state == .on
        if CoverController.shared.isCovered {
            if Settings.shared.keepAwakeWhileCovered {
                KeepAwake.begin()
            } else {
                KeepAwake.end()
            }
        }
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
        let box = NSBox(frame: NSRect(x: 24, y: y, width: 452, height: 4))
        box.boxType = .separator
        view.addSubview(box)
    }
}

extension CoverSettingsViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        saveButton.isEnabled = true
    }
}
