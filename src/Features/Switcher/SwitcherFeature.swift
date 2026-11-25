import Foundation

/// 窗口切换器（⌘Tab 接管）。
///
/// 按下 ⌘Tab 时弹出窗口网格，按住 ⌘ 期间用方向键 / E·D·S·F 循环选择，
/// 松开 ⌘ 执行选中项。底层是 `CmdTabSwitcher` 的 event tap。
///
/// **默认关闭是刻意的**：旧 `MenuStateStore` 里 `isCmdTabEnabled` 默认
/// `false`。接管系统 ⌘Tab 属于「抢快捷键」的行为，升级到新配置体系时
/// 必须保持用户既有体验——声明成 `true` 会让没做过任何设置的用户
/// 突然失去系统切换器。
final class SwitcherFeature: Feature {
    let id = FeatureID.switcher
    let title = "窗口"
    let icon = "macwindow"

    /// 旧 `MenuStateStore.isCmdTabEnabled` 默认 false，不能写成 true
    let defaultEnabled = false

    var settings: [SettingItem] {
        [
            .toggle(key: "enabled", title: "启用 ⌘Tab 接管", defaultValue: defaultEnabled),
            .toggle(key: "mouseFollow", title: "切换时鼠标移到窗口中心", defaultValue: false),
            .toggle(key: "showWindowlessApps", title: "显示无窗口应用", defaultValue: true),
        ]
    }

    /// Feature 自己持有 event tap 实例；`main.swift` 里的同名实例由整合时删除，
    /// 否则两个 tap 会同时抢 ⌘Tab（与 Caps 层同样的坑）。
    private let switcher = CmdTabSwitcher()

    /// 最近一次应用的展示配置。
    private(set) var mouseFollow = false
    private(set) var showWindowlessApps = true

    func start() { switcher.start() }

    func stop() { switcher.stop() }

    /// 应用切换器配置并同步到 `SwitcherController`。
    func applyValues(_ config: FeatureConfig) {
        if case .bool(let value)? = config.values["mouseFollow"] {
            mouseFollow = value
        } else {
            mouseFollow = false
        }
        if case .bool(let value)? = config.values["showWindowlessApps"] {
            showWindowlessApps = value
        } else {
            showWindowlessApps = true
        }
        SwitcherController.shared.configure(
            mouseFollow: mouseFollow,
            showWindowlessApps: showWindowlessApps
        )
    }
}
