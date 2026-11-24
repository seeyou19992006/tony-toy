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

    /// 应用功能自己的配置值（映射表、每页项数等）。
    ///
    /// 默认空实现——只有开关的功能不需要覆盖它。
    /// 需要更细配置的 Feature 覆盖这个方法，**不要覆盖 `apply`**：
    /// `apply` 是模板方法，保证「先启停、再应用 values」的顺序。
    func applyValues(_ config: FeatureConfig)
}

extension Feature {
    /// 统一的配置应用入口（模板方法）。
    ///
    /// **不要覆盖这个方法**——它保证「先按开关启停，再应用具体配置」的
    /// 顺序。Feature 只覆盖 `applyValues(_:)`。
    ///
    /// 之所以不把它做成协议需求：协议扩展的方法没有 `super`，
    /// 一旦某个 Feature 覆盖了 `apply`，就再也调不回这个默认实现，
    /// 「忘记启停」会变成静默 bug。
    func apply(_ config: FeatureConfig) {
        if config.isEnabled {
            start()
            applyValues(config)
        } else {
            stop()
        }
    }

    /// 默认空实现：只有开关的功能不用覆盖
    func applyValues(_ config: FeatureConfig) {}
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
