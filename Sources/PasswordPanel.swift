import Cocoa
import Carbon.HIToolbox

protocol PasswordPanelDelegate: AnyObject {
    /// 密码校验通过，请求解除遮屏。
    func passwordPanelDidRequestUnlock(_ panel: PasswordPanel)
    /// 面板被收起（ESC / 点击卡片外）。
    func passwordPanelDidDismiss(_ panel: PasswordPanel)
}

/// 防暴力试错：连错 N 次锁定一段时间（跨所有屏幕共享一份）。
final class AttemptLimiter {

    let maxAttempts = 5
    let lockoutSeconds: TimeInterval = 30

    private(set) var failCount = 0
    private var lockedUntil: Date?

    var isLocked: Bool { Date() < (lockedUntil ?? .distantPast) }

    var remainingSeconds: Int {
        guard let until = lockedUntil else { return 0 }
        return max(0, Int(ceil(until.timeIntervalSinceNow)))
    }

    /// 记一次失败；达到上限则进入锁定，返回是否刚刚触发锁定。
    @discardableResult
    func registerFailure() -> Bool {
        failCount += 1
        if failCount >= maxAttempts {
            beginLockout()
            return true
        }
        return false
    }

    private func beginLockout() {
        failCount = 0
        lockedUntil = Date().addingTimeInterval(lockoutSeconds)
    }

    func reset() {
        failCount = 0
        lockedUntil = nil
    }
}

/// 密码解锁浮层：整屏半透明压暗 + 居中毛玻璃卡片。
final class PasswordPanel: NSView, NSTextFieldDelegate {

    static let passwordAccount = "unlock"

    weak var delegate: PasswordPanelDelegate?
    private let limiter: AttemptLimiter

    private var card: NSVisualEffectView!
    private var passwordField: NSSecureTextField!
    private var unlockButton: NSButton!
    private var errorLabel: NSTextField!
    private var noPasswordLabel: NSTextField!
    private var lockoutTimer: Timer?

    private(set) var isShown = false

    init(limiter: AttemptLimiter) {
        self.limiter = limiter
        super.init(frame: .zero)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档初始化")
    }

    // MARK: - 显示 / 收起

    func show(in parent: NSView) {
        if isShown {
            focusField()
            return
        }
        isShown = true
        frame = parent.bounds
        autoresizingMask = [.width, .height]
        parent.addSubview(self)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        card.layer?.cornerRadius = 18
        card.layer?.masksToBounds = true
        layoutCard()

        let hasPassword = KeychainStore.shared.get(forAccount: Self.passwordAccount) != nil
        noPasswordLabel.isHidden = hasPassword
        passwordField.isHidden = !hasPassword
        unlockButton.isHidden = !hasPassword
        resetErrorState()

        if !hasPassword {
            errorLabel.textColor = .systemOrange
            errorLabel.stringValue = I18N.t(
                "尚未设置密码：请在菜单栏「设置解锁密码」，或直接用快捷键解除。",
                "No password set — set one in the menu bar, or unlock with the hotkey."
            )
            errorLabel.isHidden = false
        }

        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = 1
        }

