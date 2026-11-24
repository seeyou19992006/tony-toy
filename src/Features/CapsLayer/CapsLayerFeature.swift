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

    /// 映射表变更后需要重新读取配置文件。
    ///
    /// TODO: 依赖协调者为 `CapsMapperController` 增加 `func reload()`。
    /// 当前控制器只在 `private func start()` 内部调用 `configStore.loadMappings()`，
    /// 且 `start()` 会先 `stop()` 拆掉 tap 再重建、重复调用 `hidutil` 重映射——
    /// 直接复用 `setEnabled(true)` 来做重载会带来不必要的 tap 抖动，
    /// 所以这里先留空，等控制器暴露轻量重载入口后再接。
    func applyValues(_ config: FeatureConfig) {
        // 映射表改了要重新加载——配置窗口保存后立即生效，不用重启。
        // `reload()` 是轻量重载（只重读映射），不会拆掉 event tap。
        controller.reload()
    }
}