import Foundation
import AppKit
import Carbon.HIToolbox

/// 一组可持久化的全局快捷键（Carbon 虚拟键码 + Carbon 修饰键）。
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    /// 默认快捷键：⌃⌥⌘S
    static let defaultCombo = KeyCombo(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey),
        display: "⌃⌥⌘S"
    )
}

/// NSEvent → KeyCombo 的转换工具（录制用）。
enum KeyComboCodec {

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func modifiersDisplay(_ m: UInt32) -> String {
        var s = ""
        if m & UInt32(controlKey) != 0 { s += "⌃" }
        if m & UInt32(optionKey) != 0 { s += "⌥" }
        if m & UInt32(shiftKey) != 0 { s += "⇧" }
        if m & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    /// 键码的人类可读名（覆盖常用键，其余退回字符/键码）。
    static func keyDisplay(keyCode: UInt32, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "⏎"
        case kVK_Tab: return "⇥"
        case kVK_Space: return I18N.t("空格", "Space")
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            if let c = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                return c.uppercased()
            }
            return "Key\(keyCode)"
        }
    }

    static func makeCombo(keyCode: UInt32, flags: NSEvent.ModifierFlags, characters: String?) -> KeyCombo {
        let mods = carbonModifiers(from: flags)
        return KeyCombo(
            keyCode: keyCode,
            modifiers: mods,
            display: modifiersDisplay(mods) + keyDisplay(keyCode: keyCode, characters: characters)
        )
    }
}

/// 全局热键：Carbon RegisterEventHotKey（零三方依赖）。
/// 每条注册分配自增 id；注册失败向上返回 false（never silent）。
final class HotkeyCenter {

    static let shared = HotkeyCenter()

    private struct Registration {
        var combo: KeyCombo
        var ref: EventHotKeyRef
    }

    private var handlerRef: EventHandlerRef?
    private var registrations: [String: Registration] = [:]
    private var idsByCarbonID: [UInt32: String] = [:]
    private var nextID: UInt32 = 1
    private let queue = DispatchQueue(label: "com.sakura.sakuraveil.hotkeys")

    /// 主线程回调，参数为注册时的 id。
    var onKeyDown: ((String) -> Void)?

    private init() {
        installHandler()
    }

    deinit {
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    // MARK: - Public API

    /// 注册（或替换）一条热键；OS 拒绝（如组合被占用）时返回 false。
    @discardableResult
    func register(id: String, combo: KeyCombo) -> Bool {
        queue.sync { _register(id: id, combo: combo) }
    }

    @discardableResult
    func unregister(id: String) -> Bool {
        queue.sync { _unregister(id: id) }
    }

    func unregisterAll() {
        queue.sync {
            for (_, registration) in registrations {
                UnregisterEventHotKey(registration.ref)
            }
            registrations.removeAll()
            idsByCarbonID.removeAll()
        }
    }

    // MARK: - Implementation

    @discardableResult
    private func _register(id: String, combo: KeyCombo) -> Bool {
        _unregister(id: id)
        // 无 ⌘/⌥/⌃ 主修饰键的组合会全局吞掉普通按键，直接拒绝。
        guard combo.modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            Log.hotkey.error("拒绝注册无主修饰键的热键 '\(id, privacy: .public)'")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x534B_564C) /* 'SKVL' */, id: nextID)
        nextID &+= 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let hotKeyRef = ref else {
            Log.hotkey.error("RegisterEventHotKey 失败 '\(id, privacy: .public)' status=\(status)")
            return false
        }

        idsByCarbonID[hotKeyID.id] = id
        registrations[id] = Registration(combo: combo, ref: hotKeyRef)
        Log.hotkey.info("已注册热键 '\(id, privacy: .public)'")
        return true
    }

    @discardableResult
    private func _unregister(id: String) -> Bool {
        guard let registration = registrations.removeValue(forKey: id) else { return false }
        UnregisterEventHotKey(registration.ref)
        idsByCarbonID = idsByCarbonID.filter { $0.value != id }
        return true
    }

    private func installHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        ]

        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return noErr }
            let center = HotkeyCenter.shared
            guard let id = center.idsByCarbonID[hotKeyID.id] else { return noErr }
            DispatchQueue.main.async {
                center.onKeyDown?(id)
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), callback, eventTypes.count, &eventTypes, nil, &handlerRef)
    }
}

/// 「遮屏开关」这条热键的应用层管理：注册/替换 + 冲突提示（never silent）。
/// AppDelegate 启动时和设置页修改快捷键时共用。
enum ToggleHotkey {

    static let id = "toggleCover"

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
