import AppKit
import Carbon.HIToolbox

/// 录制自定义快捷键的小浮窗：按下新组合键立即生效，ESC 取消。
/// 录制期间调用方应先注销旧热键，避免按到旧组合时误触发遮屏。
final class HotkeyRecorder {

    static let shared = HotkeyRecorder()

    private var window: NSWindow?
    private var monitor: Any?
    private var comboLabel: NSTextField?
    private var onRecorded: ((KeyCombo) -> Void)?
    private var onCancel: (() -> Void)?

    func begin(current: KeyCombo,
               onCancel: @escaping () -> Void,
               onRecorded: @escaping (KeyCombo) -> Void) {
        guard window == nil else { return }
        self.onCancel = onCancel
        self.onRecorded = onRecorded

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = I18N.t("录制快捷键", "Record hotkey")
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let prompt = NSTextField(labelWithString: I18N.t("请按下新的组合键（ESC 取消）", "Press the new key combo (ESC to cancel)"))
        prompt.frame = NSRect(x: 20, y: 100, width: 360, height: 20)
        prompt.alignment = .center
        prompt.font = .systemFont(ofSize: 13)
        prompt.textColor = .secondaryLabelColor

        let comboLabel = NSTextField(labelWithString: current.display)
        comboLabel.frame = NSRect(x: 20, y: 30, width: 360, height: 52)
        comboLabel.alignment = .center
        comboLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .medium)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        content.addSubview(prompt)
        content.addSubview(comboLabel)
        window.contentView = content

        self.window = window
        self.comboLabel = comboLabel

        // 录制期间吞掉所有本地按键，统一在这里处理。
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKey(event)
            return nil
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func handleKey(_ event: NSEvent) {
        if event.keyCode == UInt32(kVK_Escape) {
            finish(cancelled: true)
            return
        }
        let mods = KeyComboCodec.carbonModifiers(from: event.modifierFlags)
        guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            comboLabel?.stringValue = I18N.t("至少需要 ⌘ / ⌥ / ⌃ 之一", "Include ⌘, ⌥ or ⌃")
            return
        }
        let combo = KeyComboCodec.makeCombo(keyCode: UInt32(event.keyCode),
                                            flags: event.modifierFlags,
                                            characters: event.charactersIgnoringModifiers)
        comboLabel?.stringValue = combo.display
        let callback = onRecorded
        finish(cancelled: false)
        callback?(combo)
    }

    private func finish(cancelled: Bool) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onRecorded = nil
        let cancelCallback = onCancel
        onCancel = nil
        window?.orderOut(nil)
        window = nil
        comboLabel = nil
        if cancelled {
            cancelCallback?()
        }
    }
}
