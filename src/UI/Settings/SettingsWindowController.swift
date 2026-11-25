import AppKit

/// 配置窗口：左侧侧边栏 + 右侧内容区。
///
/// 用 NSTableView 而不是 NSOutlineView——当前是扁平列表，
/// 将来要分组再加 OutlineView 不迟。
final class SettingsWindowController: NSWindowController {
    /// 侧边栏条目
    struct SidebarItem {
        let id: String
        let title: String
        let icon: String
        let makePane: () -> SettingsPaneViewController
    }

    private let items: [SidebarItem]
    private let sidebarTableView = NSTableView()
    private let contentContainer = NSView()
    private var currentPane: SettingsPaneViewController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TonyToy 设置"
        window.minSize = NSSize(width: 620, height: 440)
        window.center()

        self.init(window: window)
        // 帧自动保存必须设在控制器上：把 window 交给 NSWindowController 时，
        // 之前对 window.setFrameAutosaveName(_:) 设的名字会被清空（实测），
        // 那样窗口位置永远不会被记住。
        windowFrameAutosaveName = "TonyToySettingsWindow"
        setupUI()
    }

    override init(window: NSWindow?) {
        self.items = Self.makeSidebarItems()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    // MARK: - 侧边栏条目

    /// 9 个分区。顺序即侧边栏显示顺序。
    ///
    /// id 必须与 `FeatureID` 常量一致——配置窗口靠它读写对应功能的配置。
    /// general 和 about 不是 Feature（没有配置项），用固定 id。
    private static func makeSidebarItems() -> [SidebarItem] {
        [
            SidebarItem(id: "general", title: "通用", icon: "gearshape") {
                GeneralPaneViewController()
            },
            SidebarItem(id: FeatureID.capsLayer, title: "Caps 键层", icon: "capslock") {
                CapsLayerPaneViewController()
            },
            SidebarItem(id: FeatureID.hotkeyLayer, title: "全局快捷键", icon: "command") {
                HotkeyLayerPaneViewController()
            },
            SidebarItem(id: FeatureID.mouseLayer, title: "鼠标侧键层", icon: "computermouse") {
                MousePaneViewController()
            },
            SidebarItem(id: FeatureID.switcher, title: "窗口切换器", icon: "macwindow") {
                WindowPaneViewController()
            },
            SidebarItem(id: FeatureID.launcher, title: "启动器", icon: "magnifyingglass") {
                LauncherPaneViewController()
            },
            SidebarItem(id: FeatureID.passwordVault, title: "密码管理器", icon: "lock") {
                PasswordPaneViewController()
            },
            SidebarItem(id: FeatureID.gamepad, title: "MacDeck 启动器", icon: "gamecontroller") {
                GamepadPaneViewController()
            },
            SidebarItem(id: "about", title: "关于", icon: "info.circle") {
                AboutPaneViewController()
            },
        ]
    }

    // MARK: - UI

    private func setupUI() {
        guard let window, let contentView = window.contentView else { return }

        // 侧边栏
        let sidebarScroll = NSScrollView()
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true
        sidebarScroll.scrollerStyle = .overlay
        sidebarScroll.drawsBackground = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        // .sourceList 样式会给每一行内容加左右各 16pt 的内边距，NSTableView
        // 会按「列宽 + 32」决定自己的宽度。侧边栏固定 180pt，所以列宽要减掉
        // 这 32pt，表格才正好贴合滚动视图，否则高亮右侧的圆角会被裁掉。
        column.width = 148
        sidebarTableView.addTableColumn(column)
        sidebarTableView.headerView = nil
        sidebarTableView.rowHeight = 32
        sidebarTableView.style = .sourceList
        sidebarTableView.selectionHighlightStyle = .regular
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self
        sidebarScroll.documentView = sidebarTableView

        // 内容容器
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        // NSBox 的 .separator 带 1pt 固有高度。它被上下钉在内容视图上时，
        // 这个固有高度会变成整个内容区的「适配高度」（实测窗口只剩 33pt 高），
        // 所以必须放弃垂直方向的抗拉伸，让它跟着窗口高度撑满。
        separator.setContentHuggingPriority(.defaultLow, for: .vertical)
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(sidebarScroll)
        contentView.addSubview(separator)
        contentView.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            sidebarScroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebarScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebarScroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebarScroll.widthAnchor.constraint(equalToConstant: 180),

            separator.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor),
            separator.topAnchor.constraint(equalTo: contentView.topAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            contentContainer.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        sidebarTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showPane(at: 0)
    }

    private func showPane(at index: Int) {
        guard items.indices.contains(index) else { return }

        // 切换分区时销毁旧 Pane，保证每次进入都是新状态。
        //
        // 这里不能用 addChild/removeFromParent：SettingsWindowController 是
        // NSWindowController（NSResponder 子类），不是 NSViewController，
        // 没有子控制器容器。靠 currentPane 强引用保活即可——Pane 的 view
        // 由 contentContainer 持有，切走时随 removeFromSuperview 释放。
        currentPane?.view.removeFromSuperview()

        let pane = items[index].makePane()
        pane.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(pane.view)

        NSLayoutConstraint.activate([
            pane.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            pane.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            pane.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            pane.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        currentPane = pane
    }
}

// MARK: - 表格数据源

extension SettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let item = items[row]

        let cell = NSTableCellView()

        let imageView = NSImageView()
        // computermouse 是 macOS 12+ 才有的 SF Symbol，最低目标 11 上
        // 会返回 nil（静默空白）。降级到 10.15 就有的 mouse。
        imageView.image =
            NSImage(systemSymbolName: item.icon, accessibilityDescription: item.title)
            ?? NSImage(systemSymbolName: "mouse", accessibilityDescription: item.title)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: item.title)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        showPane(at: sidebarTableView.selectedRow)
    }
}
