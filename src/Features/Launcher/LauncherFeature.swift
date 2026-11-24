import Foundation

/// 应用启动器。
///
/// 全局热键呼出搜索面板，只搜应用，回车切到该应用最近使用的窗口。
final class LauncherFeature: Feature {
    let id = FeatureID.launcher
    let title = "启动器"
    let icon = "magnifyingglass"

    /// 启动器旧版没有独立开关（只有 `LauncherSettings` 的快捷键配置），
    /// 无历史默认值可继承，按「默认开启」声明。
    let defaultEnabled = true

    var settings: [SettingItem] {
        [
            .hotkey(
                key: "hotkey",
                title: "呼出快捷键",
                defaultValue: HotkeyKeySpec(key: "d", modifiers: ["option"])
            ),
            .number(key: "pageSize", title: "每页显示项数", defaultValue: 8, range: 4...12),
            .toggle(key: "pinyinMatch", title: "拼音匹配", defaultValue: true),
            .toggle(key: "showWindowlessApps", title: "显示无窗口应用", defaultValue: true),
        ]
    }

    /// 启动器是单例（`private init`），不能自己 new 一个。
    private let controller = LauncherController.shared

    /// 弹出搜索面板（托盘菜单「应用启动器」调它）
    func show() {
        controller.show()
    }

    /// `LauncherController` 没有 stop()/setEnabled()，无法真正下线。
    /// 用本地状态防止配置热更新时重复 `start()`——那会新建第二个
    /// `PaletteWindow` 并泄漏一个窗口（热键注册本身会先 unregister，不会重复）。
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        controller.start()
        isStarted = true
    }

    func stop() {
        // 不假装停止：控制器没有关闭面板/注销热键的公开接口，
        // 也不能在这里自己改控制器文件。记录日志，等协调者补接口后再接。
        dbg("启动器收到停止请求，但 LauncherController 缺少 stop()/setEnabled()，未执行")
    }

    /// 呼出快捷键 / 每页项数 / 拼音匹配 / 显示无窗口应用都要运行时接口。
    ///
    /// TODO: 依赖协调者为启动器补应用接口。现状缺口：
    /// - 热键：只能通过 `LauncherSettings.selectedHotkeyIndex` 从 5 个预设里选，
    ///   拿不到 `HotkeyKeySpec` 的任意键名，且改完需要重新注册；
    /// - `PaletteWindow.pageSize` / `maxRows` 是 private `let 8`，无法改；
    /// - 拼音匹配在 `AppIndex.search` 里是写死的，没有开关；
    /// - “显示无窗口应用”目前没有对应过滤逻辑，只有状态标记。
    func applyValues(_ config: FeatureConfig) {}
}
