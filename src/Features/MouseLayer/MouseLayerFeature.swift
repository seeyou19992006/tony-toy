import Foundation

/// 鼠标侧键层。
///
/// 按住/点击激活键后，侧键与滚轮被映射为音量、调度中心等动作。
final class MouseLayerFeature: Feature {
    let id = FeatureID.mouseLayer
    let title = "鼠标"
    /// macOS 12+ 才有的 SF Symbol，配置窗口侧边栏有两级降级（见 SettingsWindowController）
    let icon = "computermouse"

    /// 旧 `MenuStateStore.isVolumeEnabled` 默认开启，必须如实声明
    let defaultEnabled = true

    var settings: [SettingItem] {
        [
            .toggle(key: "enabled", title: "启用鼠标侧键层", defaultValue: defaultEnabled),
            .table(key: "mappings", title: "侧键映射"),
            .picker(
                key: "activationButton",
                title: "激活键",
                options: [
                    (value: "button3", label: "侧键 3"),
                    (value: "button4", label: "侧键 4"),
                    (value: "button5", label: "侧键 5"),
                    (value: "button6", label: "侧键 6"),
                    (value: "button7", label: "侧键 7"),
                    (value: "button8", label: "侧键 8"),
                ],
                defaultValue: "button5"
            ),
        ]
    }

    /// Feature 自己持有控制器实例；`main.swift` 里的同名实例由整合时删除，
    /// 否则会出现两个 event tap 争夺同一批鼠标事件。
    private let controller = MouseLayerController()

    /// 音量变化回调（转发给控制器）。
    ///
    /// 菜单栏要显示实时音量，需要订阅这个。Feature 是控制器的唯一持有者，
    /// 所以由它对外暴露——main.swift 不再直接摸 controller。
    var onVolumeChanged: ((Float32) -> Void)? {
        get { controller.onVolumeChanged }
        set { controller.onVolumeChanged = newValue }
    }

    func start() { controller.setEnabled(true) }
    func stop() { controller.setEnabled(false) }

    /// 激活键 / 映射表变更后需要控制器重新解析配置。
    ///
    /// TODO: 依赖协调者为 `MouseLayerController` 增加应用配置的入口。
    /// 现状：`reloadLayerConfig()` 是 private，唯一公开的 `setEnabled(_:)`
    /// 只能整条重启 tap，且重载来源是独立的 `mouse-layer.json`，
    /// 不读 `FeatureConfig.values`。所以这里先留空，等控制器暴露
    /// `func applyConfig(_ config: MouseLayerResolvedConfig)`（或 `reload()`）后再接。
    func applyValues(_ config: FeatureConfig) {
        // 映射表改了要重新加载——配置窗口保存后立即生效，不用重启。
        // `reload()` 是轻量重载（只重读映射），不会拆掉 event tap。
        controller.reload()
    }
}
