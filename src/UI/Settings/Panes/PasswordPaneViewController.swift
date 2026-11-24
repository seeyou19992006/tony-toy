import AppKit

final class PasswordPaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "密码管理器", icon: "lock")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(makeSectionTitle("密码库"))
        contentStack.addArrangedSubview(
            makePlaceholder("密码管理器设置将在第二阶段实现。"))
    }
}
