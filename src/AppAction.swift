import Foundation
import Cocoa

struct AppActionSpec: Codable {
    let action: String?
    let key: String?
    let modifiers: [String]?
    let bundleIdentifier: String?
    let horizontalOffset: Double?
    let verticalOffset: Double?
    let alreadyActiveBehavior: String?
    let direction: String?

    init(
        action: String?,
        key: String?,
        modifiers: [String]?,
        bundleIdentifier: String?,
        horizontalOffset: Double? = nil,
        verticalOffset: Double? = nil,
        alreadyActiveBehavior: String? = nil,
        direction: String? = nil
    ) {
        self.action = action
        self.key = key
        self.modifiers = modifiers
        self.bundleIdentifier = bundleIdentifier
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
        self.alreadyActiveBehavior = alreadyActiveBehavior
        self.direction = direction
    }

    enum CodingKeys: String, CodingKey {
        case action
        case key
        case modifiers
        case bundleIdentifier = "bundle_identifier"
        case horizontalOffset = "horizontal_offset"
        case verticalOffset = "vertical_offset"
        case alreadyActiveBehavior = "already_active_behavior"
        case direction
    }
}

enum ActivateApplicationAlreadyActiveBehavior: String, Equatable {
    case activate
    case switchToLast = "switch_to_last"
}

enum DisplayDirection: String, Equatable {
    case left
    case right
    case up
    case down
}

enum AppAction: Equatable {
    case sendHotkey(keyCode: CGKeyCode, modifiers: CGEventFlags)
    case missionControl
    case activateApplication(bundleIdentifier: String, alreadyActiveBehavior: ActivateApplicationAlreadyActiveBehavior)
    case moveWindowToAdjacentDisplay(direction: DisplayDirection)
    case maximizeWindow
}

enum AppActionError: Error, CustomStringConvertible {
    case missingKey
    case missingBundleIdentifier
    case missingDirection
    case unknownAction(String)
    case unknownKey(String)
    case unknownModifier(String)
    case unknownDirection(String)

    var description: String {
        switch self {
        case .missingKey:
            return "Missing key for send_hotkey action"
        case .missingBundleIdentifier:
            return "Missing bundle_identifier for activate_application action"
        case .missingDirection:
            return "Missing direction for move_window_to_adjacent_display action"
        case .unknownAction(let action):
            return "Unknown action: \(action)"
        case .unknownKey(let key):
            return "Unknown key: \(key)"
        case .unknownModifier(let modifier):
            return "Unknown modifier: \(modifier)"
        case .unknownDirection(let direction):
            return "Unknown direction: \(direction)"
        }
    }
}

enum AppActionResolver {
    static func resolve(_ spec: AppActionSpec) throws -> AppAction {
        let resolvedAction = try resolveActionName(spec)
        switch resolvedAction {
        case "send_hotkey":
            guard let keyName = spec.key else {
                throw AppActionError.missingKey
            }
            guard let keyCode = KeyConfigSupport.keyCode(named: keyName) else {
                throw AppActionError.unknownKey(keyName)
            }
            let modifiers = try (spec.modifiers ?? []).reduce(into: CGEventFlags()) { result, modifier in
                guard let flag = KeyConfigSupport.modifierFlag(named: modifier) else {
                    throw AppActionError.unknownModifier(modifier)
                }
                result.insert(flag)
            }
            return .sendHotkey(keyCode: keyCode, modifiers: modifiers)
        case "mission_control":
            return .missionControl
        case "activate_application":
            guard let bundleIdentifier = spec.bundleIdentifier else {
                throw AppActionError.missingBundleIdentifier
            }
            let behavior = ActivateApplicationAlreadyActiveBehavior(
                rawValue: spec.alreadyActiveBehavior ?? ActivateApplicationAlreadyActiveBehavior.activate.rawValue
            ) ?? .activate
            return .activateApplication(bundleIdentifier: bundleIdentifier, alreadyActiveBehavior: behavior)
        case "move_window_to_adjacent_display":
            guard let direction = spec.direction else {
                throw AppActionError.missingDirection
            }
            guard let resolvedDirection = DisplayDirection(rawValue: direction) else {
                throw AppActionError.unknownDirection(direction)
            }
            return .moveWindowToAdjacentDisplay(direction: resolvedDirection)
        case "maximize_window":
            return .maximizeWindow
        default:
            throw AppActionError.unknownAction(resolvedAction)
        }
    }

    private static func resolveActionName(_ spec: AppActionSpec) throws -> String {
        if let actionName = spec.action {
            return try KeyConfigSupport.actionKind(named: actionName)
        }
        if spec.key != nil {
            return "send_hotkey"
        }
        throw AppActionError.unknownAction("<missing>")
    }
}
