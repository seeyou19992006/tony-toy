import Foundation
import Cocoa

struct CapsMappingConfig: Codable {
    let version: Int
    let mappings: [CapsMappingEntry]
}

struct CapsMappingEntry: Codable {
    let from: String
    let to: CapsMappingTarget
}

struct CapsMappingTarget: Codable {
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

struct CapsResolvedMapping {
    let action: AppAction
}

enum CapsMappingConfigError: Error, CustomStringConvertible {
    case unknownSourceKey(String)
    case unknownTargetKey(String)
    case unknownModifier(String)

    var description: String {
        switch self {
        case .unknownSourceKey(let key):
            return "Unknown source key: \(key)"
        case .unknownTargetKey(let key):
            return "Unknown target key: \(key)"
        case .unknownModifier(let modifier):
            return "Unknown modifier: \(modifier)"
        }
    }
}

final class CapsMappingConfigStore {
    static let configRelativePath = KeyConfigSupport.configBasePath + "/caps-mappings.json"
    static let templateFileName = "caps-mappings.default.json"

    let configURL: URL
    let templateURL: URL

    init(
        configURL: URL = CapsMappingConfigStore.defaultConfigURL(),
        templateURL: URL? = nil
    ) {
        self.configURL = configURL
        self.templateURL = templateURL ?? Self.defaultTemplateURL()
    }

    func loadMappings() throws -> [Int64: CapsResolvedMapping] {
        try ensureConfigExists()
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(CapsMappingConfig.self, from: data)
        return try resolveMappings(config.mappings)
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

    private func resolveMappings(_ entries: [CapsMappingEntry]) throws -> [Int64: CapsResolvedMapping] {
        var resolved: [Int64: CapsResolvedMapping] = [:]
        for entry in entries {
            let fromCode = try Self.lookupSourceKeyCode(named: entry.from)
            let target = AppActionSpec(
                action: entry.to.action,
                key: entry.to.key,
                modifiers: entry.to.modifiers,
                bundleIdentifier: entry.to.bundleIdentifier
            )
            resolved[fromCode] = CapsResolvedMapping(action: try AppActionResolver.resolve(target))
        }
        return resolved
    }

    private static func lookupSourceKeyCode(named key: String) throws -> Int64 {
        guard let code = KeyConfigSupport.keyCode(named: key) else {
            throw CapsMappingConfigError.unknownSourceKey(key)
        }
        return Int64(code)
    }
}
