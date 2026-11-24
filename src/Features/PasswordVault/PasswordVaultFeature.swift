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

    /// 已应用的配置值，供整合后的热键注册 / 自动锁定定时器使用。
    private(set) var hotkey = HotkeyKeySpec(key: "v", modifiers: ["command", "shift"])
    private(set) var autoLockMinutes = 5
    private(set) var clipboardClearSeconds = 30

    /// 窗口功能没有需要常驻的启动动作（热键由 Carbon 全局注册，
    /// 现在仍留在 `main.swift` 的 `registerPasswordManagerHotkey()` 里）。
    func start() {}

    /// 关闭功能时收起面板，避免开关已经关了还浮着一个密码窗口。
    /// 不解锁/锁定 vault——那是用户显式操作（窗口里的「锁定」按钮）。
    func stop() {
        window?.orderOut(nil)
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

    /// TODO: 三项配置目前都没有运行时入口，先如实保存：
    /// - `hotkey` 现在硬编码在 `main.swift` 的 `registerPasswordManagerHotkey()`
    ///   （Carbon `RegisterEventHotKey`，keyCode 9 = V，cmd+shift）；
    /// - `autoLockMinutes` 需要 `VaultService` 暴露定时锁定（当前只有手动 `lock()`）；
    /// - `clipboardClearSeconds` 需要 `PasswordPaster` 把写死的 0.5 秒恢复
    ///   改成可配置的「延迟清除」语义（当前是恢复旧内容，不是清空）。
    /// 等这三处暴露 API 后在这里转发，不要假装已经生效。
    func applyValues(_ config: FeatureConfig) {
        // 热键在 values 里的形状还没被设置窗口定型（`SettingItem` 到
        // `FeatureConfig.values` 的写入尚未实现），这里兼容两种最自然的写法：
        // `{ "key": "v", "modifiers": [...] }` 对象，以及只存键名的字符串。
        if case .object(let dict)? = config.values["hotkey"] {
            let key = Self.stringValue(dict["key"]) ?? hotkey.key
            let modifiers: [String]?
            if case .array(let list)? = dict["modifiers"] {
                modifiers = list.compactMap(Self.stringValue)
            } else {
                modifiers = hotkey.modifiers
            }
            hotkey = HotkeyKeySpec(key: key, modifiers: modifiers)
        } else if case .string(let key)? = config.values["hotkey"] {
            hotkey = HotkeyKeySpec(key: key, modifiers: hotkey.modifiers)
        }
        if case .int(let value)? = config.values["autoLockMinutes"] {
            autoLockMinutes = min(max(value, 0), 60)
        }
        if case .int(let value)? = config.values["clipboardClearSeconds"] {
            clipboardClearSeconds = min(max(value, 5), 300)
        }
    }

    private static func stringValue(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        return text
    }
}
