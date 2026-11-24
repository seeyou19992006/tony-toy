import AppKit

final class GamepadPaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "手柄", icon: "gamecontroller")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(makeSectionTitle("全局行为"))
        contentStack.addArrangedSubview(
            makePlaceholder("手柄 Home 键配置将在第五阶段实现。"))
    }
}
