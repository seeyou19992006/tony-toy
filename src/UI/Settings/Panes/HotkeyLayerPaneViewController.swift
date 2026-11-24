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
        contentStack.addArrangedSubview(makeSectionTitle("全局行为"))
        contentStack.addArrangedSubview(
            makePlaceholder("全局快捷键映射表将在第三阶段实现。"))
    }
}
