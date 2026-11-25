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
            .table(key: "mappings", title: "键位映射"),
        ]
    }

    /// Feature 自己持有控制器实例；`main.swift` 里的同名实例由整合时删除，
    /// 否则会出现两个 event tap 争夺同一批按键。
    private let controller = CapsMapperController()

    func start() { controller.setEnabled(true) }
    func stop() { controller.setEnabled(false) }

    /// 映射表变更后轻量重载（不拆掉 event tap）。
    func applyValues(_ config: FeatureConfig) {
        controller.reload()
    }
}