import Foundation
import IOKit
import IOKit.pwr_mgt

/// 可选：遮屏期间阻止显示器睡眠（IOPMAssertion）。
enum KeepAwake {

    private static var assertionID: IOPMAssertionID = 0
    private static var active = false

    static func begin() {
        guard !active else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "SakuraVeil is covering the screen" as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            active = true
            Log.cover.info("已启用保持亮屏断言")
        } else {
            Log.cover.error("保持亮屏断言创建失败：\(result)")
        }
    }

    static func end() {
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        active = false
        Log.cover.info("已释放保持亮屏断言")
    }
}
