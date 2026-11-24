import Foundation

/// 全应用统一配置。
///
/// 所有功能配置收敛到这一个结构，序列化为 `~/.config/tony-toy/config.json`。
/// 密码库（vault.jsonl）不在此列——它是独立的安全边界。
struct TonyToyConfig: Codable, Equatable {
    /// 配置格式版本，用于迁移。新增不兼容字段时 +1。
    var version: Int

    var general: GeneralConfig

    /// key 是 Feature.id，例如 "capsLayer" / "gamepad"
    var features: [String: FeatureConfig]

    static let `default` = TonyToyConfig(
        version: 1,
        general: GeneralConfig(),
        features: [:]
    )

    /// 读取某功能的开关状态。未配置过的功能默认启用（保持升级前后行为一致）。
    func isEnabled(_ featureID: String) -> Bool {
        features[featureID]?.isEnabled ?? true
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
