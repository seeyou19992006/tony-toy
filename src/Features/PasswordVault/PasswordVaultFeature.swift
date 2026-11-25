import AppKit
import Foundation

/// 密码管理器。
///
/// 被包装的 `PasswordManagerWindow` 是一个 **`NSWindow` 子类**（不是
/// controller，也没有 `show()` / `present()`），所以这里持有窗口实例，
/// 把「显示 / 收起 / 切换」转发给窗口自己的 `makeKeyAndOrderFront`、
/// `orderOut`、`showUnlockView` / `showMainView`。
///
/// 窗口**按需创建**：只在第一次 `show()` 时构建整套 AppKit 视图。
/// 大多数会话不会打开密码面板，没必要在冷启动时为它付初始化成本
/// （与设置窗口用 `lazy` 的理由一致）。
final class PasswordVaultFeature: Feature {
    let id = FeatureID.passwordVault
    let title = "密码管理器"
    let icon = "lock"

    /// 旧 `main.swift` 里密码管理器没有独立开关，随应用常驻，等价于默认开启
    let defaultEnabled = true

    var settings: [SettingItem] {
        [
            .toggle(key: "enabled", title: "启用密码管理器", defaultValue: defaultEnabled),
            .hotkey(
                key: "hotkey", title: "呼出快捷键",
                defaultValue: HotkeyKeySpec(key: "v", modifiers: ["command", "shift"])),
            .number(
                key: "autoLockMinutes", title: "自动锁定（分钟，0 表示不锁）",
                defaultValue: 5, range: 0...60),
            .number(
                key: "clipboardClearSeconds", title: "剪贴板清除延迟（秒）",
                defaultValue: 30, range: 5...300),
        ]
    }

    /// `main.swift` 里的同名实例由整合时删除：两个 `PasswordManagerWindow`
    /// 各自持有一份 `VaultService`，会同时读写同一个 `vault.jsonl`。
    private var window: PasswordManagerWindow?

    /// 已应用的配置值。
    private(set) var hotkey = HotkeyKeySpec(key: "v", modifiers: ["command", "shift"])
    private(set) var autoLockMinutes = 5
    private(set) var clipboardClearSeconds = 30
    private var autoLockTimer: Timer?

    /// 呼出热键变更与启停回调（供 main.swift 注册/注销 Carbon 热键）
    var onHotkeyChanged: ((HotkeySpec) -> Void)?
    var onEnabledChanged: ((Bool) -> Void)?

    /// 菜单栏显示用的热键标题（如 `⌘⇧V`）
    var hotkeyTitle: String {
        HotkeyDisplay.displayName(for: hotkey)
    }

    /// 当前热键对应的 Carbon HotkeySpec
    var currentHotkeySpec: HotkeySpec? {
        LauncherFeature.makeHotkeySpec(from: hotkey)
    }

    func start() {
        onEnabledChanged?(true)
    }

    /// 关闭功能时收起面板、注销热键并停止自动锁定计时器。
    func stop() {
        autoLockTimer?.invalidate()
        autoLockTimer = nil
        window?.orderOut(nil)
        onEnabledChanged?(false)
    }

    // MARK: - 窗口转发

    /// 切换密码面板显示状态（等价于原 `AppDelegate.showPasswordManager()`）。
    func toggle() {
        let manager = makeWindowIfNeeded()
        guard !manager.isVisible else {
            manager.orderOut(nil)
            return
        }
        manager.recordPreviousApp()
        NSApp.activate(ignoringOtherApps: true)
        if manager.vaultService.isUnlocked {
            manager.showMainView()
        } else {
            manager.showUnlockView()
        }
        manager.makeKeyAndOrderFront(nil)
        resetAutoLockTimer()
    }

    /// 显示密码面板（已可见则只置前，不重复记录前台应用）。
    func show() {
        let manager = makeWindowIfNeeded()
        if !manager.isVisible {
            manager.recordPreviousApp()
        }
        NSApp.activate(ignoringOtherApps: true)
        if manager.vaultService.isUnlocked {
            manager.showMainView()
        } else {
            manager.showUnlockView()
        }
        manager.makeKeyAndOrderFront(nil)
        resetAutoLockTimer()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindowIfNeeded() -> PasswordManagerWindow {
        if let window = window { return window }
        let created = PasswordManagerWindow()
        window = created
        return created
    }

    // MARK: - 配置

    func applyValues(_ config: FeatureConfig) {
        if let decoded = SettingsPaneViewController.decodeHotkey(config.values["hotkey"]) {
            if decoded.key != hotkey.key || (decoded.modifiers ?? []) != (hotkey.modifiers ?? []) {
                hotkey = decoded
                if let spec = LauncherFeature.makeHotkeySpec(from: decoded) {
                    onHotkeyChanged?(spec)
                }
            }
        } else if case .string(let key)? = config.values["hotkey"] {
            let updated = HotkeyKeySpec(key: key, modifiers: hotkey.modifiers)
            if updated.key != hotkey.key || (updated.modifiers ?? []) != (hotkey.modifiers ?? []) {
                hotkey = updated
                if let spec = LauncherFeature.makeHotkeySpec(from: updated) {
                    onHotkeyChanged?(spec)
                }
            }
        }
        if case .int(let value)? = config.values["autoLockMinutes"] {
            autoLockMinutes = min(max(value, 0), 60)
        } else {
            autoLockMinutes = 5
        }
        if case .int(let value)? = config.values["clipboardClearSeconds"] {
            clipboardClearSeconds = min(max(value, 5), 300)
        } else {
            clipboardClearSeconds = 30
        }
        PasswordPaster.clearDelaySeconds = TimeInterval(clipboardClearSeconds)
        resetAutoLockTimer()
    }

    private func resetAutoLockTimer() {
        autoLockTimer?.invalidate()
        autoLockTimer = nil
        guard autoLockMinutes > 0 else { return }
        let interval = TimeInterval(autoLockMinutes * 60)
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, let window = self.window, window.vaultService.isUnlocked else { return }
            window.vaultService.lock()
            if window.isVisible {
                window.showUnlockView()
            }
        }
    }
}
