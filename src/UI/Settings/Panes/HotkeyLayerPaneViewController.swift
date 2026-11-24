import AppKit

final class HotkeyLayerPaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "全局快捷键", icon: "command")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 按 Feature 的 settings 声明自动生成控件——新增设置项只改
        // Feature，不用动这里。
        if let feature = FeatureRegistry.shared.feature(withID: FeatureID.hotkeyLayer) {
            buildSettings(for: feature)
        }

    }
}