        if limiter.isLocked {
            enterLockout()
        } else if hasPassword {
            focusField()
        }
    }

    func hide(notifyDismiss: Bool = true) {
        guard isShown else { return }
        isShown = false
        lockoutTimer?.invalidate()
        lockoutTimer = nil
        passwordField?.stringValue = ""
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.removeFromSuperview()
        })
        if notifyDismiss {
            delegate?.passwordPanelDidDismiss(self)
        }
    }

    // MARK: - UI 装配

    private func buildUI() {
        let card = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: 232))
        card.material = .hudWindow
        // screenSaver 层级窗口上 behindWindow 拿不到桌面的模糊，改用窗口内模糊
        card.blendingMode = .withinWindow
        card.state = .active
        self.card = card
        addSubview(card)

        let icon = NSImageView(frame: NSRect(x: 174, y: 186, width: 32, height: 32))
        icon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        card.addSubview(icon)

        let prompt = NSTextField(labelWithString: I18N.t("屏幕已锁定", "Screen locked"))
        prompt.frame = NSRect(x: 20, y: 150, width: 340, height: 24)
        prompt.alignment = .center
        prompt.font = .systemFont(ofSize: 15, weight: .semibold)
        card.addSubview(prompt)

        let field = NSSecureTextField(frame: NSRect(x: 40, y: 106, width: 300, height: 32))
        field.placeholderString = I18N.t("输入解锁密码", "Enter unlock password")
        field.target = self
        field.action = #selector(unlockTapped)
        field.delegate = self
        card.addSubview(field)
        passwordField = field

        let button = NSButton(title: I18N.t("解锁", "Unlock"), target: self, action: #selector(unlockTapped))
        button.frame = NSRect(x: 40, y: 60, width: 300, height: 34)
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        card.addSubview(button)
        unlockButton = button

        let error = NSTextField(labelWithString: "")
        error.frame = NSRect(x: 20, y: 26, width: 340, height: 30)
        error.alignment = .center
        error.font = .systemFont(ofSize: 12)
        error.textColor = .systemRed
        error.lineBreakMode = .byWordWrapping
        error.isHidden = true
        card.addSubview(error)
        errorLabel = error

        let hint = NSTextField(labelWithString: I18N.t("⎋ 收起面板（遮屏继续）", "⎋ hide panel (cover stays)"))
        hint.frame = NSRect(x: 20, y: 6, width: 340, height: 16)
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        card.addSubview(hint)

        let noPassword = NSTextField(wrappingLabelWithString: I18N.t(
            "尚未设置解锁密码。请通过菜单栏「设置解锁密码」添加，或直接使用快捷键解除遮屏。",
            "No unlock password yet. Set one from the menu bar, or unlock with the hotkey."
        ))
        noPassword.frame = NSRect(x: 30, y: 80, width: 320, height: 70)
        noPassword.alignment = .center
        noPassword.font = .systemFont(ofSize: 13)
        card.addSubview(noPassword)
        noPasswordLabel = noPassword
    }

    private func layoutCard() {
        card.frame.origin = NSPoint(
            x: (bounds.width - card.frame.width) / 2,
            y: (bounds.height - card.frame.height) / 2
        )
    }

    private func focusField() {
        DispatchQueue.main.async { [weak self] in
            self?.passwordField?.becomeFirstResponder()
        }
    }

    // 圆角在 layout 时设置，确保 backing layer 已就绪
    override func layout() {
        super.layout()
        card.layer?.cornerRadius = 18
        card.layer?.masksToBounds = true
    }

    // MARK: - 校验

    @objc private func unlockTapped() {
        guard isShown, !limiter.isLocked else { return }
        let input = passwordField.stringValue
        guard !input.isEmpty else { return }
        let saved = KeychainStore.shared.get(forAccount: Self.passwordAccount)
        if input == saved {
            limiter.reset()
            Log.security.info("密码解锁成功")
            delegate?.passwordPanelDidRequestUnlock(self)
            return
        }

        Log.security.notice("密码解锁失败")
        let triggered = limiter.registerFailure()
        passwordField.stringValue = ""
        if triggered {
            enterLockout()
        } else {
            let remain = limiter.maxAttempts - limiter.failCount
            errorLabel.textColor = .systemRed
            errorLabel.stringValue = I18N.t(
                "密码不正确，还可尝试 \(remain) 次",
                "Wrong password — \(remain) attempt(s) left"
            )
            errorLabel.isHidden = false
            shakeCard()
        }
    }

    private func enterLockout() {
        passwordField.isEnabled = false
        unlockButton.isEnabled = false
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = false
        refreshLockoutLabel()
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickLockout()
        }
    }

    private func tickLockout() {
        guard limiter.isLocked else {
            lockoutTimer?.invalidate()
            lockoutTimer = nil
            passwordField.isEnabled = true
            unlockButton.isEnabled = true
            resetErrorState()
            focusField()
            return
        }
        refreshLockoutLabel()
    }

    private func refreshLockoutLabel() {
        errorLabel.stringValue = I18N.t(
            "尝试次数过多，已锁定 \(limiter.remainingSeconds) 秒",
            "Too many attempts — locked for \(limiter.remainingSeconds)s"
        )
    }

    private func resetErrorState() {
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
    }

    private func shakeCard() {
        guard let layer = card.layer else { return }
        let baseX = card.frame.midX
        let anim = CAKeyframeAnimation(keyPath: "position.x")
        anim.values = [baseX - 14, baseX + 14, baseX - 9, baseX + 9, baseX - 4, baseX]
        anim.duration = 0.42
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "shake")
    }

    // MARK: - 事件

    /// 输入框内按 ESC → 收起面板。
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }

    /// 点击卡片外 → 收起面板。
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !card.frame.contains(point) {
            hide()
            return
        }
        super.mouseDown(with: event)
    }
}
