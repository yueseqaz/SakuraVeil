import Cocoa
import ObjectiveC

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindowController: SettingsWindowController?
    private var rightClickMonitor: Any?
    private var customDurationField: NSTextField?

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
            self?.syncCountdownTimer()
            self?.refreshStatusItem()
        }
        StayAwakeEngine.shared.installTriggerObservers()
        // 设置页切换倒计时/图标相关选项时刷新状态栏
        NotificationCenter.default.addObserver(forName: NSNotification.Name("SakuraVeil.StatusItemChanged"),
                                               object: nil, queue: .main) { [weak self] _ in
            self?.refreshStatusItem()
        }
        setupStatusItem()
        refreshStatusItem()
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
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
        }
        rightClickMonitor = nil
        HotkeyCenter.shared.unregisterAll()
        StayAwakeEngine.shared.uninstallTriggerObservers()
        KeepAwake.end()
    }

    // MARK: - 菜单栏状态（图标 + 倒计时文本）

    private var countdownTimer: Timer?

    /// 手动会话激活时按秒刷新菜单栏剩余时间
    private func syncCountdownTimer() {
        let need = StayAwakeEngine.shared.manualRemainingSeconds != nil
        if need, countdownTimer == nil {
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.refreshStatusItem()
            }
        } else if !need, countdownTimer != nil {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }

    /// 图标：moon.zzz（会睡）/ ⚡（保持唤醒）；title：可选的剩余时间
    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let engine = StayAwakeEngine.shared
        button.image = StatusBarIcon.makeImage(awake: engine.isActive)

        var title = ""
        if Settings.shared.menuBarCountdown, let remain = engine.manualRemainingSeconds {
            let seconds = max(0, remain)
            title = String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        button.title = title
        // NSStatusItemVariableLength(-1) 未暴露给 Swift，直接用数值
        statusItem?.length = title.isEmpty ? NSStatusItem.squareLength : -1
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusBarIcon.makeImage(awake: StayAwakeEngine.shared.isActive)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusMenu = menu
        statusItem = item
        // 状态项按钮换成自定义子类处理左键；
        // 右键在各版本 macOS 上不会派发 rightMouseDown，用本地事件监听统一拦截。
        if let button = item.button {
            object_setClass(button, StatusItemButton.self)
            button.svLeftClickHandler = { [weak self] in
                self?.toggleStayAwake()
            }
        }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseUp, .otherMouseUp]) { [weak self] event in
            guard let self,
                  event.window === self.statusItem?.button?.window else { return event }
            self.popUpStatusMenu()
            return nil  // 吞掉，避免再走按钮事件链
        }
    }

    /// 右键弹出菜单（贴着状态项按钮下缘），关闭后摘掉引用
    private func popUpStatusMenu() {
        guard let item = statusItem, let menu = statusMenu, let button = item.button else { return }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.maxY + 5),
                   in: button)
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

    /// 菜单：按默认时长开始保持唤醒
    @objc private func startDefaultStayAwake() {
        toggleStayAwake()
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

// MARK: - 自定义状态项按钮（左键 = 防休眠开关，右键 = 菜单）
//
// object_setClass 换类时子类不能有存储属性（实例按父类布局分配，越界写会崩），
// 所以闭包用 associated objects 挂载。

final class StatusItemButton: NSStatusBarButton {
    override func mouseDown(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.svLeftClickHandler?()
        }
    }
    // 右键由 AppDelegate 的本地事件监听器处理（rightMouseDown 在状态栏按钮上不可靠）
}

private var svLeftKey: UInt8 = 0

