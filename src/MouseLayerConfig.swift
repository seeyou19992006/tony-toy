import Foundation
import Cocoa

struct MouseLayerConfig: Codable {
    let version: Int
    let activationButton: String
    let mappings: [MouseLayerMappingEntry]

    enum CodingKeys: String, CodingKey {
        case version
        case activationButton = "activation_button"
        case mappings
    }
}

struct MouseLayerMappingEntry: Codable {
    let from: MouseLayerInputSpec
    let to: MouseLayerActionSpec
}

struct MouseLayerInputSpec: Codable {
    let input: String
}

struct MouseLayerActionSpec: Codable {
    let action: String?
    let key: String?
    let modifiers: [String]?
    let bundleIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case action
        case key
        case modifiers
        case bundleIdentifier = "bundle_identifier"
    }
}

enum MouseLayerInput: Equatable {
    case scrollWheel
    case mouseButton(Int64)
}

enum MouseLayerAction: Equatable {
    case volumeScroll
    case appAction(AppAction)

    static func == (lhs: MouseLayerAction, rhs: MouseLayerAction) -> Bool {
        switch (lhs, rhs) {
        case (.volumeScroll, .volumeScroll):
            return true
        case (.appAction(let lhsAction), .appAction(let rhsAction)):
            return lhsAction == rhsAction
        default:
            return false
        }
    }
}

struct MouseLayerResolvedMapping {
    let input: MouseLayerInput
    let action: MouseLayerAction
}

struct MouseLayerResolvedConfig {
    let activationButton: Int64
    let mappings: [MouseLayerResolvedMapping]

    static let fallback = MouseLayerResolvedConfig(
        activationButton: 4,
        mappings: [
            MouseLayerResolvedMapping(input: .scrollWheel, action: .volumeScroll),
            MouseLayerResolvedMapping(input: .mouseButton(2), action: .appAction(.missionControl))
        ]
    )

    func action(for type: CGEventType, buttonNumber: Int64?) -> MouseLayerAction? {
        guard let input = Self.input(for: type, buttonNumber: buttonNumber) else {
            return nil
        }
        return mappings.first(where: { $0.input == input })?.action
    }

    private static func input(for type: CGEventType, buttonNumber: Int64?) -> MouseLayerInput? {
        switch type {
        case .scrollWheel:
            return .scrollWheel
        case .leftMouseDown, .leftMouseUp:
            return .mouseButton(buttonNumber ?? 0)
        case .rightMouseDown, .rightMouseUp:
            return .mouseButton(buttonNumber ?? 1)
        case .otherMouseDown, .otherMouseUp:
            guard let buttonNumber else {
                return nil
            }
            return .mouseButton(buttonNumber)
        default:
            return nil
        }
    }
}

enum MouseLayerConfigError: Error, CustomStringConvertible {
    case unknownActivationButton(String)
    case unknownInput(String)
    case unknownAction(String)
    case missingKeyForAction(String)
    case unknownKey(String)
    case unknownModifier(String)

    var description: String {
        switch self {
        case .unknownActivationButton(let button):
            return "Unknown activation button: \(button)"
        case .unknownInput(let input):
            return "Unknown mouse layer input: \(input)"
        case .unknownAction(let action):
            return "Unknown mouse layer action: \(action)"
        case .missingKeyForAction(let action):
            return "Missing key for mouse layer action: \(action)"
        case .unknownKey(let key):
            return "Unknown mouse layer key: \(key)"
        case .unknownModifier(let modifier):
            return "Unknown mouse layer modifier: \(modifier)"
        }
    }
}

final class MouseLayerConfigStore {
    static let configRelativePath = KeyConfigSupport.configBasePath + "/mouse-layer.json"
    static let templateFileName = "mouse-layer.default.json"

    let configURL: URL
    let templateURL: URL

    init(
        configURL: URL = MouseLayerConfigStore.defaultConfigURL(),
        templateURL: URL? = nil
    ) {
        self.configURL = configURL
        self.templateURL = templateURL ?? Self.defaultTemplateURL()
    }

