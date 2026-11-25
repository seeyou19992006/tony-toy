import CoreGraphics
import Foundation

/// Caps Lock 键层。
///
/// 按 Caps 时进入映射层，字母键重映射为方向键等。
final class CapsLayerFeature: Feature {
    let id = FeatureID.capsLayer
    let title = "Caps 键层"
    let icon = "capslock"

    /// 旧 `MenuStateStore` 里 Caps 层默认开启，必须如实声明
    let defaultEnabled = true

    var settings: [SettingItem] {
        [
            .toggle(key: "enabled", title: "启用 Caps 键层", defaultValue: defaultEnabled),
            .toggle(key: "tapToEscape", title: "单按 Caps 触发按键", defaultValue: true),
            .hotkey(
                key: "tapKey",
                title: "单按触发按键",
                defaultValue: HotkeyKeySpec(key: "escape", modifiers: nil)
            ),
            .number(key: "tapTimeoutMs", title: "单按犹豫期 (ms)", defaultValue: 200, range: 50...1000),
            .table(key: "mappings", title: "键位映射"),
        ]
    }

    /// Feature 自己持有控制器实例；`main.swift` 里的同名实例由整合时删除，
    /// 否则会出现两个 event tap 争夺同一批按键。
    private let controller = CapsMapperController()

    func start() {
        if let config = try? ConfigStore.shared.load(),
           let featureConfig = config.features[id] {
            applyTapSettings(from: featureConfig)
        }
        controller.setEnabled(true)
    }

    func stop() { controller.setEnabled(false) }

    /// 映射表或单按配置变更后轻量重载（不拆掉 event tap）。
    func applyValues(_ config: FeatureConfig) {
        applyTapSettings(from: config)
        controller.reload()
    }

    private func applyTapSettings(from config: FeatureConfig) {
        let tapEnabled: Bool
        if case .bool(let value)? = config.values["tapToEscape"] {
            tapEnabled = value
        } else {
            tapEnabled = true
        }

        let timeoutMs: Int
        if case .int(let value)? = config.values["tapTimeoutMs"] {
            timeoutMs = min(max(value, 50), 1000)
        } else {
            timeoutMs = 200
        }

        let keySpec = SettingsPaneViewController.decodeHotkey(config.values["tapKey"])
            ?? HotkeyKeySpec(key: "escape", modifiers: nil)
        let keyCode = KeyConfigSupport.keyCode(named: keySpec.key) ?? 53
        var modifiers: CGEventFlags = []
        for name in keySpec.modifiers ?? [] {
            if let flag = KeyConfigSupport.modifierFlag(named: name) {
                modifiers.insert(flag)
            }
        }

        controller.configureTap(
            enabled: tapEnabled,
            timeoutMs: timeoutMs,
            keyCode: keyCode,
            modifiers: modifiers
        )
    }
}