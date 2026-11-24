import Foundation

/// 一个可配置的功能单元。
///
/// 新增功能只需实现这个协议 + 在 `FeatureRegistry` 注册一行，
/// 配置窗口自动获得侧边栏条目和设置项绑定。
///
/// 设计目标是「新增功能只改 2 处」：一个 Feature 文件 + 一行注册。
protocol Feature: AnyObject {
    /// 唯一标识，同时作为 `config.json` 里 `features` 的 key
    var id: String { get }

    /// 侧边栏显示名
    var title: String { get }

    /// SF Symbols 图标名
    var icon: String { get }

    /// 设置项声明。界面据此渲染控件，不描述布局。
    var settings: [SettingItem] { get }

    /// 从未配置过时的默认开关状态。
    ///
    /// **不是所有功能都默认开启**：`switcher`（⌘Tab 接管）和
    /// `mouseFollow` 在旧 `UserDefaults` 里默认关闭，这里必须如实声明，
    /// 否则升级会改变用户既有行为。
    var defaultEnabled: Bool { get }

    /// 启动：注册事件 tap、建立 AX 连接等
    func start()

    /// 停止：注销 tap、释放资源
    func stop()

    /// 配置变更后热更新。
    ///
    /// 默认实现只按 `isEnabled` 启停；需要更细配置（如映射表）的
    /// Feature 应覆盖它，先按 `isEnabled` 处理启停，再应用自己的 values。
    func apply(_ config: FeatureConfig)
}

extension Feature {
    /// 默认实现：开关切换时启停
    func apply(_ config: FeatureConfig) {
        if config.isEnabled {
            start()
        } else {
            stop()
        }
    }
}

/// 设置项类型描述。
///
/// 只声明「有什么配置、什么类型、默认多少」，不管怎么摆——
/// 布局由各分区视图手写，自动生成布局在本项目规模是负担。
enum SettingItem {
    case toggle(key: String, title: String, defaultValue: Bool)

    /// 组合键。复用已有的 `HotkeyKeySpec`（`{ key: String, modifiers: [String]? }`），
    /// 不重复定义——注意与 `src/LauncherSettings.swift` 的 `HotkeySpec`
    /// （`{ keyCode: UInt32, modifiers: UInt32, title: String }`）不是一回事。
    case hotkey(key: String, title: String, defaultValue: HotkeyKeySpec)

    case number(key: String, title: String, defaultValue: Int, range: ClosedRange<Int>)

    case picker(
        key: String,
        title: String,
        options: [(value: String, label: String)],
        defaultValue: String
    )

    /// 映射表：界面用 `MappingTableEditor` 渲染（第三阶段实现）
    case table(key: String, title: String)
}
