import Cocoa

/// 设置窗口：工具栏式三个标签页（通用 / 安全 / 关于）。
final class SettingsTabViewController: NSTabViewController {

    private let generalVC = GeneralSettingsViewController()
    private let securityVC = SecuritySettingsViewController()
    private let aboutVC = AboutViewController()

    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        addTab(generalVC, label: I18N.t("通用", "General"), symbol: "gearshape")
        addTab(securityVC, label: I18N.t("安全", "Security"), symbol: "lock")
        addTab(aboutVC, label: I18N.t("关于", "About"), symbol: "info.circle")
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档初始化")
    }

    var aboutIndex: Int { 2 }

    private func addTab(_ vc: NSViewController, label: String, symbol: String) {
        vc.title = label
        let item = NSTabViewItem(viewController: vc)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        addTabViewItem(item)
    }

    /// NSTabViewController 切换时会重置窗口标题（显示 Untitled），这里固定回写。
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, willSelect: tabViewItem)
        DispatchQueue.main.async { [weak self] in
            self?.view.window?.title = I18N.t("SakuraVeil 设置", "SakuraVeil Settings")
        }
    }
}

/// 持有设置窗口；关闭仅隐藏，实例由 AppDelegate 懒创建并复用。
final class SettingsWindowController: NSWindowController {

    init() {
        let tabVC = SettingsTabViewController()
        let window = NSWindow(contentViewController: tabVC)
        window.styleMask = [.titled, .closable]
        window.title = I18N.t("SakuraVeil 设置", "SakuraVeil Settings")
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档初始化")
    }

    func showAbout() {
        guard let tabVC = window?.contentViewController as? SettingsTabViewController else { return }
        tabVC.selectedTabViewItemIndex = tabVC.aboutIndex
    }
}
