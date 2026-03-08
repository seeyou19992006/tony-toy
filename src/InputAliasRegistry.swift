import Foundation
import Cocoa

struct AliasMouseInput: Equatable {
    enum Kind: Equatable {
        case scrollWheel
        case mouseButton(Int64)
    }

    let kind: Kind
}

struct InputAliasRegistryConfig: Codable {
    let version: Int
    let keyboardKeys: [String: KeyboardKeyAliasSpec]
    let modifiers: [String: ModifierAliasSpec]
    let mouseInputs: [String: MouseInputAliasSpec]
    let actions: [String: MouseActionAliasSpec]?
    let legacyMouseActions: [String: MouseActionAliasSpec]?

    enum CodingKeys: String, CodingKey {
        case version
        case keyboardKeys = "keyboard_keys"
        case modifiers
        case mouseInputs = "mouse_inputs"
        case actions
        case legacyMouseActions = "mouse_actions"
    }
}

struct KeyboardKeyAliasSpec: Codable {
    let keyCode: Int?
    let keyCodeByLayout: KeyboardLayoutKeyCodeSpec?

    enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case keyCodeByLayout = "key_code_by_layout"
    }
}

struct KeyboardLayoutKeyCodeSpec: Codable {
    let ansi: Int?
    let iso: Int?
    let jis: Int?
}

struct ModifierAliasSpec: Codable {
    let flag: String
    let keyCode: Int?

    enum CodingKeys: String, CodingKey {
        case flag
        case keyCode = "key_code"
    }
}

struct MouseInputAliasSpec: Codable {
    let kind: String
    let buttonNumber: Int64?

    enum CodingKeys: String, CodingKey {
        case kind
        case buttonNumber = "button_number"
    }
}

struct MouseActionAliasSpec: Codable {
    let kind: String
}

struct InputAliasRegistry {
    struct KeyboardAliasDefinition {
        let fixedKeyCode: CGKeyCode?
        let keyCodeByLayout: [Int: CGKeyCode]
    }

    struct ModifierAliasDefinition {
        let flag: CGEventFlags
        let keyCode: CGKeyCode?
    }

    private let keyboardAliases: [String: KeyboardAliasDefinition]
    private let modifierAliases: [String: ModifierAliasDefinition]
    private let modifierKeyCodes: [UInt64: CGKeyCode]
    private let mouseInputs: [String: AliasMouseInput]
    private let mouseActions: [String: String]

    init(
        keyboardAliases: [String: KeyboardAliasDefinition],
        modifierAliases: [String: ModifierAliasDefinition],
        mouseInputs: [String: AliasMouseInput],
        mouseActions: [String: String]
    ) {
        self.keyboardAliases = keyboardAliases
        self.modifierAliases = modifierAliases
        self.mouseInputs = mouseInputs
        self.mouseActions = mouseActions
        self.modifierKeyCodes = modifierAliases.values.reduce(into: [:]) { result, definition in
            guard let keyCode = definition.keyCode else {
                return
            }
            let flagKey = definition.flag.rawValue
            if let existing = result[flagKey] {
                result[flagKey] = min(existing, keyCode)
            } else {
                result[flagKey] = keyCode
            }
        }
    }

    func keyCode(named key: String, keyboardLayoutType: Int) -> CGKeyCode? {
        guard let definition = keyboardAliases[key.lowercased()] else {
            return nil
        }
        if let layoutKeyCode = definition.keyCodeByLayout[keyboardLayoutType] {
            return layoutKeyCode
        }
        return definition.fixedKeyCode
    }

    func modifierFlag(named modifier: String) -> CGEventFlags? {
        modifierAliases[modifier.lowercased()]?.flag
    }

    func modifierKeyCode(for flag: CGEventFlags) -> CGKeyCode? {
        modifierKeyCodes[flag.rawValue]
    }

    func mouseInput(named name: String) throws -> AliasMouseInput {
        guard let input = mouseInputs[name.lowercased()] else {
            throw InputAliasRegistryError.unknownMouseInput(name)
        }
        return input
    }

    func actionKind(named name: String) throws -> String {
        guard let action = mouseActions[name.lowercased()] else {
            throw InputAliasRegistryError.unknownAction(name)
        }
        return action
    }

