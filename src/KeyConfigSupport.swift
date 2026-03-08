import Foundation
import Cocoa
import Carbon.HIToolbox

enum KeyConfigSupport {
    static let configBasePath = ".config/tony-toy"
    static let keyboardANSI = Int(kKeyboardANSI)
    static let keyboardISO = Int(kKeyboardISO)
    static let keyboardJIS = Int(kKeyboardJIS)

    static func defaultConfigURL(relativePath: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(relativePath)
    }

    static func defaultTemplateURL(templateFileName: String) -> URL {
        if let bundleURL = Bundle.main.url(forResource: templateFileName.replacingOccurrences(of: ".json", with: ""), withExtension: "json") {
            return bundleURL
        }

        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        let executableTemplate = executableDirectory.appendingPathComponent(templateFileName)
        if FileManager.default.fileExists(atPath: executableTemplate.path) {
            return executableTemplate
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resourceTemplate = currentDirectory
            .appendingPathComponent("resources")
            .appendingPathComponent(templateFileName)
        if FileManager.default.fileExists(atPath: resourceTemplate.path) {
            return resourceTemplate
        }

        return currentDirectory.appendingPathComponent(templateFileName)
    }

    static func currentKeyboardLayoutType() -> Int {
        Int(KBGetLayoutType(Int16(LMGetKbdType())))
    }

    static func keyCode(named key: String, keyboardLayoutType: Int? = nil) -> CGKeyCode? {
        registry().keyCode(named: key, keyboardLayoutType: keyboardLayoutType ?? currentKeyboardLayoutType())
    }

    static func modifierFlag(named modifier: String) -> CGEventFlags? {
        registry().modifierFlag(named: modifier)
    }

    static func modifierKeyCode(for flag: CGEventFlags) -> CGKeyCode? {
        registry().modifierKeyCode(for: flag)
    }

    static func mouseInput(named name: String) throws -> AliasMouseInput {
        try registry().mouseInput(named: name)
    }

    static func actionKind(named name: String) throws -> String {
        try registry().actionKind(named: name)
    }

    private static func registry() -> InputAliasRegistry {
        let store = InputAliasRegistryStore()
        do {
            return try store.loadRegistry()
        } catch {
            fputs("Failed to load input aliases from \(store.configURL.path): \(error)\n", stderr)
            return .fallback
        }
    }
}
