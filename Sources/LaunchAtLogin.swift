import Foundation
import ServiceManagement

/// 开机自启：SMAppService（macOS 13+）。失败向上报告、落日志，但不打断应用。
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.app.info("开机自启已设为 \(enabled)")
            return true
        } catch {
            Log.app.error("开机自启设置失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
