import Cocoa

/// 居中的搜索面板，回车执行，Esc 或失焦关闭
final class PaletteWindow: NSPanel, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

    private let index: AppIndex
    private let onExecute: (AppEntry) -> Void

    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let background = NSVisualEffectView()
    private let container = NSView()
    private let tintView = AppearanceAwareTintView()

    private var results: [AppEntry] = []
    private var pageSize = 8
    private var showWindowlessApps = true
    private var currentPage = 0
    private var selectedIndex = 0
    private var iconCache: [String: NSImage] = [:]
    private var previousApp: NSRunningApplication?
    private var windowedBundleIDs = Set<String>()
    private var runningBundleIDs = Set<String>()

    private let panelWidth: CGFloat = 720
    private let searchAreaHeight: CGFloat = 64
    private let rowHeight: CGFloat = 66
    private let listBottomPadding: CGFloat = 14

    func configure(pageSize: Int, showWindowlessApps: Bool) {
        self.pageSize = min(max(pageSize, 4), 12)
        self.showWindowlessApps = showWindowlessApps
        if isVisible {
            refresh()
        }
    }

    private let selectionColor = NSColor(srgbRed: 0.13, green: 0.47, blue: 0.55, alpha: 1)

    init(index: AppIndex, onExecute: @escaping (AppEntry) -> Void) {
        self.index = index
        self.onExecute = onExecute
        super.init(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 200),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 失焦即隐藏（Spotlight / Alfred 的行为）。这样不存在
        // 「面板可见但收不到按键」的状态，也就不需要全局 tap 兜底。
        hidesOnDeactivate = true
        // 不要硬编码 appearance——那会覆盖 `NSApp.appearance`，
        // 让设置里的「主题」对启动器/切换器失效。留空即继承应用外观。
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        delegate = self

        buildUI()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - UI

    private func buildUI() {
        // 毛玻璃材质由窗口服务端合成，不响应自身圆角；
        // 用一层 layer-backed 容器做裁剪，否则圆角外会露出矩形底色
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        contentView = container

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.frame = container.bounds
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)

        // 深色着色层：压暗毛玻璃，保证深色主题下的对比度
        tintView.wantsLayer = true
        // 颜色由 `AppearanceAwareTintView.updateLayer` 按当前外观算，
        // 不在这里写死——写死的话切主题只有框架变、遮罩还是旧颜色。
        tintView.autoresizingMask = [.width, .height]
        tintView.frame = background.bounds
        background.addSubview(tintView)

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 30, weight: .regular)
        searchField.textColor = .labelColor
        searchField.placeholderString = "搜索应用"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = true
        searchField.autoresizingMask = [.width, .minYMargin]
        background.addSubview(searchField)

        let separator = NSBox()
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .minYMargin]
        background.addSubview(separator)
        self.separator = separator

        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(executeSelected)
        tableView.intercellSpacing = NSSize(width: 0, height: 0)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.width = panelWidth - 20
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.documentView = tableView
        scrollView.autoresizingMask = [.width]
        background.addSubview(scrollView)
    }

    private var separator: NSBox!

    // MARK: - 显示与关闭

    func show() {
        dbg("show() 被调用")
        previousApp = NSWorkspace.shared.frontmostApplication

        // 调试用：--query 预填搜索词
        if let flag = CommandLine.arguments.firstIndex(of: "--query"),
           flag + 1 < CommandLine.arguments.count {
            searchField.stringValue = CommandLine.arguments[flag + 1]
        } else {
            searchField.stringValue = ""
        }
        refresh()

        // 与密码管理器一致：强制激活，否则 borderless 面板收不到键盘
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)

        // 窗口成为 key 是异步的，必须等下一轮 runloop 再设焦点，否则输入框拿不到键盘事件
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            dbg("active=\(NSApp.isActive) isKey=\(self.isKeyWindow) appKey=\(String(describing: NSApp.keyWindow))")
            let ok = self.makeFirstResponder(self.searchField)
            dbg("makeFirstResponder ok=\(ok) first=\(String(describing: self.firstResponder))")
            if let editor = self.searchField.currentEditor() {
                editor.selectedRange = NSRange(location: (self.searchField.stringValue as NSString).length, length: 0)
            }
        }
        if let editor = searchField.currentEditor() {
            editor.selectedRange = NSRange(location: (searchField.stringValue as NSString).length, length: 0)
        }
    }

    /// 按结果条数调整面板高度，顶部位置保持不动
    private func layoutWindow() {
        guard let screen = targetScreen() else { return }
        let visible = screen.visibleFrame
        let rows = max(1, pageItems.count)
        let listHeight = CGFloat(rows) * rowHeight
        let height = searchAreaHeight + listHeight + listBottomPadding

        let topInset = visible.height * 0.18
        let origin = NSPoint(x: visible.midX - panelWidth / 2,
                             y: visible.maxY - topInset - height)
        setFrame(NSRect(origin: origin, size: NSSize(width: panelWidth, height: height)), display: true)

        // 输入框在搜索区内垂直居中：上下各留 12pt
        searchField.frame = NSRect(x: 24, y: height - searchAreaHeight + 12,
                                   width: panelWidth - 48, height: 40)
        separator.frame = NSRect(x: 16, y: height - searchAreaHeight,
                                 width: panelWidth - 32, height: 1)
        scrollView.frame = NSRect(x: 10, y: listBottomPadding,
                                  width: panelWidth - 20, height: listHeight)
        tableView.frame = NSRect(x: 0, y: 0, width: panelWidth - 20, height: listHeight)
    }

    /// 多显示器下优先弹在前台窗口所在屏幕，其次鼠标所在屏幕
    private func targetScreen() -> NSScreen? {
        if let front = previousApp,
           let frame = frontWindowFrame(pid: front.processIdentifier) {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if let screen = NSScreen.screens.first(where: { screenContains(cgPoint: center, screen: $0) }) {
                return screen
            }
        }

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// 前台应用的第一个可见窗口，CG 坐标（左上原点）
    private func frontWindowFrame(pid: pid_t) -> CGRect? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            let x = (bounds["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (bounds["Y"] as? NSNumber)?.doubleValue ?? 0
            let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            return CGRect(x: x, y: y, width: width, height: height)
        }
        return nil
    }

    /// 把 NSScreen 的左下原点坐标换算成 CG 的左上原点再判断包含
    private func screenContains(cgPoint: CGPoint, screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let frame = CGRect(x: screen.frame.origin.x,
                           y: primary.frame.height - screen.frame.maxY,
                           width: screen.frame.width,
                           height: screen.frame.height)
        return frame.contains(cgPoint)
    }

    /// 关闭面板并把焦点还给之前的应用
    func closePanel() {
        dismiss(restoreFocus: true)
    }

    private func dismiss(restoreFocus: Bool) {
        dbg("dismiss restoreFocus=\(restoreFocus) isVisible=\(isVisible)")
        guard isVisible else { return }
        orderOut(nil)
        if restoreFocus,
           let previous = previousApp,
           previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previous.activate(options: [.activateIgnoringOtherApps])
        }
        previousApp = nil
    }

    /// 应用层兜底：焦点即使不在输入框，Esc 也能关闭面板
    func windowDidResignKey(_ notification: Notification) {
        let front = NSWorkspace.shared.frontmostApplication
        dbg("windowDidResignKey frontmost=\(front?.localizedName ?? "nil") (\(front?.bundleIdentifier ?? "-"))")

        // 延迟判断：瞬时失焦（输入法弹窗、系统提示）不该直接把面板关掉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow else { return }
            dbg("still not key after 0.25s, dismiss")
            self.dismiss(restoreFocus: false)
        }
    }

    // MARK: - 数据

    private var pageItems: [AppEntry] {
        let start = currentPage * pageSize
        let end = min(start + pageSize, results.count)
        guard start < end else { return [] }
        return Array(results[start..<end])
    }

    private func refresh() {
        let raw = searchField.stringValue
        let keyword = raw.trimmingCharacters(in: .whitespaces)

        windowedBundleIDs = Set(WindowedApps.current().map(\.bundleID))
        runningBundleIDs = Set(WindowedApps.running().map(\.bundleID))

        if raw.isEmpty {
            // 空输入：有窗口的在前，后台运行的殿后；关闭「显示无窗口应用」时仅展示有窗口应用
            let defaults = showWindowlessApps
                ? WindowedApps.defaultEntries()
                : WindowedApps.current()
            results = defaults.isEmpty ? index.search("") : defaults
        } else if keyword.isEmpty {
            // 只输入空格：列出所有程序，这是默认窗口列表之外查看全部应用的入口
            results = index.search("")
        } else {
            let searched = index.search(keyword, preferred: windowedBundleIDs)
            if showWindowlessApps {
                results = searched
            } else {
                // 关闭「显示无窗口应用」时，有窗口或未运行的已安装应用仍保留，只过滤掉无窗口后台进程
                let windowlessRunning = runningBundleIDs.subtracting(windowedBundleIDs)
                results = searched.filter { !windowlessRunning.contains($0.bundleID) }
            }
        }
        currentPage = 0
        selectedIndex = 0
        layoutWindow()
        tableView.reloadData()
        guard !results.isEmpty else { return }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        pageItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let items = pageItems
        guard items.indices.contains(row) else { return nil }
        let entry = items[row]
        let identifier = NSUserInterfaceItemIdentifier("ResultCell")

        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ResultCell
            ?? ResultCell(identifier: identifier)
        cell.configure(name: entry.name,
                       path: displayPath(for: entry),
                       icon: icon(for: entry),
                       shortcut: shortcutLabel(for: row),
                       selected: row == tableView.selectedRow,
                       state: runtimeState(for: entry.bundleID))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ResultRowView()
        rowView.selectionColor = selectionColor
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // 选中态变化需要同步刷新右侧提示（↵ 与 ⌘N 互换）
        let selected = tableView.selectedRow
        let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("app"))
        guard column >= 0 else { return }
        let all = IndexSet(integersIn: 0..<results.count)
        tableView.reloadData(forRowIndexes: all, columnIndexes: IndexSet(integer: column))
        if selected >= 0 {
            tableView.scrollRowToVisible(selected)
        }
    }

    private func runtimeState(for bundleID: String) -> AppRuntimeState {
        if windowedBundleIDs.contains(bundleID) { return .runningWithWindow }
        if runningBundleIDs.contains(bundleID) { return .running }
        return .notRunning
    }

    private func displayPath(for entry: AppEntry) -> String {
        let path = entry.url.path
        return path.replacingOccurrences(of: NSString(string: "~").expandingTildeInPath,
                                          with: "~")
    }

    private func shortcutLabel(for row: Int) -> String {
        if row == tableView.selectedRow { return "↵" }
        return "⌘\(row + 1)"
    }

    private func icon(for entry: AppEntry) -> NSImage {
        if let cached = iconCache[entry.bundleID] {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: entry.url.path)
        image.size = NSSize(width: 52, height: 52)
        iconCache[entry.bundleID] = image
        return image
    }

    // MARK: - 键盘

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true

        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true

        case #selector(NSResponder.insertNewline(_:)):
            executeSelected()
            return true

        case #selector(NSResponder.cancelOperation(_:)):
            // Esc：关面板。必须在本地处理——之前靠一个全局 tap 兜底，
            // 那个 tap 是误判「Esc 失效 = 焦点问题」的产物，真因是
            // Caps 层映射残留，跟焦点无关。
            closePanel()
            return true

        // 左右键：光标还能动就让 field editor 自己处理（返回 false），
        // 到两端才翻页。
        case #selector(NSResponder.moveLeft(_:)):
            guard atStartOfInput() else { return false }
            changePage(by: -1)
            return true

        case #selector(NSResponder.moveRight(_:)):
            guard atEndOfInput() else { return false }
            changePage(by: 1)
            return true

        default:
            return false
        }
    }

    /// 面板自己是 first responder 时的 Esc（搜索框有焦点时走上面的 doCommandBy）
    override func cancelOperation(_ sender: Any?) {
        closePanel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            closePanel()
            return
        }
        super.keyDown(with: event)
    }

    /// ⌘1–⌘9 与 Esc：窗口级快捷键处理，不依赖搜索框焦点。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           isVisible {
            closePanel()
            return true
        }
        if event.modifierFlags.contains(.command),
            let chars = event.charactersIgnoringModifiers,
            let digit = Int(chars),
            digit >= 1, digit <= min(9, pageSize), isVisible
        {
            executePageRow(digit - 1)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func atStartOfInput() -> Bool {
        guard let editor = searchField.currentEditor() else { return true }
        let range = editor.selectedRange
        return range.length == 0 && range.location == 0
    }

    private func atEndOfInput() -> Bool {
        guard let editor = searchField.currentEditor() else { return true }
        let range = editor.selectedRange
        let length = (searchField.stringValue as NSString).length
        return range.length == 0 && range.location >= length
    }

    /// 整页切换，选中落到新页第一条
    private func changePage(by delta: Int) {
        guard !results.isEmpty else { return }
        let totalPages = max(1, (results.count + pageSize - 1) / pageSize)
        // 翻页首尾循环：第一页再往前到最后一页，最后一页再往后回第一页
        var target = currentPage + delta
        if target < 0 { target = totalPages - 1 }
        if target >= totalPages { target = 0 }
        guard target != currentPage else { return }
        currentPage = target
        selectedIndex = min(target * pageSize, results.count - 1)
        layoutWindow()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        // 首尾环绕
        var next = selectedIndex + delta
        if next < 0 { next = results.count - 1 }
        if next >= results.count { next = 0 }
        selectedIndex = next

        // 固定翻页：选中项换页时整页切换，而不是平滑滚动
        let targetPage = next / pageSize
        if targetPage != currentPage {
            currentPage = targetPage
            layoutWindow()
            tableView.reloadData()
        }
        tableView.selectRowIndexes(IndexSet(integer: next % pageSize), byExtendingSelection: false)
    }

    /// 页内第几条
    private func executePageRow(_ row: Int) {
        let items = pageItems
        guard items.indices.contains(row) else { return }
        let entry = items[row]
        // 先执行（此时面板仍是 key，跨应用激活才被允许），再关闭
        onExecute(entry)
        dismiss(restoreFocus: false)
    }

    @objc private func executeSelected() {
        executePageRow(tableView.selectedRow)
    }
}

