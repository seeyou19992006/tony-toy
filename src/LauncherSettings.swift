import Carbon.HIToolbox

/// 一个可选的全局热键组合
struct HotkeySpec: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let title: String

    static let presets: [HotkeySpec] = [
        HotkeySpec(keyCode: 2, modifiers: UInt32(optionKey), title: "⌥ D"),
        HotkeySpec(keyCode: 49, modifiers: UInt32(optionKey), title: "⌥ Space"),
        HotkeySpec(keyCode: 49, modifiers: UInt32(controlKey), title: "⌃ Space"),
        HotkeySpec(keyCode: 49, modifiers: UInt32(cmdKey | shiftKey), title: "⌘ ⇧ Space"),
        HotkeySpec(keyCode: 49, modifiers: UInt32(optionKey | cmdKey), title: "⌥ ⌘ Space")
    ]
}

enum LauncherSettings {
    // 存标题而不是下标，增删预设时不会错位
    private static let key = "hotkeyTitle"

    static var selectedHotkeyIndex: Int {
        get {
            if let title = UserDefaults.standard.string(forKey: key),
               let index = HotkeySpec.presets.firstIndex(where: { $0.title == title }) {
                return index
            }
            return 0
        }
        set {
            UserDefaults.standard.set(HotkeySpec.presets[newValue].title, forKey: key)
        }
    }

    static var selectedHotkey: HotkeySpec {
        HotkeySpec.presets[selectedHotkeyIndex]
    }
}