extension NSStatusBarButton {
    var svLeftClickHandler: (() -> Void)? {
        get { objc_getAssociatedObject(self, &svLeftKey) as? (() -> Void) }
        set { objc_setAssociatedObject(self, &svLeftKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - NSMenuDelegate（每次打开重建，保证状态新鲜）

extension AppDelegate: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let engine = StayAwakeEngine.shared
        let combo = Settings.shared.hotkeyCombo

        // ═══ 保持唤醒（主功能）═══
        let statusTitle: String
        if engine.isActive {
            var detail = engine.activeReasonNames.joined(separator: I18N.t("、", ", "))
            if let remain = engine.manualRemainingSeconds {
                detail = String(format: "%d:%02d · ", remain / 60, remain % 60) + detail
            }
            statusTitle = "⚡ " + I18N.t("保持唤醒中（\(detail)）", "Awake (\(detail))")
        } else {
            statusTitle = I18N.t("未在保持唤醒", "Not staying awake")
        }
        menu.addItem(NSMenuItem(title: statusTitle, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        if engine.hasManualSession {
            let remain = engine.manualRemainingSeconds ?? 0
            let end = NSMenuItem(
                title: I18N.t("结束保持唤醒（剩余 \(remain / 60) 分 \(remain % 60) 秒）",
                              "End Stay Awake (\(remain / 60)m \(remain % 60)s left)"),
                action: #selector(endStayAwake), keyEquivalent: "")
            end.target = self
            menu.addItem(end)
        } else {
            let minutes = Settings.shared.stayAwakeDefaultMinutes
            let defaultLabel = minutes > 0
                ? I18N.t("\(minutes) 分钟", "\(minutes) min")
                : I18N.t("直到我关闭", "until I turn it off")
            let quick = NSMenuItem(
                title: I18N.t("开始保持唤醒（\(defaultLabel)）", "Start staying awake (\(defaultLabel))"),
                action: #selector(startDefaultStayAwake), keyEquivalent: "")
            quick.target = self
            menu.addItem(quick)

            let options: [(Int?, String)] = [
                (30, I18N.t("保持唤醒 30 分钟", "Awake for 30 minutes")),
                (60, I18N.t("保持唤醒 1 小时", "Awake for 1 hour")),
                (120, I18N.t("保持唤醒 2 小时", "Awake for 2 hours")),
                (240, I18N.t("保持唤醒 4 小时", "Awake for 4 hours")),
                (nil, I18N.t("保持唤醒直到我关闭", "Awake until I turn it off")),
            ]
            for (value, title) in options {
                let item = NSMenuItem(title: title, action: #selector(startStayAwake(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = value.map { NSNumber(value: $0) }
                menu.addItem(item)
            }

            // 自定义时长：直接嵌在菜单里输入（NSMenuItem.view），回车即开始
            let customRow = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 30))
            let label = NSTextField(labelWithString: I18N.t("自定义", "Custom"))
            label.frame = NSRect(x: 12, y: 8, width: 54, height: 15)
            label.font = .systemFont(ofSize: 12)
            let field = NSTextField(frame: NSRect(x: 70, y: 4, width: 120, height: 22))
            field.placeholderString = I18N.t("90 / 1h30m", "90 / 1h30m")
            field.font = .systemFont(ofSize: 12)
            field.delegate = self
            customRow.addSubview(label)
            customRow.addSubview(field)
            customDurationField = field

            let customItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            customItem.view = customRow
            menu.addItem(customItem)
        }

        // 触发器状态（只读）
        menu.addItem(.separator())
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
            menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: I18N.t("（在设置 → 保持唤醒 中配置）", "(configure in Settings → Stay Awake)"),
                                action: nil, keyEquivalent: ""))

        // ═══ 遮屏（可选功能）═══
        menu.addItem(.separator())
        let coverTitle = CoverController.shared.isCovered
            ? I18N.t("解除遮屏", "Uncover")
            : I18N.t("立即遮屏", "Cover Now")
        let coverItem = NSMenuItem(title: "\(coverTitle)（\(combo.display)）",
                                   action: #selector(toggleCover), keyEquivalent: "")
        coverItem.target = self
        menu.addItem(coverItem)

        menu.addItem(.separator())

        // ═══ 应用 ═══
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

    /// 菜单打开后自动聚焦自定义时长输入框（直接打字，回车即开始）
    func menuDidOpen(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in
            _ = self?.customDurationField?.becomeFirstResponder()
        }
    }

    @objc private func startStayAwake(_ sender: NSMenuItem) {
        let minutes = (sender.representedObject as? NSNumber)?.intValue
        StayAwakeEngine.shared.startManualSession(minutes: minutes)
        AppNotifier.requestAuthorizationIfNeeded()
    }

    @objc private func endStayAwake() {
        StayAwakeEngine.shared.endManualSession()
    }

    /// 解析用户输入的时长：支持 "90"（分钟）、"90m"、"1h"、"1h30m"
    static func parseMinutes(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let minutes = Int(trimmed) { return minutes > 0 ? minutes : nil }
        if let mIndex = trimmed.firstIndex(of: "h") {
            let hours = Int(trimmed[trimmed.startIndex..<mIndex]) ?? -1
            let mins = Int(trimmed[mIndex...].dropFirst().replacingOccurrences(of: "m", with: "")) ?? 0
            guard hours >= 0, hours + mins > 0 else { return nil }
            return hours * 60 + mins
        }
        if trimmed.hasSuffix("m"), let mins = Int(trimmed.dropLast()), mins > 0 {
            return mins
        }
        return nil
    }
}

// MARK: - 菜单内自定义时长输入

extension AppDelegate: NSTextFieldDelegate {

    /// 菜单内输入框按回车 → 解析并开始会话
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === customDurationField else { return false }
        if commandSelector == #selector(NSText.insertNewline(_:)) {
            submitCustomDuration(control as? NSTextField ?? NSTextField())
            return true
        }
        return false
    }

    private func submitCustomDuration(_ field: NSTextField) {
        guard let minutes = AppDelegate.parseMinutes(field.stringValue) else {
            field.stringValue = ""
            field.placeholderString = I18N.t("无效，重试：90 / 1h30m", "Invalid — try 90 / 1h30m")
            return
        }
        field.stringValue = ""
        StayAwakeEngine.shared.startManualSession(minutes: minutes)
        AppNotifier.requestAuthorizationIfNeeded()
        statusMenu?.cancelTracking()  // 关闭菜单，状态交给菜单栏图标
    }
}
