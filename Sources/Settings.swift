import Foundation

/// 遮罩内容模式。
enum ContentMode: String {
    /// 内置极光动画（默认，零素材）
    case aurora
    /// 自选视频（循环静音播放）
    case video
    /// 自选图片
    case image
    /// 当前桌面壁纸
    case wallpaper
}

/// 手动保持唤醒会话到点后的动作。
enum StayAwakeEndAction: String {
    case none
    case sleep          // 让 Mac 睡眠
    case displaySleep   // 仅熄屏

    var displayName: String {
        switch self {
        case .none: return I18N.t("什么都不做", "Do nothing")
        case .sleep: return I18N.t("让 Mac 睡眠", "Sleep the Mac")
        case .displaySleep: return I18N.t("仅熄屏", "Display sleep only")
        }
    }
}

/// App 触发器里登记的一个应用。
struct TriggerApp: Codable, Equatable {
    var bundleID: String
    var name: String
}

/// 设置持久化：UserDefaults，键统一前缀 sakuraveil_。
final class Settings {
    static let shared = Settings()

    private let defaults: UserDefaults

    private enum Key {
        static let contentMode = "sakuraveil.contentMode"
        static let videoPath = "sakuraveil.videoPath"
        static let imagePath = "sakuraveil.imagePath"
        static let customMessages = "sakuraveil.customMessages"
        static let keepAwake = "sakuraveil.keepAwake"
        static let hotkey = "sakuraveil.hotkey"
        static let menuBarCountdown = "sakuraveil.menuBarCountdown"
        // 保持唤醒
        static let stayAwakeDefaultMinutes = "sakuraveil.stayAwake.defaultMinutes"
        static let stayAwakeEndAction = "sakuraveil.stayAwake.endAction"
        static let stayAwakeNotify = "sakuraveil.stayAwake.notify"
        static let stayAwakeHotkey = "sakuraveil.stayAwake.hotkey"
        static let coverPreventSystemSleep = "sakuraveil.cover.preventSystemSleep"
        // 触发器
        static let triggerApps = "sakuraveil.trigger.apps"
        static let triggerAppsEnabled = "sakuraveil.trigger.appsEnabled"
        static let triggerScheduleEnabled = "sakuraveil.trigger.scheduleEnabled"
        static let triggerScheduleStart = "sakuraveil.trigger.scheduleStart"
        static let triggerScheduleEnd = "sakuraveil.trigger.scheduleEnd"
        static let triggerPowerEnabled = "sakuraveil.trigger.powerEnabled"
        static let triggerDisplayEnabled = "sakuraveil.trigger.displayEnabled"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.contentMode: ContentMode.aurora.rawValue,
            Key.keepAwake: false,
            Key.stayAwakeDefaultMinutes: 60,
            Key.stayAwakeEndAction: StayAwakeEndAction.none.rawValue,
            Key.stayAwakeNotify: true,
            Key.coverPreventSystemSleep: true,
            Key.menuBarCountdown: true,
            Key.triggerAppsEnabled: false,
            Key.triggerScheduleEnabled: false,
            Key.triggerScheduleStart: 22 * 60,
            Key.triggerScheduleEnd: 6 * 60,
            Key.triggerPowerEnabled: false,
            Key.triggerDisplayEnabled: false,
        ])
    }

    var contentMode: ContentMode {
        get { ContentMode(rawValue: defaults.string(forKey: Key.contentMode) ?? "") ?? .aurora }
        set { defaults.set(newValue.rawValue, forKey: Key.contentMode) }
    }

    var videoURL: URL? {
        get { defaults.string(forKey: Key.videoPath).map(URL.init(fileURLWithPath:)) }
        set { defaults.set(newValue?.path, forKey: Key.videoPath) }
    }

    var imageURL: URL? {
        get { defaults.string(forKey: Key.imagePath).map(URL.init(fileURLWithPath:)) }
        set { defaults.set(newValue?.path, forKey: Key.imagePath) }
    }

    /// 自定义轮播文案（每行一句）；为空时用内置文案。
    var customMessages: [String] {
        get { defaults.stringArray(forKey: Key.customMessages) ?? [] }
        set { defaults.set(newValue, forKey: Key.customMessages) }
    }

    /// 轮播文案：优先自定义，否则内置。
    var messages: [String] {
        let custom = customMessages.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !custom.isEmpty { return custom }
        return [
            I18N.t("任务运行中，请勿操作 ✿", "Task in progress — please don't touch ✿"),
            I18N.t("屏幕休息中，马上回来", "Screen resting, back soon"),
            I18N.t("去去就回～", "Back in a moment~"),
        ]
    }

    var keepAwakeWhileCovered: Bool {
        get { defaults.bool(forKey: Key.keepAwake) }
        set { defaults.set(newValue, forKey: Key.keepAwake) }
    }

    var hotkeyCombo: KeyCombo {
        get {
            guard let data = defaults.data(forKey: Key.hotkey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .defaultCombo
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.hotkey)
            }
        }
    }

    // MARK: - 保持唤醒（Amphetamine 式功能）

    /// 手动会话默认时长（分钟）
    var stayAwakeDefaultMinutes: Int {
        get { defaults.integer(forKey: Key.stayAwakeDefaultMinutes) }
        set { defaults.set(newValue, forKey: Key.stayAwakeDefaultMinutes) }
    }

    /// 手动会话到点后的动作
    var stayAwakeEndAction: StayAwakeEndAction {
        get { StayAwakeEndAction(rawValue: defaults.string(forKey: Key.stayAwakeEndAction) ?? "") ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Key.stayAwakeEndAction) }
    }

    /// 会话结束 / 触发变化时发系统通知
    var stayAwakeNotify: Bool {
        get { defaults.bool(forKey: Key.stayAwakeNotify) }
        set { defaults.set(newValue, forKey: Key.stayAwakeNotify) }
    }

    /// 菜单栏显示剩余时间（⚡ 59:12）
    var menuBarCountdown: Bool {
        get { defaults.bool(forKey: Key.menuBarCountdown) }
        set { defaults.set(newValue, forKey: Key.menuBarCountdown) }
    }

    /// 保持唤醒开关的独立热键
    var stayAwakeHotkeyCombo: KeyCombo {
        get {
            guard let data = defaults.data(forKey: Key.stayAwakeHotkey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .defaultStayAwakeCombo
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.stayAwakeHotkey)
            }
        }
    }

    /// 遮屏期间防止系统睡眠（任务不断线；与「保持亮屏」独立）
    var coverPreventSystemSleep: Bool {
        get { defaults.bool(forKey: Key.coverPreventSystemSleep) }
        set { defaults.set(newValue, forKey: Key.coverPreventSystemSleep) }
    }

    // MARK: - 触发器

    var triggerApps: [TriggerApp] {
        get {
            guard let data = defaults.data(forKey: Key.triggerApps),
                  let apps = try? JSONDecoder().decode([TriggerApp].self, from: data) else { return [] }
            return apps
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.triggerApps)
            }
        }
    }

    var triggerAppsEnabled: Bool {
        get { defaults.bool(forKey: Key.triggerAppsEnabled) }
        set { defaults.set(newValue, forKey: Key.triggerAppsEnabled) }
    }

    var triggerScheduleEnabled: Bool {
        get { defaults.bool(forKey: Key.triggerScheduleEnabled) }
        set { defaults.set(newValue, forKey: Key.triggerScheduleEnabled) }
    }

    /// 日程起点 / 终点（距零点的分钟数；支持跨零点）
    var triggerScheduleStart: Int {
        get { defaults.integer(forKey: Key.triggerScheduleStart) }
        set { defaults.set(newValue, forKey: Key.triggerScheduleStart) }
    }

    var triggerScheduleEnd: Int {
        get { defaults.integer(forKey: Key.triggerScheduleEnd) }
        set { defaults.set(newValue, forKey: Key.triggerScheduleEnd) }
    }

    var triggerPowerEnabled: Bool {
        get { defaults.bool(forKey: Key.triggerPowerEnabled) }
        set { defaults.set(newValue, forKey: Key.triggerPowerEnabled) }
    }

    var triggerDisplayEnabled: Bool {
        get { defaults.bool(forKey: Key.triggerDisplayEnabled) }
        set { defaults.set(newValue, forKey: Key.triggerDisplayEnabled) }
    }
}
