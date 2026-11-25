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

    /// 映射表变更后轻量重载（不拆掉 event tap）。
    func applyValues(_ config: FeatureConfig) {
        controller.reload()
    }
}