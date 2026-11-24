import AppKit

final class WindowPaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "窗口", icon: "macwindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 按 Feature 的 settings 声明自动生成控件——新增设置项只改
        // Feature，不用动这里。
        if let feature = FeatureRegistry.shared.feature(withID: FeatureID.switcher) {
            buildSettings(for: feature)
        }

    }
}
