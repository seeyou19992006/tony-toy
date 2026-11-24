import Foundation

/// 组合键的声明形式（配置文件里的形状）。
///
/// 原本定义在 `HotkeyMappingConfig.swift`，与热键运行时（CGEventFlags、
/// Carbon 键码表）放在一起。但 `SettingItem.hotkey` 的默认值也要用它，
/// 而配置层（`src/Core/`）必须能被纯 Foundation 的单元测试编译——
/// 拖入 `HotkeyMappingConfig.swift` 会级联拉进 `KeyConfigSupport`（Carbon）、
/// `AppAction`、`InputAliasRegistry` 等 AppKit 层文件。故把纯数据定义下沉到 Core。
///
/// 注意与 `src/LauncherSettings.swift` 的 `HotkeySpec`
/// （`{ keyCode: UInt32, modifiers: UInt32, title: String }`）区分：
/// 那个是解析后的键码，这个是配置文件里的键名。
struct HotkeyKeySpec: Codable {
    let key: String
    let modifiers: [String]?
}
