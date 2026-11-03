import Foundation
import os

/// 统一日志出口（never silent 约定：错误必须落日志）。
enum Log {
    static let app = Logger(subsystem: "com.sakura.sakuraveil", category: "app")
    static let hotkey = Logger(subsystem: "com.sakura.sakuraveil", category: "hotkey")
    static let cover = Logger(subsystem: "com.sakura.sakuraveil", category: "cover")
    static let security = Logger(subsystem: "com.sakura.sakuraveil", category: "security")
}