/// 选中行：青绿圆角底色
final class ResultRowView: NSTableRowView {
    var selectionColor: NSColor = .controlAccentColor

    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 6, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        selectionColor.setFill()
        path.fill()
    }

    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

/// 结果行：图标 + 应用名 + 路径 + 快捷键提示
final class ResultCell: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let badge = NSView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        nameLabel.font = .systemFont(ofSize: 16, weight: .regular)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        pathLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(pathLabel)

        shortcutLabel.font = .systemFont(ofSize: 12, weight: .medium)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.alignment = .right
        addSubview(shortcutLabel)

        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.layer?.borderWidth = 2
        badge.layer?.borderColor = NSColor.separatorColor.cgColor
        badge.isHidden = true
        addSubview(badge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        iconView.frame = NSRect(x: 12, y: (height - 52) / 2, width: 52, height: 52)
        nameLabel.frame = NSRect(x: 78, y: height / 2 + 2, width: max(0, bounds.width - 190), height: 20)
        pathLabel.frame = NSRect(x: 78, y: height / 2 - 18, width: max(0, bounds.width - 190), height: 15)
        shortcutLabel.frame = NSRect(x: bounds.width - 90, y: (height - 16) / 2, width: 76, height: 16)
        badge.frame = NSRect(x: iconView.frame.maxX - 17, y: iconView.frame.maxY - 17, width: 16, height: 16)
    }

    func configure(name: String, path: String, icon: NSImage, shortcut: String,
                   selected: Bool, state: AppRuntimeState) {
        nameLabel.stringValue = name
        pathLabel.stringValue = path
        shortcutLabel.stringValue = shortcut
        iconView.image = icon
        // 选中行是深青色高亮，文字必须转白——否则深色文字压在深青上看不清
        nameLabel.textColor = selected ? .white : .labelColor
        pathLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
        shortcutLabel.textColor =
            selected ? NSColor.white.withAlphaComponent(0.7) : .tertiaryLabelColor

        // 图标右上角：绿点=有窗口，灰点=后台运行，无点=未运行
        switch state {
        case .runningWithWindow:
            badge.isHidden = false
            badge.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case .running:
            badge.isHidden = false
            badge.layer?.backgroundColor = NSColor(white: 0.62, alpha: 1).cgColor
        case .notRunning:
            badge.isHidden = true
        }
        needsLayout = true
    }
}
