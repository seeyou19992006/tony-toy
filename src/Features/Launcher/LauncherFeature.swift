import Carbon.HIToolbox
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
        // 启动前先用配置初始化热键，避免「先注册默认值再立刻改」
        // 造成一次多余的 unregister/register。
        if let config = try? ConfigStore.shared.load(),
            let featureConfig = config.features[id]
        {
            applyValues(featureConfig)
        }
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
    /// 菜单栏显示用的热键标题（如 `⌥ D`）
    var hotkeyTitle: String { controller.hotkeyTitle }

    /// 从配置应用设置。
    ///
    /// 目前只有热键需要真正生效——其余三项（每页项数、拼音匹配、
    /// 无窗口应用）还需要 `PaletteWindow` / `AppIndex` 暴露接口，
    /// 等那两处改完再补（TODO 在各自的 setter 上）。
    func applyValues(_ config: FeatureConfig) {
        guard let keySpec = SettingsPaneViewController.decodeHotkey(config.values["hotkey"])
        else { return }

        guard let spec = Self.makeHotkeySpec(from: keySpec) else {
            dbg("启动器热键无法解析: \(keySpec.key)")
            return
        }
        controller.updateHotkey(spec)
    }

    // MARK: - 键名 → 键码

    /// 把配置文件里的键名（`{key: "d", modifiers: ["option"]}`）
    /// 转成 Carbon 热键需要的键码 + 修饰键掩码。
    ///
    /// 解析失败返回 nil——宁可不改也不注册一个错的键
    /// （错键会占住别的快捷键）。
    static func makeHotkeySpec(from keySpec: HotkeyKeySpec) -> HotkeySpec? {
        guard let keyCode = KeyConfigSupport.keyCode(named: keySpec.key) else { return nil }

        var modifiers: UInt32 = 0
        for name in keySpec.modifiers ?? [] {
            guard let flag = KeyConfigSupport.modifierFlag(named: name) else { continue }
            modifiers |= Self.carbonMask(from: flag)
        }

        return HotkeySpec(
            keyCode: UInt32(keyCode),
            modifiers: modifiers,
            title: title(for: keySpec))
    }

    /// `CGEventFlags` → Carbon 修饰键掩码。
    ///
    /// **两套位定义不同**，不能直接 `UInt32(flag.rawValue)`：
    ///   - Carbon（`RegisterEventHotKey` 要的）：shift=0x0200,
    ///     option=0x0800, control=0x1000, command=0x0100
    ///   - `CGEventFlags`：maskShift=0x00020000, maskAlternate=0x00080000,
    ///     maskControl=0x00040000, maskCommand=0x00100000
    ///
    /// 直接用 rawValue 会注册出完全错误的组合键（比如把 ⌥ 变成 ⌃）。
    private static func carbonMask(from flag: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        if flag.contains(.maskShift) { result |= UInt32(shiftKey) }
        if flag.contains(.maskControl) { result |= UInt32(controlKey) }
        if flag.contains(.maskAlternate) { result |= UInt32(optionKey) }
        if flag.contains(.maskCommand) { result |= UInt32(cmdKey) }
        return result
    }

    /// `{key: "d", modifiers: ["option"]}` → `⌥ D`
    private static func title(for keySpec: HotkeyKeySpec) -> String {
        let symbols: [String: String] = [
            "control": "⌃", "option": "⌥", "shift": "⇧",
            "command": "⌘", "fn": "fn",
        ]
        // 固定顺序，避免不同配置排出不同字符串
        let order = ["control", "option", "shift", "command", "fn"]
        let prefix =
            order
            .filter { (keySpec.modifiers ?? []).contains($0) }
            .compactMap { symbols[$0] }
            .joined()
        return prefix.isEmpty ? keySpec.key.uppercased() : "\(prefix) \(keySpec.key.uppercased())"
    }
}
