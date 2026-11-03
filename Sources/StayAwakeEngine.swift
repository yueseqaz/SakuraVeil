import Cocoa
import Carbon.HIToolbox
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

/// 保持唤醒引擎（Amphetamine 式功能）：多「理由」计数模型 ——
/// 任一理由活跃（手动会话 / App 触发器 / 日程 / 电源 / 外接显示器 / 遮屏联动），
/// 就持有一条系统唤醒断言（PreventUserIdleSystemSleep），任务不会被睡眠打断。
/// 全部理由退出后释放断言。引擎方法须在主线程调用。
final class StayAwakeEngine {

    static let shared = StayAwakeEngine()

    enum Reason: String, CaseIterable {
        case manual     // 手动会话（有限 / 无限期）
        case app        // App 触发器
        case schedule   // 日程触发器
        case power      // 接通电源触发器
        case display    // 外接显示器触发器
        case cover      // 遮屏联动（防止系统睡眠）

        var displayName: String {
            switch self {
            case .manual: return I18N.t("手动会话", "Manual session")
            case .app: return I18N.t("App 触发器", "App trigger")
            case .schedule: return I18N.t("日程触发器", "Schedule trigger")
            case .power: return I18N.t("接通电源", "AC power")
            case .display: return I18N.t("外接显示器", "External display")
            case .cover: return I18N.t("遮屏联动", "Cover link")
            }
        }
    }

    private var activeReasons: [Reason: Date] = [:]   // 激活时刻
    private var manualExpiry: Date?
    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var tickTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// 状态变化回调（主线程）：刷新菜单与菜单栏图标。
    var onStateChange: (() -> Void)?

    private init() {}

    // MARK: - 状态查询

    var isActive: Bool { !activeReasons.isEmpty }

    /// 当前是否有手动会话（热键 toggle 用）
    var hasManualSession: Bool { activeReasons[.manual] != nil }

    /// 手动会话剩余秒数（没有手动会话时为 nil）
    var manualRemainingSeconds: Int? {
        guard let expiry = manualExpiry else { return nil }
        return max(0, Int(ceil(expiry.timeIntervalSinceNow)))
    }

    var activeReasonNames: [String] {
        Reason.allCases
            .filter { activeReasons[$0] != nil }
            .map { $0.displayName }
    }

    /// 某个理由当前是否活跃（菜单状态行用）
    func isReasonActive(_ reason: Reason) -> Bool {
        activeReasons[reason] != nil
    }

    // MARK: - 手动会话

    /// minutes 为 nil 表示「直到我关闭」
    func startManualSession(minutes: Int?) {
        manualExpiry = minutes.map { Date().addingTimeInterval(TimeInterval($0) * 60) }
        activeReasons[.manual] = Date()
        if let minutes {
            Log.app.info("手动保持唤醒：\(minutes) 分钟")
        } else {
            Log.app.info("手动保持唤醒：无限期")
        }
        updateAssertion()
        onStateChange?()
    }

    func endManualSession() {
        guard activeReasons.removeValue(forKey: .manual) != nil else { return }
        manualExpiry = nil
        Log.app.info("手动保持唤醒已结束")
        updateAssertion()
        onStateChange?()
    }

    // MARK: - 触发器

    func setTrigger(_ reason: Reason, active: Bool) {
        let changed: Bool
        if active {
            changed = activeReasons[reason] == nil
            if changed { activeReasons[reason] = Date() }
        } else {
            changed = activeReasons.removeValue(forKey: reason) != nil
        }
        guard changed else { return }
        Log.app.info("触发器 \(reason.rawValue, privacy: .public) → \(active)")
        updateAssertion()
        onStateChange?()
    }

    // MARK: - 生命周期