    static let fallback = InputAliasRegistry(
        keyboardAliases: [
            "a": .init(fixedKeyCode: 0, keyCodeByLayout: [:]),
            "s": .init(fixedKeyCode: 1, keyCodeByLayout: [:]),
            "d": .init(fixedKeyCode: 2, keyCodeByLayout: [:]),
            "f": .init(fixedKeyCode: 3, keyCodeByLayout: [:]),
            "h": .init(fixedKeyCode: 4, keyCodeByLayout: [:]),
            "g": .init(fixedKeyCode: 5, keyCodeByLayout: [:]),
            "z": .init(fixedKeyCode: 6, keyCodeByLayout: [:]),
            "x": .init(fixedKeyCode: 7, keyCodeByLayout: [:]),
            "c": .init(fixedKeyCode: 8, keyCodeByLayout: [:]),
            "v": .init(fixedKeyCode: 9, keyCodeByLayout: [:]),
            "b": .init(fixedKeyCode: 11, keyCodeByLayout: [:]),
            "q": .init(fixedKeyCode: 12, keyCodeByLayout: [:]),
            "w": .init(fixedKeyCode: 13, keyCodeByLayout: [:]),
            "e": .init(fixedKeyCode: 14, keyCodeByLayout: [:]),
            "r": .init(fixedKeyCode: 15, keyCodeByLayout: [:]),
            "y": .init(fixedKeyCode: 16, keyCodeByLayout: [:]),
            "t": .init(fixedKeyCode: 17, keyCodeByLayout: [:]),
            "1": .init(fixedKeyCode: 18, keyCodeByLayout: [:]),
            "2": .init(fixedKeyCode: 19, keyCodeByLayout: [:]),
            "3": .init(fixedKeyCode: 20, keyCodeByLayout: [:]),
            "4": .init(fixedKeyCode: 21, keyCodeByLayout: [:]),
            "6": .init(fixedKeyCode: 22, keyCodeByLayout: [:]),
            "5": .init(fixedKeyCode: 23, keyCodeByLayout: [:]),
            "equal_sign": .init(fixedKeyCode: 24, keyCodeByLayout: [:]),
            "9": .init(fixedKeyCode: 25, keyCodeByLayout: [:]),
            "7": .init(fixedKeyCode: 26, keyCodeByLayout: [:]),
            "hyphen": .init(fixedKeyCode: 27, keyCodeByLayout: [:]),
            "8": .init(fixedKeyCode: 28, keyCodeByLayout: [:]),
            "0": .init(fixedKeyCode: 29, keyCodeByLayout: [:]),
            "close_bracket": .init(fixedKeyCode: 30, keyCodeByLayout: [:]),
            "o": .init(fixedKeyCode: 31, keyCodeByLayout: [:]),
            "u": .init(fixedKeyCode: 32, keyCodeByLayout: [:]),
            "open_bracket": .init(fixedKeyCode: 33, keyCodeByLayout: [:]),
            "i": .init(fixedKeyCode: 34, keyCodeByLayout: [:]),
            "p": .init(fixedKeyCode: 35, keyCodeByLayout: [:]),
            "return_or_enter": .init(fixedKeyCode: 36, keyCodeByLayout: [:]),
            "l": .init(fixedKeyCode: 37, keyCodeByLayout: [:]),
            "j": .init(fixedKeyCode: 38, keyCodeByLayout: [:]),
            "quote": .init(fixedKeyCode: 39, keyCodeByLayout: [:]),
            "k": .init(fixedKeyCode: 40, keyCodeByLayout: [:]),
            "semicolon": .init(fixedKeyCode: 41, keyCodeByLayout: [:]),
            "backslash": .init(fixedKeyCode: 42, keyCodeByLayout: [:]),
            "comma": .init(fixedKeyCode: 43, keyCodeByLayout: [:]),
            "slash": .init(fixedKeyCode: 44, keyCodeByLayout: [:]),
            "n": .init(fixedKeyCode: 45, keyCodeByLayout: [:]),
            "m": .init(fixedKeyCode: 46, keyCodeByLayout: [:]),
            "period": .init(fixedKeyCode: 47, keyCodeByLayout: [:]),
            "tab": .init(fixedKeyCode: 48, keyCodeByLayout: [:]),
            "spacebar": .init(fixedKeyCode: 49, keyCodeByLayout: [:]),
            "grave_accent_and_tilde": .init(fixedKeyCode: nil, keyCodeByLayout: [
                KeyConfigSupport.keyboardANSI: 50,
                KeyConfigSupport.keyboardISO: 10,
                KeyConfigSupport.keyboardJIS: 50
            ]),
            "delete_or_backspace": .init(fixedKeyCode: 51, keyCodeByLayout: [:]),
            "escape": .init(fixedKeyCode: 53, keyCodeByLayout: [:]),
            "caps_lock": .init(fixedKeyCode: 57, keyCodeByLayout: [:]),
            "delete_forward": .init(fixedKeyCode: 117, keyCodeByLayout: [:]),
            "left_arrow": .init(fixedKeyCode: 123, keyCodeByLayout: [:]),
            "right_arrow": .init(fixedKeyCode: 124, keyCodeByLayout: [:]),
            "down_arrow": .init(fixedKeyCode: 125, keyCodeByLayout: [:]),
            "up_arrow": .init(fixedKeyCode: 126, keyCodeByLayout: [:])
        ],
        modifierAliases: [
            "shift": .init(flag: .maskShift, keyCode: 56),
            "left_shift": .init(flag: .maskShift, keyCode: 56),
            "right_shift": .init(flag: .maskShift, keyCode: 60),
            "option": .init(flag: .maskAlternate, keyCode: 58),
            "left_option": .init(flag: .maskAlternate, keyCode: 58),
            "right_option": .init(flag: .maskAlternate, keyCode: 61),
            "command": .init(flag: .maskCommand, keyCode: 55),
            "left_command": .init(flag: .maskCommand, keyCode: 55),
            "right_command": .init(flag: .maskCommand, keyCode: 54),
            "control": .init(flag: .maskControl, keyCode: 59),
            "left_control": .init(flag: .maskControl, keyCode: 59),
            "right_control": .init(flag: .maskControl, keyCode: 62),
            "fn": .init(flag: .maskSecondaryFn, keyCode: nil)
        ],
        mouseInputs: [
            "scroll_wheel": .init(kind: .scrollWheel),
            "left_click": .init(kind: .mouseButton(0)),
            "right_click": .init(kind: .mouseButton(1)),
            "middle_click": .init(kind: .mouseButton(2)),
            "button1": .init(kind: .mouseButton(0)),
            "button2": .init(kind: .mouseButton(1)),
            "button3": .init(kind: .mouseButton(2)),
            "button4": .init(kind: .mouseButton(3)),
            "button5": .init(kind: .mouseButton(4)),
            "button6": .init(kind: .mouseButton(5)),
            "button7": .init(kind: .mouseButton(6)),
            "button8": .init(kind: .mouseButton(7))
        ],
        mouseActions: [
            "volume_scroll": "volume_scroll",
            "mission_control": "mission_control",
            "send_hotkey": "send_hotkey"
        ]
    )
}

