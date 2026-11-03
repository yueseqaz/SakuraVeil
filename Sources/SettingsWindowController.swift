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

    private func addTab(_ vc: NSViewController, label: String, symbol: String) {
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

    /// 切换标签页时，窗口高度贴合当前页内容（顶边不动，动画过渡）。
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        DispatchQueue.main.async { [weak self] in
            self?.fitWindowToContent(of: tabViewItem)
        }
    }

    private func fitWindowToContent(of tabViewItem: NSTabViewItem?) {
        guard let window = view.window,
              let vc = tabViewItem?.viewController else { return }
        let contentSize = vc.view.frame.size
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        var frame = window.frame
        guard abs(frame.height - target.height) > 0.5 else { return }
        frame.size = target.size
        frame.origin.y += (window.frame.height - target.height)  // 保持顶边不动
        window.setFrame(frame, display: true, animate: true)
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
}
