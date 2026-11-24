import AppKit

/// 配置窗口右侧分区的基类。
///
/// 子类在 `viewDidLoad` 里往 `contentStack` 添加行。
/// 行统一用 `makeRow(title:control:)` 构造，保证全窗口样式一致——
/// 手写布局而不是自动生成，因为自动生成布局在项目这个规模会变成负担
/// （想调个间距都要跟生成器搏斗）。
class SettingsPaneViewController: NSViewController {
    let paneTitle: String
    let paneIcon: String

    /// 纵向内容栈，子类往里加视图
    private(set) lazy var contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    init(title: String, icon: String) {
        self.paneTitle = title
        self.paneIcon = icon
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func loadView() {
        let container = NSView()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // NSScrollView 的 documentView 需要有明确尺寸，
        // 用容器 + 四边约束把 contentStack 撑开，滚动范围才正确。
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)
        scrollView.documentView = documentView

        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // 用 contentView（NSClipView）而不是 scrollView：系统设置「始终显示
            // 滚动条」时 clipView 比 scrollView 窄 17pt，用 scrollView 会让
            // documentView 右侧 17pt 落到滚动条下面，最小窗口时控件被裁。
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])

        view = container
    }

    // MARK: - 行构造

    /// 统一的「左标题 + 右控件」行
    func makeRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        // 不设宽度下限：窗口 minSize 已保证内容区最小 391pt，
        // 硬编码 400 会在最小窗口下把右边距从 24 压到 15。
        return row
    }

    /// 分区标题（用于一页内再分组）
    func makeSectionTitle(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// 占位说明（本阶段各 Pane 都是空的）
    func makePlaceholder(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabelColor
        return label
    }
}
