import Cocoa

/// 设置窗口：工具栏式三个标签页（通用 / 安全 / 关于）。
final class SettingsTabViewController: NSTabViewController {

    private let stayAwakeVC = StayAwakeSettingsViewController()
    private let coverVC = CoverSettingsViewController()
    private let securityVC = SecuritySettingsViewController()
    private let aboutVC = AboutViewController()

    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        addTab(stayAwakeVC, label: I18N.t("保持唤醒", "Stay Awake"), symbol: "bolt")
        addTab(coverVC, label: I18N.t("遮屏", "Cover"), symbol: "eye.slash")
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
    /// 注意：子 view 会被 NSTabView 拉伸到容器大小，不能读 frame，
    /// 必须用每个页面声明的 preferredContentSize。
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        DispatchQueue.main.async { [weak self] in
            self?.fitWindowToContent(of: tabViewItem)
        }
    }

    func fitWindowToContent(of tabViewItem: NSTabViewItem?) {
        guard let window = view.window,
              let vc = tabViewItem?.viewController else { return }
        let contentSize = vc.preferredContentSize
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        var frame = window.frame
        guard abs(frame.height - target.height) > 0.5 || abs(frame.width - target.width) > 0.5 else { return }
        let oldTop = frame.maxY
        frame.size = target.size
        frame.origin.y = oldTop - frame.height  // 保持顶边不动
        window.setFrame(frame, display: true, animate: true)
    }

    /// 窗口初次打开时也贴合当前页（didSelect 只在切换时触发）。
    func syncWindowSize() {
        fitWindowToContent(of: tabView.selectedTabViewItem)
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

    /// 转发给标签页控制器：窗口初次打开时贴合当前页高度。
    func syncWindowSize() {
        (window?.contentViewController as? SettingsTabViewController)?.syncWindowSize()
    }
}
