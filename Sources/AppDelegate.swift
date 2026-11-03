import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyCenter.shared.onKeyDown = { [weak self] _ in
            self?.toggleCover()
        }
        ToggleHotkey.apply(Settings.shared.hotkeyCombo, alertOnFailure: false)
        setupStatusItem()
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
        KeepAwake.end()
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

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
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
}
