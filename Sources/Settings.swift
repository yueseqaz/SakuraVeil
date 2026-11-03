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
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.contentMode: ContentMode.aurora.rawValue,
            Key.keepAwake: false,
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
}
