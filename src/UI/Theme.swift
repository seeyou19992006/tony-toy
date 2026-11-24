import AppKit

/// 主题应用器：把 `ThemePreference` 落到 `NSApp.appearance`。
///
/// 为什么只设 `NSApp.appearance` 就够：配置窗口、启动器、切换器、
/// 密码管理器都是普通 `NSWindow` / `NSPanel`，继承应用的 appearance；
/// `NSVisualEffectView` 会自动跟随切换材质明暗。
enum ThemeApplier {
    /// 应用主题。传 nil 表示跟随系统。
    ///
    /// 用 `NSApplication.shared` 而不是 `NSApp`：`NSApp` 是隐式解包的全局
    /// 变量，只有 `NSApplication.shared` 被访问过之后才非 nil。`shared` 会
    /// 按需创建应用实例，所以本方法在 `app.run()` 之前调用也安全——
    /// 启动时先恢复用户主题、再跑事件循环正是预期用法。
    static func apply(_ preference: ThemePreference) {
        let app = NSApplication.shared
        switch preference {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// 保存并立即应用。
    ///
    /// 先应用再落盘：外观切换用户能立刻感知，落盘失败（如配置只读）
    /// 不应该让这次操作看起来「没反应」；写入失败只记录日志。
    /// 配置窗口在读配置失败时会以默认值展示，这里同样不打断交互。
    static func setPreference(_ preference: ThemePreference, store: ConfigStore = .shared) {
        apply(preference)
        guard var config = try? store.load() else { return }
        config.general.theme = preference
        do {
            try store.save(config)
        } catch {
            dbg("主题偏好保存失败: \(error)")
        }
    }
}