    func loadConfig() throws -> MouseLayerResolvedConfig {
        // 优先从统一配置读，理由同 `HotkeyMappingConfigStore`
        if let unified = unifiedConfig() {
            return try resolve(unified)
        }

        // 兼容：还没迁移的老配置
        try ensureConfigExists()
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(MouseLayerConfig.self, from: data)
        return try resolve(config)
    }

    /// 从 `config.json` 的 `features.mouseLayer.values` 还原配置。
    ///
    /// 侧键层比另两个映射表多一个 `activationButton`（激活键），
    /// 做迁移时单独存在 `values` 里。
    private func unifiedConfig() -> MouseLayerConfig? {
        guard let config = try? ConfigStore.shared.load(),
            let feature = config.features[FeatureID.mouseLayer],
            case .array(let list)? = feature.values["mappings"]
        else { return nil }

        guard let data = try? JSONEncoder().encode(JSONValue.array(list)),
            let mappings = try? JSONDecoder().decode([MouseLayerMappingEntry].self, from: data)
        else { return nil }

        // 激活键缺失时用默认值（与 resources/mouse-layer.default.json 一致）
        let activationButton: String
        if case .string(let value)? = feature.values["activationButton"] {
            activationButton = value
        } else {
            activationButton = "button5"
        }

        return MouseLayerConfig(
            version: 1,
            activationButton: activationButton,
            mappings: mappings
        )
    }

    func ensureConfigExists() throws {
        guard !FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }

        let directoryURL = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let templateData = try Data(contentsOf: templateURL)
        try templateData.write(to: configURL, options: .atomic)
    }

    static func defaultConfigURL() -> URL {
        KeyConfigSupport.defaultConfigURL(relativePath: configRelativePath)
    }

    static func defaultTemplateURL() -> URL {
        KeyConfigSupport.defaultTemplateURL(templateFileName: templateFileName)
    }

    private func resolve(_ config: MouseLayerConfig) throws -> MouseLayerResolvedConfig {
        let activationButton = try Self.resolveButtonNumber(named: config.activationButton)
        let mappings = try config.mappings.map(Self.resolve)
        return MouseLayerResolvedConfig(activationButton: activationButton, mappings: mappings)
    }

    private static func resolve(_ entry: MouseLayerMappingEntry) throws -> MouseLayerResolvedMapping {
        let input = try resolveInput(entry.from.input)
        let action = try resolveAction(entry.to)
        return MouseLayerResolvedMapping(input: input, action: action)
    }

    private static func resolveInput(_ input: String) throws -> MouseLayerInput {
        switch try KeyConfigSupport.mouseInput(named: input).kind {
        case .scrollWheel:
            return .scrollWheel
        case .mouseButton(let buttonNumber):
            return .mouseButton(buttonNumber)
        }
    }

    private static func resolveAction(_ spec: MouseLayerActionSpec) throws -> MouseLayerAction {
        let actionName = try resolveActionName(spec)
        switch actionName {
        case "volume_scroll":
            return .volumeScroll
        default:
            let appActionSpec = AppActionSpec(
                action: spec.action,
                key: spec.key,
                modifiers: spec.modifiers,
                bundleIdentifier: spec.bundleIdentifier
            )
            return .appAction(try AppActionResolver.resolve(appActionSpec))
        }
    }

    private static func resolveActionName(_ spec: MouseLayerActionSpec) throws -> String {
        if let action = spec.action {
            return try KeyConfigSupport.actionKind(named: action)
        }
        if spec.key != nil {
            return "send_hotkey"
        }
        throw MouseLayerConfigError.unknownAction("<missing>")
    }

    private static func resolveButtonNumber(named name: String) throws -> Int64 {
        switch try KeyConfigSupport.mouseInput(named: name).kind {
        case .scrollWheel:
            throw MouseLayerConfigError.unknownActivationButton(name)
        case .mouseButton(let buttonNumber):
            return buttonNumber
        }
    }
}
