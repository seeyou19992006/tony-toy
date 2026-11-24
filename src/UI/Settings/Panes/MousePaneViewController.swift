import AppKit

final class MousePaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "鼠标", icon: "computermouse")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(makeSectionTitle("全局行为"))
        contentStack.addArrangedSubview(
            makePlaceholder("鼠标侧键层配置将在第三阶段实现。"))
    }
}
