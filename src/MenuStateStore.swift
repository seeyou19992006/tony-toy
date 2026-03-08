import Foundation

struct MenuToggleState {
    let isVolumeEnabled: Bool
    let isCapsEnabled: Bool
    let isHotkeyEnabled: Bool

    static let `default` = MenuToggleState(
        isVolumeEnabled: true,
        isCapsEnabled: true,
        isHotkeyEnabled: true
    )
}

final class MenuStateStore {
    private enum Key {
        static let isVolumeEnabled = "menu.isVolumeEnabled"
        static let isCapsEnabled = "menu.isCapsEnabled"
        static let isHotkeyEnabled = "menu.isHotkeyEnabled"
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
            isHotkeyEnabled: defaults.object(forKey: Key.isHotkeyEnabled) as? Bool ?? true
        )
    }

    func save(_ state: MenuToggleState) {
        defaults.set(state.isVolumeEnabled, forKey: Key.isVolumeEnabled)
        defaults.set(state.isCapsEnabled, forKey: Key.isCapsEnabled)
        defaults.set(state.isHotkeyEnabled, forKey: Key.isHotkeyEnabled)
    }
}
