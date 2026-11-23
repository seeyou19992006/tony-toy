import Foundation

struct MenuToggleState {
    let isVolumeEnabled: Bool
    let isCapsEnabled: Bool
    let isHotkeyEnabled: Bool
    let isCmdTabEnabled: Bool
    let isMouseFollowEnabled: Bool

    static let `default` = MenuToggleState(
        isVolumeEnabled: true,
        isCapsEnabled: true,
        isHotkeyEnabled: true,
        isCmdTabEnabled: false,
        isMouseFollowEnabled: false
    )
}

final class MenuStateStore {
    private enum Key {
        static let isVolumeEnabled = "menu.isVolumeEnabled"
        static let isCapsEnabled = "menu.isCapsEnabled"
        static let isHotkeyEnabled = "menu.isHotkeyEnabled"
        static let isCmdTabEnabled = "menu.isCmdTabEnabled"
        static let isMouseFollowEnabled = "menu.isMouseFollowEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MenuToggleState {
        if defaults.object(forKey: Key.isVolumeEnabled) == nil,
            defaults.object(forKey: Key.isCapsEnabled) == nil,
            defaults.object(forKey: Key.isHotkeyEnabled) == nil
        {
            return .default
        }

        return MenuToggleState(
            isVolumeEnabled: defaults.object(forKey: Key.isVolumeEnabled) as? Bool ?? true,
            isCapsEnabled: defaults.object(forKey: Key.isCapsEnabled) as? Bool ?? true,
            isHotkeyEnabled: defaults.object(forKey: Key.isHotkeyEnabled) as? Bool ?? true,
            isCmdTabEnabled: defaults.object(forKey: Key.isCmdTabEnabled) as? Bool ?? false,
            isMouseFollowEnabled: defaults.object(forKey: Key.isMouseFollowEnabled) as? Bool ?? false
        )
    }

    func save(_ state: MenuToggleState) {
        defaults.set(state.isVolumeEnabled, forKey: Key.isVolumeEnabled)
        defaults.set(state.isCapsEnabled, forKey: Key.isCapsEnabled)
        defaults.set(state.isHotkeyEnabled, forKey: Key.isHotkeyEnabled)
        defaults.set(state.isCmdTabEnabled, forKey: Key.isCmdTabEnabled)
        defaults.set(state.isMouseFollowEnabled, forKey: Key.isMouseFollowEnabled)
    }

    /// 供 Activator 直接读取，避免层层传参
    static var isMouseFollowEnabled: Bool {
        UserDefaults.standard.bool(forKey: "menu.isMouseFollowEnabled")
    }
}
