import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyCenter.shared.onKeyDown = { [weak self] id in
            switch id {
            case ToggleHotkey.id:
                self?.toggleCover()
            case StayAwakeHotkey.id:
                self?.toggleStayAwake()
            default:
                break
            }
        }
        ToggleHotkey.apply(Settings.shared.hotkeyCombo, alertOnFailure: false)
        StayAwakeHotkey.apply(Settings.shared.stayAwakeHotkeyCombo, alertOnFailure: false)
        StayAwakeEngine.shared.onStateChange = { [weak self] in
            self?.refreshStatusIcon()
        }
        StayAwakeEngine.shared.installTriggerObservers()
        setupStatusItem()
        refreshStatusIcon()
        Log.app.info("SakuraVeil 启动完成")

        // 调试入口：`SakuraVeil --show-settings` 启动时直接打开设置窗口
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 遮罩状态下菜单栏不可达，理论上到不了这里；兜底拒绝退出。
        if CoverController.shared.isCovered {
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyCenter.shared.unregisterAll()
        StayAwakeEngine.shared.uninstallTriggerObservers()
        KeepAwake.end()
    }

    /// 保持唤醒状态变化 → 菜单栏图标切换（眼睛斜杠 ↔ 闪电）
    private func refreshStatusIcon() {
        statusItem?.button?.image = StatusBarIcon.makeImage(awake: StayAwakeEngine.shared.isActive)
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusBarIcon.makeImage()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    // MARK: - 动作

    @objc private func toggleCover() {
        CoverController.shared.toggle()
    }

    /// 热键 / 菜单：开启默认时长会话；已有手动会话则结束它
    @objc private func toggleStayAwake() {
        let engine = StayAwakeEngine.shared
        if engine.hasManualSession {
            engine.endManualSession()
        } else {
            let minutes = Settings.shared.stayAwakeDefaultMinutes
            engine.startManualSession(minutes: minutes > 0 ? minutes : nil)
            AppNotifier.requestAuthorizationIfNeeded()
        }
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.syncWindowSize()
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - NSMenuDelegate（每次打开重建，保证状态新鲜）

extension AppDelegate: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let combo = Settings.shared.hotkeyCombo
        let coverTitle = CoverController.shared.isCovered
            ? I18N.t("解除遮屏", "Uncover")
            : I18N.t("立即遮屏", "Cover Now")
        let coverItem = NSMenuItem(title: "\(coverTitle)（\(combo.display)）",
                                   action: #selector(toggleCover), keyEquivalent: "")
        coverItem.target = self
        menu.addItem(coverItem)

        // 保持唤醒子菜单
        let stayItem = NSMenuItem(title: I18N.t("保持唤醒", "Stay Awake"), action: nil, keyEquivalent: "")
        stayItem.submenu = buildStayAwakeSubmenu()
        menu.addItem(stayItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: I18N.t("设置…", "Settings…"),
                                      action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: I18N.t("退出 SakuraVeil", "Quit SakuraVeil"),
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = nil
        menu.addItem(quitItem)
    }

    /// 「保持唤醒 ▸」子菜单：状态行 + 快速时长 + 触发器状态
    private func buildStayAwakeSubmenu() -> NSMenu {
        let sub = NSMenu()
        let engine = StayAwakeEngine.shared

        // 状态行
        let status: String
        if engine.isActive {
            var detail = engine.activeReasonNames.joined(separator: I18N.t("、", ", "))
            if let remain = engine.manualRemainingSeconds {
                detail = I18N.t("剩余 \(remain / 60) 分钟 · ", "\(remain / 60) min left · ") + detail
            }
            status = "⚡︎ " + I18N.t("保持唤醒中（\(detail)）", "Awake (\(detail))")
        } else {
            status = I18N.t("未激活", "Not active")
        }
        let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        sub.addItem(statusItem)
        sub.addItem(.separator())

        // 手动会话控制
        if engine.hasManualSession {
            let end = NSMenuItem(title: I18N.t("结束保持唤醒", "End Stay Awake"),
                                 action: #selector(endStayAwake), keyEquivalent: "")
            end.target = self
            sub.addItem(end)
        } else {
            let minutes: [(Int?, String)] = [
                (30, I18N.t("保持唤醒 30 分钟", "Awake for 30 minutes")),
                (60, I18N.t("保持唤醒 1 小时", "Awake for 1 hour")),
                (120, I18N.t("保持唤醒 2 小时", "Awake for 2 hours")),
                (240, I18N.t("保持唤醒 4 小时", "Awake for 4 hours")),
                (nil, I18N.t("保持唤醒直到我关闭", "Awake until I turn it off")),
            ]
            for (value, title) in minutes {
                let item = NSMenuItem(title: title, action: #selector(startStayAwake(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = value.map { NSNumber(value: $0) }
                sub.addItem(item)
            }
        }

        // 触发器状态（只读）
        sub.addItem(.separator())
        let triggerLines: [(StayAwakeEngine.Reason, Bool)] = [
            (.app, Settings.shared.triggerAppsEnabled),
            (.schedule, Settings.shared.triggerScheduleEnabled),
            (.power, Settings.shared.triggerPowerEnabled),
            (.display, Settings.shared.triggerDisplayEnabled),
        ]
        for (reason, enabled) in triggerLines {
            let on = enabled && engine.isReasonActive(reason)
            let title = enabled
                ? (on ? I18N.t("✓ \(reason.displayName)：生效中", "✓ \(reason.displayName): active")
                      : I18N.t("· \(reason.displayName)：已启用（条件未满足）", "· \(reason.displayName): waiting"))
                : I18N.t("· \(reason.displayName)：未启用", "· \(reason.displayName): off")
            let line = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            sub.addItem(line)
        }
        let hint = NSMenuItem(title: I18N.t("（在设置 → 保持唤醒 中配置）", "(configure in Settings → Stay Awake)"),
                              action: nil, keyEquivalent: "")
        sub.addItem(hint)
        return sub
    }

    @objc private func startStayAwake(_ sender: NSMenuItem) {
        let minutes = (sender.representedObject as? NSNumber)?.intValue
        StayAwakeEngine.shared.startManualSession(minutes: minutes)
        AppNotifier.requestAuthorizationIfNeeded()
    }

    @objc private func endStayAwake() {
        StayAwakeEngine.shared.endManualSession()
    }
}