enum InputAliasRegistryError: Error, CustomStringConvertible {
    case unknownModifierFlag(String)
    case invalidKeyboardAlias(String)
    case invalidMouseInput(String)
    case invalidAction(String)
    case unknownMouseInput(String)
    case unknownAction(String)

    var description: String {
        switch self {
        case .unknownModifierFlag(let flag):
            return "Unknown modifier flag alias: \(flag)"
        case .invalidKeyboardAlias(let name):
            return "Invalid keyboard alias definition: \(name)"
        case .invalidMouseInput(let name):
            return "Invalid mouse input alias definition: \(name)"
        case .invalidAction(let name):
            return "Invalid action alias definition: \(name)"
        case .unknownMouseInput(let name):
            return "Unknown mouse input alias: \(name)"
        case .unknownAction(let name):
            return "Unknown action alias: \(name)"
        }
    }
}

final class InputAliasRegistryStore {
    static let configRelativePath = KeyConfigSupport.configBasePath + "/input-aliases.json"
    static let templateFileName = "input-aliases.default.json"

    let configURL: URL
    let templateURL: URL

    init(
        configURL: URL = InputAliasRegistryStore.defaultConfigURL(),
        templateURL: URL? = nil
    ) {
        self.configURL = configURL
        self.templateURL = templateURL ?? Self.defaultTemplateURL()
    }