    /// AppDelegate 启动时调用：安装各类触发器观察者并做首次评估。
    func installTriggerObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        let refreshApps: (Notification) -> Void = { [weak self] _ in
            self?.refreshAppTrigger()
        }
        observers.append(ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                        object: nil, queue: .main, using: refreshApps))
        observers.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                        object: nil, queue: .main, using: refreshApps))

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.refreshDisplayTrigger()
        }

        startMonitoring()

        refreshAppTrigger()
        refreshDisplayTrigger()
        refreshScheduleTrigger()
        refreshPowerTrigger()
    }

    func uninstallTriggerObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - 各触发器刷新

    func refreshAppTrigger() {
        guard Settings.shared.triggerAppsEnabled else {
            setTrigger(.app, active: false)
            return
        }
        let configured = Set(Settings.shared.triggerApps.map { $0.bundleID })
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        setTrigger(.app, active: !configured.isDisjoint(with: running))
    }

    func refreshDisplayTrigger() {
        guard Settings.shared.triggerDisplayEnabled else {
            setTrigger(.display, active: false)
            return
        }
        setTrigger(.display, active: NSScreen.screens.count > 1)
    }

    func refreshScheduleTrigger() {
        guard Settings.shared.triggerScheduleEnabled else {
            setTrigger(.schedule, active: false)
            return
        }
        let active = Self.isNowInMinutesRange(start: Settings.shared.triggerScheduleStart,
                                              end: Settings.shared.triggerScheduleEnd)
        setTrigger(.schedule, active: active)
    }

    func refreshPowerTrigger() {
        guard Settings.shared.triggerPowerEnabled else {
            setTrigger(.power, active: false)
            return
        }
        setTrigger(.power, active: Self.isOnACPower())
    }

    /// 是否处于日程区间内（分钟数，支持跨零点）
    static func isNowInMinutesRange(start: Int, end: Int) -> Bool {
        let cal = Calendar.current
        let now = cal.dateComponents([.hour, .minute], from: Date())
        let current = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        if start == end { return false }
        if start < end { return current >= start && current < end }
        return current >= start || current < end
    }

    /// 当前是否接通电源（IOPS 电源源列表）
    static func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let state = description[kIOPSPowerSourceStateKey as String] as? String,
               state == "AC Power" {  // kIOPxACPowerValue 未暴露给 Swift，用字面量
                return true
            }
        }
        return false
    }

    // MARK: - 内部

    /// 周期检查：手动会话到点 + 日程/电源触发器重估
    /// （IOPS 通知 API 未暴露给 Swift，电源状态用轮询，5 秒内响应插拔）
    private func startMonitoring() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        var expired = false
        if let expiry = manualExpiry, Date() >= expiry {
            manualExpiry = nil
            activeReasons.removeValue(forKey: .manual)
            expired = true
        }
        refreshScheduleTrigger()
        refreshPowerTrigger()

        guard expired else { return }
        Log.app.info("手动保持唤醒到点结束")
        AppNotifier.send(title: I18N.t("保持唤醒结束", "Stay Awake ended"),
                         body: I18N.t("保持唤醒会话已到时结束。", "Your stay-awake session finished."))
        performEndAction()
        updateAssertion()
        onStateChange?()
    }

    private func updateAssertion() {
        let active = !activeReasons.isEmpty
        if active, !hasAssertion {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "SakuraVeil stay awake" as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertionID = id
                hasAssertion = true
                Log.app.info("已持有系统唤醒断言")
            } else {
                Log.app.error("唤醒断言创建失败：\(result)")
            }
        } else if !active, hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
            Log.app.info("已释放系统唤醒断言")
        }
    }

    /// 手动会话到点后的收尾动作
    private func performEndAction() {
        switch Settings.shared.stayAwakeEndAction {
        case .sleep:
            runPMSet(["sleepnow"])
        case .displaySleep:
            runPMSet(["displaysleepnow"])
        case .none:
            break
        }
    }

    private func runPMSet(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        do {
            try process.run()
            Log.app.info("已执行 pmset \(arguments.joined(separator: " "), privacy: .public)")
        } catch {
            Log.app.error("pmset 执行失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}

/// 「保持唤醒」开关的独立热键管理（与遮屏热键并列）。
enum StayAwakeHotkey {

    static let id = "toggleStayAwake"

    /// 默认 ⌃⌥⌘W（W = Wake）
    static let defaultCombo = KeyCombo(
        keyCode: UInt32(kVK_ANSI_W),
        modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey),
        display: "⌃⌥⌘W"
    )

    @discardableResult
    static func apply(_ combo: KeyCombo, alertOnFailure: Bool) -> Bool {
        HotkeyCenter.shared.unregister(id: id)
        if HotkeyCenter.shared.register(id: id, combo: combo) {
            return true
        }
        if alertOnFailure {
            let alert = NSAlert()
            alert.messageText = I18N.t("快捷键注册失败", "Failed to register hotkey")
            alert.informativeText = I18N.t(
                "「\(combo.display)」可能已被其他应用占用，请换一个组合。",
                "“\(combo.display)” may be taken by another app. Try another combo."
            )
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        return false
    }
}
