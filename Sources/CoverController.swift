import Cocoa
import Carbon.HIToolbox

/// 遮罩状态机：多屏窗口编排、唤出/解除、显示器与唤醒事件监听。
final class CoverController {

    static let shared = CoverController()

    private(set) var isCovered = false

    private var windows: [CoverWindow] = []
    private var contents: [ObjectIdentifier: CoverContentController] = [:]
    private var panels: [ObjectIdentifier: PasswordPanel] = [:]
    private let attemptLimiter = AttemptLimiter()

    private var observers: [NSObjectProtocol] = []
    private var globalMonitor: Any?
    private var reactivateTask: DispatchWorkItem?
    private var activityToken: NSObjectProtocol?

    // MARK: - 开关

    func toggle() {
        isCovered ? hide() : show()
    }

    func show() {
        guard !isCovered else { return }
        isCovered = true
        attemptLimiter.reset()
        rebuildWindows()

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)

        installObservers()
        if Settings.shared.keepAwakeWhileCovered {
            KeepAwake.begin()
        }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "SakuraVeil 遮屏期间保持响应"
        )
        Log.cover.info("遮屏已开启（\(self.windows.count) 块屏幕）")
    }

    func hide() {
        guard isCovered else { return }
        isCovered = false
        removeObservers()
        KeepAwake.end()
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
        Log.cover.info("遮屏解除")

        // 渐隐后统一拆除，避免和快速重开互相踩踏
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.allowsImplicitAnimation = true
            for window in windows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            guard let self, !self.isCovered else { return }
            self.teardownWindows()
        })
    }

    // MARK: - 窗口编排

    private func rebuildWindows() {
        teardownWindows()
        for screen in NSScreen.screens {
            let window = CoverWindow(contentRect: screen.frame,
                                     styleMask: .borderless,
                                     backing: .buffered,
                                     defer: false,
                                     screen: screen)
            window.configure(for: screen)
            window.coverDelegate = self
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                let content = CoverContentController(screen: screen, container: contentView)
                content.install()
                contents[ObjectIdentifier(window)] = content

                let panel = PasswordPanel(limiter: attemptLimiter)
                panel.delegate = self
                panels[ObjectIdentifier(window)] = panel
            }
            windows.append(window)
        }
        for window in windows {
            window.orderFrontRegardless()
        }
    }

    private func teardownWindows() {
        for (_, content) in contents {
            content.teardown()
        }
        contents.removeAll()
        for (_, panel) in panels {
            panel.hide(notifyDismiss: false)
        }
        panels.removeAll()
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    // MARK: - 密码面板

    private func showPanel(for window: CoverWindow) {
        guard let contentView = window.contentView,
              let panel = panels[ObjectIdentifier(window)] else { return }
        panel.show(in: contentView)
    }

    // MARK: - 观察者（仅遮屏期间安装）

    private func installObservers() {
        let center = NotificationCenter.default

        // 显示器热插拔 / 分辨率变化 → 按新屏幕集合重建
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isCovered else { return }
            self.rebuildWindows()
            NSApp.activate(ignoringOtherApps: true)
            self.windows.first?.makeKeyAndOrderFront(nil)
        })

        // 系统唤醒 → 重新压盖并恢复播放
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isCovered else { return }
            for window in self.windows {
                window.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
            for (_, content) in self.contents {
                content.resumeIfNeeded()
            }
        })

        // 遮屏期间失去焦点（如他人按 ⌘Tab）→ 立刻抢回
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isCovered else { return }
            self.reactivateTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.isCovered else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.windows.first?.makeKeyAndOrderFront(nil)
            }
            self.reactivateTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
        })

        // 事件流向其他 App（遮罩未被激活时）→ 抢回焦点
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.isCovered else { return }
            DispatchQueue.main.async {
                guard self.isCovered else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = nil
        reactivateTask?.cancel()
        reactivateTask = nil
    }
}

// MARK: - CoverWindowDelegate

extension CoverController: CoverWindowDelegate {

    func coverWindow(_ window: CoverWindow, didPressKey event: NSEvent) {
        guard isCovered else { return }
        // ESC：面板已显示时仅收起面板，遮屏继续
        if event.keyCode == UInt16(kVK_Escape),
           let panel = panels[ObjectIdentifier(window)], panel.isShown {
            panel.hide()
            return
        }
        // 任意按键 → 唤出密码面板
        showPanel(for: window)
    }

    func coverWindow(_ window: CoverWindow, didClickMouse event: NSEvent) {
        guard isCovered else { return }
        showPanel(for: window)
    }
}

// MARK: - PasswordPanelDelegate

extension CoverController: PasswordPanelDelegate {

    func passwordPanelDidRequestUnlock(_ panel: PasswordPanel) {
        hide()
    }

    func passwordPanelDidDismiss(_ panel: PasswordPanel) {
        // 收起面板后回到纯遮罩状态，无需处理
    }
}
