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
        contentStack.addArrangedSubview(makeSectionTitle("窗口切换与平铺"))
        contentStack.addArrangedSubview(
            makePlaceholder("⌘Tab 接管与窗口平铺配置将在第二阶段实现。"))
    }
}
