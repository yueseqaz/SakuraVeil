import Cocoa

/// 安全设置页：全局快捷键（录制）+ 解锁密码（Keychain）。
final class SecuritySettingsViewController: NSViewController {

    private var comboLabel: NSTextField!
    private var passwordStatus: NSTextField!
    private var setPasswordButton: NSButton!
    private var clearPasswordButton: NSButton!

    /// 页面固定尺寸（设置窗口按此自适应高度）
    static let pageSize = NSSize(width: 500, height: 268)

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: Self.pageSize))

        // MARK: 全局快捷键
        addLabel(I18N.t("全局快捷键", "Global hotkey"), to: view,
                 frame: NSRect(x: 24, y: 228, width: 200, height: 18), bold: true)
        addLabel(I18N.t("遮屏 / 解除共用同一个组合键；需包含 ⌘ / ⌥ / ⌃ 之一。", "One combo toggles the cover; must include ⌘, ⌥ or ⌃."),
                 to: view, frame: NSRect(x: 24, y: 208, width: 452, height: 14), small: true)

        comboLabel = NSTextField(labelWithString: "")
        comboLabel.frame = NSRect(x: 24, y: 158, width: 320, height: 40)
        comboLabel.font = .monospacedDigitSystemFont(ofSize: 27, weight: .medium)
        view.addSubview(comboLabel)

        let changeHotkeyButton = NSButton(title: I18N.t("修改快捷键…", "Change hotkey…"),
                                          target: self, action: #selector(changeHotkey))
        changeHotkeyButton.bezelStyle = .rounded
        changeHotkeyButton.frame = NSRect(x: 372, y: 164, width: 104, height: 28)
        view.addSubview(changeHotkeyButton)

        addSeparator(to: view, y: 142)

        // MARK: 解锁密码
        addLabel(I18N.t("解锁密码", "Unlock password"), to: view,
                 frame: NSRect(x: 24, y: 112, width: 200, height: 18), bold: true)

        passwordStatus = NSTextField(labelWithString: "")
        passwordStatus.frame = NSRect(x: 24, y: 90, width: 452, height: 14)
        passwordStatus.font = .systemFont(ofSize: 11)
        passwordStatus.textColor = .secondaryLabelColor
        view.addSubview(passwordStatus)

        setPasswordButton = NSButton(title: "", target: self, action: #selector(setPassword))
        setPasswordButton.bezelStyle = .rounded
        setPasswordButton.frame = NSRect(x: 24, y: 52, width: 104, height: 28)
        view.addSubview(setPasswordButton)

        clearPasswordButton = NSButton(title: I18N.t("清除密码", "Remove password"),
                                       target: self, action: #selector(clearPassword))
        clearPasswordButton.bezelStyle = .rounded
        clearPasswordButton.frame = NSRect(x: 136, y: 52, width: 104, height: 28)
        view.addSubview(clearPasswordButton)

        addLabel(I18N.t("密码只保存在本机 Keychain；连错 5 次锁定 30 秒。", "Stored only in your Keychain; 5 wrong attempts lock input for 30s."),
                 to: view, frame: NSRect(x: 24, y: 24, width: 452, height: 14), small: true)

        self.view = view
        preferredContentSize = Self.pageSize  // 供设置窗口贴合高度（子 view 会被拉伸，不能用 frame）
        refresh()
    }

    private func refresh() {
        comboLabel.stringValue = Settings.shared.hotkeyCombo.display

        let hasPassword = KeychainStore.shared.get(forAccount: PasswordPanel.passwordAccount) != nil
        passwordStatus.stringValue = hasPassword
            ? I18N.t("已设置（存于 Keychain）· 遮屏时按任意键唤出输入框", "Set (in Keychain) · press any key while covered to unlock")
            : I18N.t("未设置 · 遮屏时仅快捷键可解除", "Not set · hotkey is the only way out")
        setPasswordButton.title = hasPassword
            ? I18N.t("修改密码…", "Change password…")
            : I18N.t("设置密码…", "Set password…")
        clearPasswordButton.isEnabled = hasPassword
    }

    // MARK: - 快捷键

    @objc private func changeHotkey() {
        // 录制期间暂停旧热键，避免按到旧组合时误触发遮屏
        HotkeyCenter.shared.unregister(id: ToggleHotkey.id)
        HotkeyRecorder.shared.begin(
            current: Settings.shared.hotkeyCombo,
            onCancel: { [weak self] in
                ToggleHotkey.apply(Settings.shared.hotkeyCombo, alertOnFailure: false)
                self?.refresh()
            },
            onRecorded: { [weak self] combo in
                if ToggleHotkey.apply(combo, alertOnFailure: true) {
                    Settings.shared.hotkeyCombo = combo
                    Log.app.info("快捷键已更新为 \(combo.display, privacy: .public)")
                } else {
                    ToggleHotkey.apply(Settings.shared.hotkeyCombo, alertOnFailure: false)
                }
                self?.refresh()
            }
        )
    }

    // MARK: - 密码

    @objc private func setPassword() {
        let hasPassword = KeychainStore.shared.get(forAccount: PasswordPanel.passwordAccount) != nil
        let alert = NSAlert()
        alert.messageText = hasPassword
            ? I18N.t("修改解锁密码", "Change unlock password")
            : I18N.t("设置解锁密码", "Set unlock password")
        alert.informativeText = I18N.t(
            "遮屏时按任意键可唤出密码解锁；建议不要使用系统登录密码。",
            "Press any key while covered to unlock. Don't reuse your login password."
        )

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        let field1 = NSSecureTextField(frame: NSRect(x: 0, y: 32, width: 260, height: 22))
        field1.placeholderString = I18N.t("密码", "Password")
        let field2 = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field2.placeholderString = I18N.t("再输一遍", "Repeat password")
        accessory.addSubview(field1)
        accessory.addSubview(field2)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = field1
        alert.addButton(withTitle: I18N.t("保存", "Save"))
        alert.addButton(withTitle: I18N.t("取消", "Cancel"))

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let password = field1.stringValue
        guard !password.isEmpty else {
            showAlert(I18N.t("密码不能为空", "Password can't be empty"))
            return
        }
        guard password == field2.stringValue else {
            showAlert(I18N.t("两次输入不一致", "Passwords don't match"))
            return
        }
        do {
            try KeychainStore.shared.set(password, forAccount: PasswordPanel.passwordAccount)
            Log.security.info("解锁密码已更新")
        } catch {
            showAlert(I18N.t("密码保存失败：\(error.localizedDescription)",
                             "Failed to save password: \(error.localizedDescription)"))
        }
        refresh()
    }

    @objc private func clearPassword() {
        KeychainStore.shared.delete(forAccount: PasswordPanel.passwordAccount)
        Log.security.info("解锁密码已清除")
        refresh()
    }

    private func showAlert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
