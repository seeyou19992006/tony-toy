import AppKit

final class GeneralPaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "通用", icon: "gearshape")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(makeSectionTitle("全局行为"))
        contentStack.addArrangedSubview(
            makePlaceholder("开机自启、主题、菜单栏图标将在第二阶段实现。"))
    }
}
