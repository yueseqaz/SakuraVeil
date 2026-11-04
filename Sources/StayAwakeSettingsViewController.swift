import Cocoa

/// 保持唤醒设置页：手动会话、菜单栏倒计时、热键、触发器、开机自启。
final class StayAwakeSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private var defaultDurationPopup: NSPopUpButton!
    private var endActionPopup: NSPopUpButton!
    private var notifyCheck: NSButton!
    private var countdownCheck: NSButton!
    private var hotkeyLabel: NSTextField!
    private var launchCheck: NSButton!

    private var appsCheck: NSButton!
    private var appsTable: NSTableView!
    private var removeAppButton: NSButton!
    private var scheduleCheck: NSButton!
    private var scheduleStartPicker: NSDatePicker!
    private var scheduleEndPicker: NSDatePicker!
    private var powerCheck: NSButton!
    private var displayCheck: NSButton!

    /// 页面固定尺寸（设置窗口按此自适应高度）
    static let pageSize = NSSize(width: 500, height: 510)

    private static let durationOptions: [(Int?, String)] = [
        (30, I18N.t("30 分钟", "30 minutes")),
        (60, I18N.t("1 小时", "1 hour")),
        (120, I18N.t("2 小时", "2 hours")),
        (240, I18N.t("4 小时", "4 hours")),
        (nil, I18N.t("直到我关闭", "Until I turn it off")),
    ]

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: Self.pageSize))

        // MARK: 手动会话
        addLabel(I18N.t("手动会话", "Manual session"), to: view,
                 frame: NSRect(x: 24, y: 472, width: 200, height: 18), bold: true)

        addLabel(I18N.t("默认时长", "Default duration"), to: view,
                 frame: NSRect(x: 24, y: 440, width: 90, height: 18))
        defaultDurationPopup = NSPopUpButton(frame: NSRect(x: 120, y: 434, width: 150, height: 26))
        for (_, title) in Self.durationOptions {
            defaultDurationPopup.addItem(withTitle: title)
        }
        defaultDurationPopup.target = self
        defaultDurationPopup.action = #selector(defaultDurationChanged(_:))
        view.addSubview(defaultDurationPopup)

        addLabel(I18N.t("到点动作", "When it ends"), to: view,
                 frame: NSRect(x: 24, y: 406, width: 90, height: 18))
        endActionPopup = NSPopUpButton(frame: NSRect(x: 120, y: 400, width: 150, height: 26))
        for action in [StayAwakeEndAction.none, .sleep, .displaySleep] {
            endActionPopup.addItem(withTitle: action.displayName)
            endActionPopup.lastItem?.representedObject = action.rawValue
        }
        endActionPopup.target = self
        endActionPopup.action = #selector(endActionChanged(_:))
        view.addSubview(endActionPopup)

        notifyCheck = NSButton(checkboxWithTitle: I18N.t("会话结束时发送系统通知", "Send a notification when the session ends"),
                               target: self, action: #selector(toggleNotify(_:)))
        notifyCheck.frame = NSRect(x: 24, y: 374, width: 452, height: 20)
        view.addSubview(notifyCheck)

        countdownCheck = NSButton(checkboxWithTitle: I18N.t("菜单栏显示剩余时间（⚡ 59:12）", "Show remaining time in the menu bar (⚡ 59:12)"),
                                  target: self, action: #selector(toggleCountdown(_:)))
        countdownCheck.frame = NSRect(x: 24, y: 350, width: 452, height: 20)
        view.addSubview(countdownCheck)

        addLabel(I18N.t("开关热键", "Toggle hotkey"), to: view,
                 frame: NSRect(x: 24, y: 318, width: 90, height: 18))
        hotkeyLabel = NSTextField(labelWithString: "")
        hotkeyLabel.frame = NSRect(x: 120, y: 316, width: 140, height: 22)
        hotkeyLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        view.addSubview(hotkeyLabel)

        let changeHotkey = NSButton(title: I18N.t("修改…", "Change…"), target: self, action: #selector(changeHotkey))
        changeHotkey.bezelStyle = .rounded
        changeHotkey.frame = NSRect(x: 268, y: 312, width: 80, height: 26)
        view.addSubview(changeHotkey)

        launchCheck = NSButton(checkboxWithTitle: I18N.t("开机自启", "Launch at login"),
                               target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launchCheck.frame = NSRect(x: 24, y: 286, width: 452, height: 20)
        view.addSubview(launchCheck)

        addSeparator(to: view, y: 270)

        // MARK: 触发器
        addLabel(I18N.t("触发器", "Triggers"), to: view,
                 frame: NSRect(x: 24, y: 242, width: 200, height: 18), bold: true)

        appsCheck = NSButton(checkboxWithTitle: I18N.t("App 触发器：以下应用运行时保持唤醒", "App trigger: stay awake while these apps run"),
                             target: self, action: #selector(toggleAppsTrigger(_:)))
        appsCheck.frame = NSRect(x: 24, y: 214, width: 452, height: 20)
        view.addSubview(appsCheck)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 120, width: 330, height: 88))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let table = NSTableView(frame: .zero)
        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = 30
        table.allowsMultipleSelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.width = 320
        table.addTableColumn(column)
        scroll.documentView = table
        view.addSubview(scroll)
        appsTable = table

        let addAppButton = NSButton(title: I18N.t("添加 App…", "Add App…"), target: self, action: #selector(addApp))
        addAppButton.bezelStyle = .rounded
        addAppButton.frame = NSRect(x: 366, y: 146, width: 110, height: 26)
        view.addSubview(addAppButton)

        removeAppButton = NSButton(title: I18N.t("移除", "Remove"), target: self, action: #selector(removeSelectedApp))
        removeAppButton.bezelStyle = .rounded
        removeAppButton.frame = NSRect(x: 366, y: 114, width: 110, height: 26)
        removeAppButton.isEnabled = false
        view.addSubview(removeAppButton)

        scheduleCheck = NSButton(checkboxWithTitle: I18N.t("日程触发器：每天此时间段保持唤醒", "Schedule trigger: stay awake daily during"),
                                 target: self, action: #selector(toggleScheduleTrigger(_:)))
        scheduleCheck.frame = NSRect(x: 24, y: 90, width: 452, height: 20)
        view.addSubview(scheduleCheck)

        scheduleStartPicker = makeTimePicker(frame: NSRect(x: 24, y: 56, width: 70, height: 24),
                                             onChange: #selector(scheduleTimeChanged(_:)))
        scheduleEndPicker = makeTimePicker(frame: NSRect(x: 132, y: 56, width: 70, height: 24),
                                           onChange: #selector(scheduleTimeChanged(_:)))
        view.addSubview(scheduleStartPicker)
        view.addSubview(scheduleEndPicker)
        addLabel(I18N.t("开始", "from"), to: view,
                 frame: NSRect(x: 98, y: 59, width: 30, height: 18), small: true)
        addLabel(I18N.t("到", "to"), to: view,
                 frame: NSRect(x: 208, y: 59, width: 20, height: 18), small: true)

        powerCheck = NSButton(checkboxWithTitle: I18N.t("接通电源时", "On AC power"),
                              target: self, action: #selector(togglePowerTrigger(_:)))
        powerCheck.frame = NSRect(x: 244, y: 56, width: 120, height: 20)
        view.addSubview(powerCheck)

        displayCheck = NSButton(checkboxWithTitle: I18N.t("外接显示器接入时保持唤醒", "Stay awake when an external display is connected"),
                                target: self, action: #selector(toggleDisplayTrigger(_:)))
        displayCheck.frame = NSRect(x: 24, y: 26, width: 452, height: 20)
        view.addSubview(displayCheck)

        addLabel(I18N.t("合盖运行 = 接通电源 + 外接显示器 + 防系统睡眠同时满足；注意散热。", "Clamshell = AC power + external display + no system sleep. Mind the heat."),
                 to: view, frame: NSRect(x: 24, y: 8, width: 460, height: 14), small: true)

        self.view = view
        preferredContentSize = Self.pageSize
        refresh()
    }

    private func makeTimePicker(frame: NSRect, onChange: Selector) -> NSDatePicker {
        let picker = NSDatePicker(frame: frame)
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.datePickerMode = .single
        picker.target = self
        picker.action = onChange
        picker.locale = Locale(identifier: "en_US_POSIX")
        return picker
    }

    // MARK: - 状态刷新

    private func refresh() {
        if let index = Self.durationOptions.firstIndex(where: { $0.0 == Settings.shared.stayAwakeDefaultMinutes }) {
            defaultDurationPopup.selectItem(at: index)
        }
        endActionPopup.selectItem(at: [StayAwakeEndAction.none, .sleep, .displaySleep]
            .firstIndex(of: Settings.shared.stayAwakeEndAction) ?? 0)
        notifyCheck.state = Settings.shared.stayAwakeNotify ? .on : .off
        countdownCheck.state = Settings.shared.menuBarCountdown ? .on : .off
        hotkeyLabel.stringValue = Settings.shared.stayAwakeHotkeyCombo.display
        launchCheck.state = LaunchAtLogin.isEnabled ? .on : .off

        appsCheck.state = Settings.shared.triggerAppsEnabled ? .on : .off
        appsTable.reloadData()
        scheduleCheck.state = Settings.shared.triggerScheduleEnabled ? .on : .off
        scheduleStartPicker.dateValue = Self.date(fromMinutes: Settings.shared.triggerScheduleStart)
        scheduleEndPicker.dateValue = Self.date(fromMinutes: Settings.shared.triggerScheduleEnd)
        powerCheck.state = Settings.shared.triggerPowerEnabled ? .on : .off
        displayCheck.state = Settings.shared.triggerDisplayEnabled ? .on : .off
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        let comps = DateComponents(hour: min(23, minutes / 60), minute: minutes % 60)
        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func minutes(fromDate date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - 动作

    @objc private func defaultDurationChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        Settings.shared.stayAwakeDefaultMinutes = Self.durationOptions[index].0 ?? 60
    }

    @objc private func endActionChanged(_ sender: NSPopUpButton) {
        if let raw = sender.selectedItem?.representedObject as? String,
           let action = StayAwakeEndAction(rawValue: raw) {
            Settings.shared.stayAwakeEndAction = action
        }
    }

    @objc private func toggleNotify(_ sender: NSButton) {
        Settings.shared.stayAwakeNotify = sender.state == .on
        if sender.state == .on {
            AppNotifier.requestAuthorizationIfNeeded()
        }
    }

    @objc private func toggleCountdown(_ sender: NSButton) {
        Settings.shared.menuBarCountdown = sender.state == .on
        NotificationCenter.default.post(name: NSNotification.Name("SakuraVeil.StatusItemChanged"), object: nil)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        LaunchAtLogin.setEnabled(sender.state == .on)
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func changeHotkey() {
        HotkeyCenter.shared.unregister(id: StayAwakeHotkey.id)
        HotkeyRecorder.shared.begin(
            current: Settings.shared.stayAwakeHotkeyCombo,
            onCancel: { [weak self] in
                StayAwakeHotkey.apply(Settings.shared.stayAwakeHotkeyCombo, alertOnFailure: false)
                self?.refresh()
            },
            onRecorded: { [weak self] combo in
                if StayAwakeHotkey.apply(combo, alertOnFailure: true) {
                    Settings.shared.stayAwakeHotkeyCombo = combo
                    Log.app.info("保持唤醒热键已更新为 \(combo.display, privacy: .public)")
                } else {
                    StayAwakeHotkey.apply(Settings.shared.stayAwakeHotkeyCombo, alertOnFailure: false)
                }
                self?.refresh()
            }
        )
    }

    @objc private func toggleAppsTrigger(_ sender: NSButton) {
        Settings.shared.triggerAppsEnabled = sender.state == .on
        StayAwakeEngine.shared.refreshAppTrigger()
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.message = I18N.t("选择需要保持唤醒的应用", "Pick an app that should keep the Mac awake")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url) else { return }
        var apps = Settings.shared.triggerApps
        let bundleID = bundle.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        guard !apps.contains(where: { $0.bundleID == bundleID }) else { return }
        apps.append(TriggerApp(bundleID: bundleID, name: name))
        Settings.shared.triggerApps = apps
        appsTable.reloadData()
        StayAwakeEngine.shared.refreshAppTrigger()
        Log.app.info("App 触发器已添加 \(name, privacy: .public)")
    }

    @objc private func removeSelectedApp() {
        var apps = Settings.shared.triggerApps
        guard appsTable.selectedRow >= 0, appsTable.selectedRow < apps.count else { return }
        let removed = apps.remove(at: appsTable.selectedRow)
        Settings.shared.triggerApps = apps
        appsTable.reloadData()
        removeAppButton.isEnabled = false
        StayAwakeEngine.shared.refreshAppTrigger()
        Log.app.info("App 触发器已移除 \(removed.name, privacy: .public)")
    }

    @objc private func toggleScheduleTrigger(_ sender: NSButton) {
        Settings.shared.triggerScheduleEnabled = sender.state == .on
        StayAwakeEngine.shared.refreshScheduleTrigger()
    }

    @objc private func scheduleTimeChanged(_ sender: NSDatePicker) {
        Settings.shared.triggerScheduleStart = Self.minutes(fromDate: scheduleStartPicker.dateValue)
        Settings.shared.triggerScheduleEnd = Self.minutes(fromDate: scheduleEndPicker.dateValue)
        StayAwakeEngine.shared.refreshScheduleTrigger()
    }

    @objc private func togglePowerTrigger(_ sender: NSButton) {
        Settings.shared.triggerPowerEnabled = sender.state == .on
        StayAwakeEngine.shared.refreshPowerTrigger()
    }

    @objc private func toggleDisplayTrigger(_ sender: NSButton) {
        Settings.shared.triggerDisplayEnabled = sender.state == .on
        StayAwakeEngine.shared.refreshDisplayTrigger()
    }

    // MARK: - App 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        Settings.shared.triggerApps.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let apps = Settings.shared.triggerApps
        guard row < apps.count else { return nil }
        let app = apps[row]
        let cell = NSTableCellView()
        let name = NSTextField(labelWithString: app.name)
        name.font = .systemFont(ofSize: 13)
        name.frame = NSRect(x: 4, y: 14, width: 310, height: 15)
        let bundle = NSTextField(labelWithString: app.bundleID)
        bundle.font = .systemFont(ofSize: 10)
        bundle.textColor = .secondaryLabelColor
        bundle.frame = NSRect(x: 4, y: 2, width: 310, height: 12)
        cell.addSubview(name)
        cell.addSubview(bundle)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeAppButton.isEnabled = appsTable.selectedRow >= 0
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
