import AppKit

final class LauncherPaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "启动器", icon: "magnifyingglass")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(makeSectionTitle("全局行为"))
        contentStack.addArrangedSubview(
            makePlaceholder("启动器设置将在第二阶段实现。"))
    }
}
