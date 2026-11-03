import Cocoa
import Carbon.HIToolbox

/// 遮罩窗口把键鼠事件上抛给控制器处理。
protocol CoverWindowDelegate: AnyObject {
    func coverWindow(_ window: CoverWindow, didPressKey event: NSEvent)
    func coverWindow(_ window: CoverWindow, didClickMouse event: NSEvent)
}

/// 全屏遮罩窗口：borderless、.screenSaver 层级（压过菜单栏/Dock）、
/// 所有 Space 可见（含全屏 App 所在 Space）、接管键鼠不透给底层 App。
final class CoverWindow: NSWindow {

    weak var coverDelegate: CoverWindowDelegate?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 每屏窗口的统一外观与 Space 行为。
    func configure(for screen: NSScreen) {
        setFrame(screen.frame, display: true)
        level = .screenSaver
        collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = false
        isReleasedWhenClosed = false
    }

    // 键盘：吞掉，不透给底层 App；交给控制器决定是否唤出密码面板。
    override func keyDown(with event: NSEvent) {
        coverDelegate?.coverWindow(self, didPressKey: event)
    }

    override func mouseDown(with event: NSEvent) {
        coverDelegate?.coverWindow(self, didClickMouse: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        coverDelegate?.coverWindow(self, didClickMouse: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        coverDelegate?.coverWindow(self, didClickMouse: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // 吞掉滚动
    }
}
