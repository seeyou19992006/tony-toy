import AppKit

final class CapsLayerPaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "Caps 键层", icon: "capslock")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(makeSectionTitle("全局行为"))
        contentStack.addArrangedSubview(
            makePlaceholder("Caps 层映射表将在第三阶段实现。"))
    }
}
