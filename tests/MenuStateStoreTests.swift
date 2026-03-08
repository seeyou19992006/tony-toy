import Foundation

func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct MenuStateStoreTests {
    static func main() {
        let suiteName = "com.sxl.inputlayers.tests.menu-state"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("Failed to create UserDefaults suite\n", stderr)
            exit(1)
        }

        defaults.removePersistentDomain(forName: suiteName)

        let store = MenuStateStore(defaults: defaults)
        let initial = store.load()
        assertTrue(initial.isVolumeEnabled, "volume should default to enabled")
        assertTrue(initial.isCapsEnabled, "caps should default to enabled")
        assertTrue(initial.isHotkeyEnabled, "hotkey should default to enabled")

        let expected = MenuToggleState(
            isVolumeEnabled: false, isCapsEnabled: true, isHotkeyEnabled: false)
        store.save(expected)

        let reloaded = store.load()
        assertTrue(
            reloaded.isVolumeEnabled == expected.isVolumeEnabled, "volume state should persist")
        assertTrue(reloaded.isCapsEnabled == expected.isCapsEnabled, "caps state should persist")
        assertTrue(
            reloaded.isHotkeyEnabled == expected.isHotkeyEnabled, "hotkey state should persist")

        print("MenuStateStoreTests passed")
    }
}
