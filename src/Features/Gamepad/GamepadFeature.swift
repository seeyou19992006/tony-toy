import Foundation

/// 手柄。
///
/// Home 键走原始 HID 报告（`HomeKeyBridge`），不经过 TCC：
/// 辅助功能、输入监控都不需要授权。
///
/// 包装的是**单例** `HomeKeyBridge.shared`——整个进程只能有一个
/// `IOHIDManager`，不能 new 第二个实例，重复 open 会拿不到设备。
final class GamepadFeature: Feature {
    let id = FeatureID.gamepad
    let title = "手柄"
    let icon = "gamecontroller"

    /// 旧 `MenuStateStore.isGamepadHomeEnabled` 默认 true
    let defaultEnabled = true

    var settings: [SettingItem] {
        [
            .toggle(key: "homeWake", title: "Home 键拉起 MacDeck", defaultValue: true)
        ]
    }

    /// MacDeck 的 bundle id。Home 键统一由 TonyToy 接管，用来切换它的大屏。
    private static let macDeckBundleIdentifier = "com.sunxiaolong.macdeck"

    /// 手柄 Home 是独立输入源，用自己的执行器，不掺进键鼠那几条链路
    /// （整合时 `main.swift` 里的同名实例会删除）。
    private let actionExecutor = AppActionExecutor()

    private let bridge = HomeKeyBridge.shared

    /// Home 键是否负责「没跑就拉起 MacDeck」。关闭后不挂钩回调，
    /// 把 Home 让给 MacDeck 自己（它也在监听原始 HID 报告）。
    private var homeWake = true

    func start() {
        installHomeHandler()
        bridge.start()
    }

    func stop() {
        // 这里**不**调用 `bridge.stop()`：HomeKeyBridge 的注释明确
        // 「关闭后仍继续跟踪按键状态，只是不再回调，避免重新打开时误触发」。
        // stop() 会 unschedule + close IOHIDManager 并清空设备上下文，
        // 功能开关切换时那样做会丢掉已接入设备的按键状态。
        bridge.setEnabled(false)
        bridge.onHomePressed = nil
    }

    /// 按 `homeWake` 重新挂钩 Home 回调。
    ///
    /// `start()` 和 `applyValues()` 都走这里：后者在功能仍启用时执行，
    /// 只改配置不改开关，需要立即换掉回调而不重启监听。
    private func installHomeHandler() {
        bridge.setEnabled(homeWake)
        guard homeWake else {
            bridge.onHomePressed = nil
            return
        }
        bridge.onHomePressed = { [weak self] device in
            self?.actionExecutor.dispatch(
                .ensureApplicationRunning(bundleIdentifier: Self.macDeckBundleIdentifier,
                                          controllerName: device))
        }
    }

    /// 由 `apply(_:)` 在 `start()` 之后调用，此时按开关状态改写回调。
    func applyValues(_ config: FeatureConfig) {
        if case .bool(let value)? = config.values["homeWake"] {
            homeWake = value
        }
        installHomeHandler()
    }
}
