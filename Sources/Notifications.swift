import Foundation
import UserNotifications

/// 系统通知封装：会话到点 / 触发器变化提醒。
enum AppNotifier {

    private static var delegateInstalled = false

    /// 请求通知授权（幂等；用户拒绝则静默不发）。
    static func requestAuthorizationIfNeeded() {
        installDelegate()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Log.app.info("通知授权: \(granted) \(error?.localizedDescription ?? "无错误", privacy: .public)")
        }
    }

    /// 发一条本地通知（stayAwakeNotify 关闭时不发）。
    static func send(title: String, body: String) {
        guard Settings.shared.stayAwakeNotify else { return }
        installDelegate()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("通知发送失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func installDelegate() {
        guard !delegateInstalled else { return }
        delegateInstalled = true
        UNUserNotificationCenter.current().delegate = NotifierDelegate.shared
    }

    /// accessory 应用在前台也要能看到横幅。
    final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
        static let shared = NotifierDelegate()

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }
}
