import Foundation
import Cocoa
struct HotkeyMappingConfig: Codable {
    let version: Int
    let mappings: [HotkeyMappingEntry]
}

struct HotkeyMappingEntry: Codable {
    let from: HotkeyKeySpec
    let to: AppActionSpec
}

struct HotkeyKeySpec: Codable {
    let key: String
    let modifiers: [String]?
}

struct HotkeyResolvedMapping {
    let sourceCode: Int64
    let sourceModifiers: CGEventFlags
    let action: AppAction

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard sourceCode == keyCode else {
            return false
        }

        let normalized = normalizedModifiers(flags)
        if normalized == sourceModifiers {
            return true
        }

        guard !sourceModifiers.contains(.maskSecondaryFn) else {
            return false
        }

        var normalizedWithoutFn = normalized
        normalizedWithoutFn.remove(.maskSecondaryFn)
        return normalizedWithoutFn == sourceModifiers
    }

    private func normalizedModifiers(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn])
    }
}

enum HotkeyMappingConfigError: Error, CustomStringConvertible {
    case unknownKey(String)
    case unknownModifier(String)

    var description: String {
        switch self {
        case .unknownKey(let key):
            return "Unknown hotkey key: \(key)"
        case .unknownModifier(let modifier):
            return "Unknown hotkey modifier: \(modifier)"
        }
    }
}

final class HotkeyMappingConfigStore {
    static let configRelativePath = KeyConfigSupport.configBasePath + "/hotkeys.json"
    static let templateFileName = "hotkeys.default.json"
    static let keyboardANSI = KeyConfigSupport.keyboardANSI
    static let keyboardISO = KeyConfigSupport.keyboardISO
    static let keyboardJIS = KeyConfigSupport.keyboardJIS

    let configURL: URL
    let templateURL: URL

    init(
        configURL: URL = HotkeyMappingConfigStore.defaultConfigURL(),
        templateURL: URL? = nil
    ) {
        self.configURL = configURL
        self.templateURL = templateURL ?? Self.defaultTemplateURL()
    }

    func loadMappings() throws -> [HotkeyResolvedMapping] {
        try ensureConfigExists()
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(HotkeyMappingConfig.self, from: data)
        return try config.mappings.map(resolve)
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

    private func resolve(_ entry: HotkeyMappingEntry) throws -> HotkeyResolvedMapping {
        let keyboardLayoutType = KeyConfigSupport.currentKeyboardLayoutType()
        let sourceCode = try Self.lookupKeyCode(named: entry.from.key, keyboardLayoutType: keyboardLayoutType)
        let sourceModifiers = try Self.resolveModifiers(entry.from.modifiers ?? [])
        return HotkeyResolvedMapping(
            sourceCode: Int64(sourceCode),
            sourceModifiers: sourceModifiers,
            action: try AppActionResolver.resolve(entry.to)
        )
    }

    static func lookupKeyCode(named key: String, keyboardLayoutType: Int? = nil) throws -> CGKeyCode {
        guard let code = KeyConfigSupport.keyCode(named: key, keyboardLayoutType: keyboardLayoutType) else {
            throw HotkeyMappingConfigError.unknownKey(key)
        }
        return code
    }

    private static func resolveModifiers(_ modifiers: [String]) throws -> CGEventFlags {
        try modifiers.reduce(into: CGEventFlags()) { result, modifier in
            guard let flag = KeyConfigSupport.modifierFlag(named: modifier) else {
                throw HotkeyMappingConfigError.unknownModifier(modifier)
            }
            result.insert(flag)
        }
    }
}
