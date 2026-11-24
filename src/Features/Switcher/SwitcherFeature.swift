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
            .number(key: "rows", title: "切换器行数", defaultValue: 3, range: 2...5),
        ]
    }

    /// Feature 自己持有 event tap 实例；`main.swift` 里的同名实例由整合时删除，
    /// 否则两个 tap 会同时抢 ⌘Tab（与 Caps 层同样的坑）。
    private let switcher = CmdTabSwitcher()

    /// 最近一次应用的展示配置。
    ///
    /// `SwitcherController` 目前没有公开的配置入口：`rows` 是 private，
    /// 每次 `show()` 都由 `static grid(for:)` 按窗口数自动推导行列。
    /// 所以这里只保存值，等控制器暴露 setter 后再转发——不假装已经生效。
    private(set) var rows = 3
    private(set) var mouseFollow = false

    func start() { switcher.start() }

    func stop() { switcher.stop() }

    /// 应用行数与鼠标跟随。
    ///
    /// TODO: 依赖协调者为 `SwitcherController` 增加 `configure(rows:mouseFollow:)`。
    /// 当前 `SwitcherController.grid(for:)` 固定按「竖向 x 行、横向 x+2 列」
    /// 自适应，直接改不到；鼠标跟随在 `main.swift` 里也只存了菜单状态、
    /// 没有行为实现。这两项先保存为属性，行为等控制器/窗口层补齐后接入。
    func applyValues(_ config: FeatureConfig) {
        if case .bool(let value)? = config.values["mouseFollow"] {
            mouseFollow = value
        }
        if case .int(let value)? = config.values["rows"] {
            rows = min(max(value, 2), 5)
        }
    }
}
