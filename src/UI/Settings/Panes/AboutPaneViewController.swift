import AppKit

final class AboutPaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "关于", icon: "info.circle")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(makeSectionTitle("版本与诊断"))
        contentStack.addArrangedSubview(
            makePlaceholder("版本信息与诊断工具将在第三阶段实现。"))
    }
}