    func loadRegistry() throws -> InputAliasRegistry {
        try ensureConfigExists()
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(InputAliasRegistryConfig.self, from: data)
        return try resolve(config)
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

    private func resolve(_ config: InputAliasRegistryConfig) throws -> InputAliasRegistry {
        let keyboardAliases = try config.keyboardKeys.reduce(into: [String: InputAliasRegistry.KeyboardAliasDefinition]()) { result, entry in
            result[entry.key.lowercased()] = try resolveKeyboardAlias(name: entry.key, spec: entry.value)
        }

        let modifierAliases = try config.modifiers.reduce(into: [String: InputAliasRegistry.ModifierAliasDefinition]()) { result, entry in
            result[entry.key.lowercased()] = try resolveModifierAlias(spec: entry.value)
        }

        let mouseInputs = try config.mouseInputs.reduce(into: [String: AliasMouseInput]()) { result, entry in
            result[entry.key.lowercased()] = try resolveMouseInput(name: entry.key, spec: entry.value)
        }

        let actionSpecs = config.actions ?? config.legacyMouseActions ?? [:]
        let mouseActions = try actionSpecs.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = try resolveAction(name: entry.key, spec: entry.value)
        }

        return InputAliasRegistry(
            keyboardAliases: keyboardAliases,
            modifierAliases: modifierAliases,
            mouseInputs: mouseInputs,
            mouseActions: mouseActions
        )
    }

    private func resolveKeyboardAlias(name: String, spec: KeyboardKeyAliasSpec) throws -> InputAliasRegistry.KeyboardAliasDefinition {
        let fixedKeyCode = spec.keyCode.map(CGKeyCode.init)
        var keyCodeByLayout: [Int: CGKeyCode] = [:]
        if let layout = spec.keyCodeByLayout {
            if let ansi = layout.ansi {
                keyCodeByLayout[KeyConfigSupport.keyboardANSI] = CGKeyCode(ansi)
            }
            if let iso = layout.iso {
                keyCodeByLayout[KeyConfigSupport.keyboardISO] = CGKeyCode(iso)
            }
            if let jis = layout.jis {
                keyCodeByLayout[KeyConfigSupport.keyboardJIS] = CGKeyCode(jis)
            }
        }

        guard fixedKeyCode != nil || !keyCodeByLayout.isEmpty else {
            throw InputAliasRegistryError.invalidKeyboardAlias(name)
        }

        return .init(fixedKeyCode: fixedKeyCode, keyCodeByLayout: keyCodeByLayout)
    }

    private func resolveModifierAlias(spec: ModifierAliasSpec) throws -> InputAliasRegistry.ModifierAliasDefinition {
        guard let flag = fallbackModifierFlag(named: spec.flag) else {
            throw InputAliasRegistryError.unknownModifierFlag(spec.flag)
        }
        return .init(flag: flag, keyCode: spec.keyCode.map(CGKeyCode.init))
    }

    private func resolveMouseInput(name: String, spec: MouseInputAliasSpec) throws -> AliasMouseInput {
        switch spec.kind.lowercased() {
        case "scroll_wheel":
            return .init(kind: .scrollWheel)
        case "button":
            guard let buttonNumber = spec.buttonNumber else {
                throw InputAliasRegistryError.invalidMouseInput(name)
            }
            return .init(kind: .mouseButton(buttonNumber))
        default:
            throw InputAliasRegistryError.invalidMouseInput(name)
        }
    }

    private func resolveAction(name: String, spec: MouseActionAliasSpec) throws -> String {
        let kind = spec.kind.lowercased()
        switch kind {
        case "volume_scroll", "mission_control", "send_hotkey", "activate_application", "move_window_to_adjacent_display", "maximize_window":
            return kind
        default:
            throw InputAliasRegistryError.invalidAction(name)
        }
    }

    private func fallbackModifierFlag(named name: String) -> CGEventFlags? {
        InputAliasRegistry.fallback.modifierFlag(named: name)
    }
}
