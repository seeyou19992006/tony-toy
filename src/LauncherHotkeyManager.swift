import Carbon.HIToolbox
import Cocoa

/// 启动器的全局热键。
///
/// 实际的注册/分发逻辑在 `CarbonHotkey` 里——这里只负责把
/// `HotkeySpec`（键码 + Carbon 修饰键掩码）转过去。
/// Carbon 热键不依赖辅助功能权限，也不抢按键。
final class LauncherHotkeyManager {
    private var hotkey = CarbonHotkey(
        name: "启动器", signature: OSType.fourCharCode("TnyL"))

    deinit {
        unregister()
    }

    @discardableResult
    func register(_ spec: HotkeySpec, onTrigger: @escaping () -> Void) -> Bool {
        hotkey.onTrigger = onTrigger
        return hotkey.register(keyCode: spec.keyCode, modifiers: spec.modifiers)
    }

    func unregister() {
        hotkey.unregister()
        hotkey.onTrigger = nil
    }
}
