import Foundation

/// 全应用统一配置。
///
/// 所有功能配置收敛到这一个结构，序列化为 `~/.config/tony-toy/config.json`。
/// 密码库（vault.jsonl）不在此列——它是独立的安全边界。
struct TonyToyConfig: Codable, Equatable {
    /// 配置格式版本。当前值的唯一来源是 `currentVersion`（见下）。
    var version: Int

    var general: GeneralConfig

    /// key 是 Feature.id，例如 "capsLayer" / "gamepad"
    var features: [String: FeatureConfig]

    /// 当前配置格式版本。新增不兼容字段时 +1。
    static let currentVersion = 1

    static let `default` = TonyToyConfig(
        version: currentVersion,
        general: GeneralConfig(),
        features: [:]
    )

    /// 成员初始化器。声明了 `init(from:)` 后编译器不再合成它，这里显式补回。
    init(version: Int, general: GeneralConfig, features: [String: FeatureConfig]) {
        self.version = version
        self.general = general
        self.features = features
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 用 decodeIfPresent 而不是 decode：缺字段时用默认值，
        // 否则手写 JSON 漏一个字段就会让整份配置被判损坏并静默重置。
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        general = try container.decodeIfPresent(GeneralConfig.self, forKey: .general)
            ?? GeneralConfig()
        features = try container.decodeIfPresent([String: FeatureConfig].self, forKey: .features)
            ?? [:]
    }

    /// 读取某功能的开关状态。
    ///
    /// - Parameters:
    ///   - featureID: 功能的唯一标识
    ///   - defaultEnabled: 未配置过时使用的默认值。
    ///     **必须由 Feature 自己声明**——不是所有功能都默认开启。
    ///     旧 `UserDefaults` 里 `switcher`（⌘Tab 接管）和 `mouseFollow`
    ///     的默认是 `false`，硬编码 `true` 会改变这些功能的既有行为。
    func isEnabled(_ featureID: String, defaultEnabled: Bool = true) -> Bool {
        features[featureID]?.isEnabled ?? defaultEnabled
    }
}

struct GeneralConfig: Codable, Equatable {
    var launchAtLogin: Bool
    var theme: ThemePreference
    var showMenuBarIcon: Bool

    init(
        launchAtLogin: Bool = false,
        theme: ThemePreference = .system,
        showMenuBarIcon: Bool = true
    ) {
        self.launchAtLogin = launchAtLogin
        self.theme = theme
        self.showMenuBarIcon = showMenuBarIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GeneralConfig()
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
            ?? defaults.launchAtLogin
        theme = try container.decodeIfPresent(ThemePreference.self, forKey: .theme)
            ?? defaults.theme
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon)
            ?? defaults.showMenuBarIcon
    }
}

/// 单个功能的配置：开关 + 任意键值对。
///
/// `values` 用 JSONValue 承载而不是泛型，因为各功能的配置结构差异很大
/// （映射表 vs 单个数字 vs 快捷键）。Feature 在 apply 时自己解码。
struct FeatureConfig: Codable, Equatable {
    var isEnabled: Bool
    var values: [String: JSONValue]

    init(isEnabled: Bool = true, values: [String: JSONValue] = [:]) {
        self.isEnabled = isEnabled
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FeatureConfig()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? defaults.isEnabled
        values = try container.decodeIfPresent([String: JSONValue].self, forKey: .values)
            ?? defaults.values
    }
}

/// 主题偏好。system 表示跟随系统外观。
enum ThemePreference: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// Feature 的唯一标识。集中定义，避免字符串字面量扩散到各处拼错。
///
/// 值与 `Feature.id` 必须一致。新增功能时同时在这里加一个常量。
enum FeatureID {
    static let capsLayer = "capsLayer"
    static let hotkeyLayer = "hotkeyLayer"
    static let mouseLayer = "mouseLayer"
    static let launcher = "launcher"
    static let switcher = "switcher"
    static let passwordVault = "passwordVault"
    static let gamepad = "gamepad"
    static let inputAliases = "inputAliases"
}
