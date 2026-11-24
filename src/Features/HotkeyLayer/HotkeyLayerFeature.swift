import Foundation

/// 全局快捷键层。
///
/// 拦截修饰键组合，把按键映射为动作（启动 App、执行命令等）。
final class HotkeyLayerFeature: Feature {
    let id = FeatureID.hotkeyLayer
    let title = "全局快捷键"
    let icon = "command"

    /// 旧 `MenuStateStore` 里全局快捷键默认开启，必须如实声明
    let defaultEnabled = true

    var settings: [SettingItem] {
        [
            .toggle(key: "enabled", title: "启用全局快捷键", defaultValue: defaultEnabled),
            .table(key: "mappings", title: "键位映射"),
        ]
    }

    /// Feature 自己持有控制器实例；`main.swift` 里的同名实例由整合时删除，
    /// 否则会出现两个 event tap 争夺同一批按键。
    private let controller = HotkeyMapperController()

    func start() { controller.setEnabled(true) }
    func stop() { controller.setEnabled(false) }

    /// 映射表变更后需要重新读取配置文件。
    ///
    /// TODO: 依赖协调者为 `HotkeyMapperController` 增加 `func reload()`。
    /// 当前控制器只在 `private func start()` 内部调用 `configStore.loadMappings()`，
    /// 且 `start()` 会先 `stop()` 拆掉 tap 再重建——直接复用 `setEnabled(true)`
    /// 来做重载会带来不必要的 tap 抖动，所以这里先留空，
    /// 等控制器暴露轻量重载入口后再接。
    func applyValues(_ config: FeatureConfig) {}
}