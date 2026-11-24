import AppKit

/// 映射表编辑器。
///
/// 三种映射表结构不同（Caps 层来源是单字符、全局快捷键来源是组合键、
/// 鼠标层来源是侧键），用 `MappingTableStyle` 区分。
///
/// 表格里的两列都是只读展示，编辑统一走「＋」弹出的表单——
/// 就地编辑要在一个单元格里塞下组合键录制器/动作参数，反而更难用。
final class MappingTableEditor: NSView {
    enum Style: Equatable {
        /// from 单字符 → to 目标键
        case capsLayer
        /// from 组合键 → to 目标键/动作
        case hotkeyLayer
        /// from 鼠标输入 → to 动作
        case mouseLayer
    }

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        setupUI()
        reloadRows()
    }

    /// 便捷构造：直接喂 config 里的映射数组与变更回调
    convenience init(
        style: Style,
        mappings: [JSONValue],
        onChange: (([JSONValue]) -> Void)? = nil
    ) {
        self.init(style: style)
        self.mappings = mappings
        self.onChange = onChange
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    /// 当前映射（JSONValue 数组，直接对应 config 里的 `values["mappings"]`）
    var mappings: [JSONValue] {
        get { rawMappings }
        set {
            rawMappings = newValue
            reloadRows()
        }
    }

    /// 变更回调（新增 / 删除 / 编辑后触发）
    var onChange: (([JSONValue]) -> Void)?

    /// 当前映射的 JSON 形态（写回 `values["mappings"]` 用）
    var jsonValue: JSONValue { .array(rawMappings) }

    /// 从 `values["mappings"]` 取值：不是数组（未配置/类型错误）时返回空数组
    static func mappings(from value: JSONValue?) -> [JSONValue] {
        if case .array(let list)? = value { return list }
        return []
    }

    private let style: Style
    private var rawMappings: [JSONValue] = []
    private var rows: [Row] = []

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "还没有映射，点 ＋ 添加")

    // MARK: - 行模型

    private struct Row {
        let raw: JSONValue
        let sourceText: String
        let targetText: String
        let sourceValid: Bool
        let targetValid: Bool
        /// 冲突检测用的规范化来源（空串表示解析不出来，不参与冲突）
        let conflictKey: String
    }

    // MARK: - UI

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 26
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.doubleAction = #selector(editSelectedRow)

        let sourceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        sourceColumn.title = "来源"
        sourceColumn.width = 150
        sourceColumn.minWidth = 100
        let targetColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("target"))
        targetColumn.title = "目标"
        targetColumn.width = 220
        targetColumn.minWidth = 120
        tableView.addTableColumn(sourceColumn)
        tableView.addTableColumn(targetColumn)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        addButton.title = "＋"
        addButton.bezelStyle = .smallSquare
        addButton.setButtonType(.momentaryPushIn)
        addButton.font = .systemFont(ofSize: 13, weight: .semibold)
        addButton.target = self
        addButton.action = #selector(addTapped)
        addButton.toolTip = "添加映射"

        removeButton.title = "－"
        removeButton.bezelStyle = .smallSquare
        removeButton.setButtonType(.momentaryPushIn)
        removeButton.font = .systemFont(ofSize: 13, weight: .semibold)
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.toolTip = "删除选中的映射"

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [addButton, removeButton, footerSpacer])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 6
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footer)

        let hint = NSTextField(labelWithString: "双击一行可编辑")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)

        addButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        removeButton.widthAnchor.constraint(equalToConstant: 30).isActive = true

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 12),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -12),

            footer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),

            hint.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 380, height: 240)
    }

    // MARK: - 数据

    private func reloadRows() {
        rows = rawMappings.map(parseRow)
        emptyLabel.isHidden = !rows.isEmpty
        removeButton.isEnabled = !rows.isEmpty
        tableView.reloadData()
    }

    private func commit(_ newMappings: [JSONValue]) {
        rawMappings = newMappings
        reloadRows()
        onChange?(rawMappings)
    }

    private func parseRow(_ value: JSONValue) -> Row {
        var sourceText = "（缺少来源）"
        var sourceValid = false
        var conflictKey = ""

        switch style {
        case .capsLayer:
            if let from = value.string("from"), !from.isEmpty {
                sourceText = HotkeyDisplay.displayName(forKey: from)
                sourceValid = KeyConfigSupport.keyCode(named: from) != nil
                conflictKey = "caps:" + from.lowercased()
            }
        case .hotkeyLayer:
            if let from = value.object("from"), let spec = Self.spec(from: from) {
                sourceText = HotkeyDisplay.displayName(for: spec)
                sourceValid = KeyConfigSupport.keyCode(named: spec.key) != nil
                conflictKey = "hotkey:" + spec.key.lowercased() + "|" + Self.canonicalModifiers(spec.modifiers)
            }
        case .mouseLayer:
            if let from = value.object("from"), let input = from["input"]?.stringValue {
                sourceText = HotkeyDisplay.mouseInputTitle(input)
                sourceValid = (try? KeyConfigSupport.mouseInput(named: input)) != nil
                conflictKey = "mouse:" + input.lowercased()
            }
        }

        let target = describeTarget(value.object("to"))
        return Row(
            raw: value,
            sourceText: sourceText,
            targetText: target.text,
            sourceValid: sourceValid,
            targetValid: target.valid,
            conflictKey: conflictKey
        )
    }

    /// 目标侧展示文案 + 是否能解析。解析失败的行整行文字标红。
    private func describeTarget(_ value: [String: JSONValue]?) -> (text: String, valid: Bool) {
        guard let dict = value else {
            return ("（缺少目标）", false)
        }

        if let action = dict["action"]?.stringValue {
            switch action {
            case "send_hotkey":
                guard let spec = Self.spec(from: dict) else {
                    return ("发送快捷键（缺少按键）", false)
                }
                return ("发送 " + HotkeyDisplay.displayName(for: spec), true)
            case "activate_application":
                guard let bundle = dict["bundle_identifier"]?.stringValue, !bundle.isEmpty else {
                    return ("激活应用（缺少 Bundle ID）", false)
                }
                let switchBack = dict["already_active_behavior"]?.stringValue == "switch_to_last"
                return (switchBack ? "切到上一个 / " + bundle : "激活 " + bundle, true)
            case "move_window_to_adjacent_display":
                guard let direction = dict["direction"]?.stringValue,
                      let label = Self.directionTitles[direction] else {
                    return ("移到相邻屏幕（方向无效）", false)
                }
                return ("移到\(label)侧屏幕", true)
            case "maximize_window":
                return ("最大化窗口", true)
            case "mission_control":
                return ("调度中心", true)
            case "volume_scroll":
                return ("音量滚动", true)
            case "launch_application", "toggle_application":
                guard let bundle = dict["bundle_identifier"]?.stringValue, !bundle.isEmpty else {
                    return ("启动应用（缺少 Bundle ID）", false)
                }
                return ("启动 " + bundle, true)
            default:
                return (action, false)
            }
        }

        // Caps/热键的旧格式：to 直接是 {key, modifiers}，等价 send_hotkey
        if let spec = Self.spec(from: dict) {
            return ("发送 " + HotkeyDisplay.displayName(for: spec), true)
        }
        return ("（无法识别）", false)
    }

    // MARK: - 按钮动作

    @objc private func addTapped() {
        presentEditor(existing: nil, rowIndex: nil)
    }

    @objc private func removeTapped() {
        let index = tableView.selectedRow
        guard index >= 0, index < rawMappings.count else { return }
        var newMappings = rawMappings
        newMappings.remove(at: index)
        commit(newMappings)
    }

    @objc private func editSelectedRow() {
        let index = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard index >= 0, index < rawMappings.count else { return }
        presentEditor(existing: rawMappings[index], rowIndex: index)
    }

    // MARK: - 编辑表单

    private func presentEditor(existing: JSONValue?, rowIndex: Int?) {
        let form = MappingEntryForm(style: style, existing: existing, isMouseLayer: style == .mouseLayer)

        while true {
            let alert = NSAlert()
            alert.messageText = existing == nil ? "添加映射" : "编辑映射"
            alert.informativeText = form.informativeText
            alert.addButton(withTitle: "确定")
            let cancelButton = alert.addButton(withTitle: "取消")
            alert.accessoryView = form.container

            // NSAlert 会把 Esc 自动绑到「取消」按钮，按 ⌘Esc 时弹窗直接被关掉，
            // 录制器根本收不到（⌘A 不受影响，所以只有 Esc 录不进去）。
            // 录制期间临时解绑 Esc，让它进到录制器；结束录制后恢复。
            let cancelKeyEquivalent = cancelButton.keyEquivalent
            HotkeyRecorder.onRecordingChanged = { [weak cancelButton] isRecording in
                cancelButton?.keyEquivalent = isRecording ? "" : cancelKeyEquivalent
            }
            defer {
                HotkeyRecorder.onRecordingChanged = nil
                cancelButton.keyEquivalent = cancelKeyEquivalent
            }

            guard alert.runModal() == .alertFirstButtonReturn else { return }

            if let message = form.validationMessage() {
                form.statusLabel.stringValue = message
                continue
            }
            guard let mapping = form.makeMapping(base: existing) else { return }

            // 冲突检测：来源已存在时响一声并高亮那一行，不写入
            let conflictKey = form.conflictKey
            if !conflictKey.isEmpty,
               let conflictIndex = rows.firstIndex(where: {
                   $0.conflictKey == conflictKey && $0.conflictKey != ""
               }),
               conflictIndex != rowIndex {
                NSSound.beep()
                highlight(row: conflictIndex)
                return
            }

            var newMappings = rawMappings
            if let rowIndex, rowIndex < newMappings.count {
                newMappings[rowIndex] = mapping
            } else {
                newMappings.append(mapping)
            }
            commit(newMappings)
            return
        }
    }

    private func highlight(row index: Int) {
        guard index >= 0, index < rows.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        guard let rowView = tableView.rowView(atRow: index, makeIfNecessary: true) else { return }
        rowView.backgroundColor = NSColor.systemRed.withAlphaComponent(0.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak rowView] in
            rowView?.backgroundColor = .clear
        }
    }

    // MARK: - 解析工具

    fileprivate static let directionTitles: [String: String] = [
        "left": "左", "right": "右", "up": "上", "down": "下",
    ]

    fileprivate static let directionOrder = ["left", "right", "up", "down"]

    fileprivate static func spec(from dict: [String: JSONValue]) -> HotkeyKeySpec? {
        guard let key = dict["key"]?.stringValue, !key.isEmpty else { return nil }
        let modifiers = dict["modifiers"]?.arrayValue?.compactMap(\.stringValue)
        return HotkeyKeySpec(key: key, modifiers: modifiers)
    }

    fileprivate static func canonicalModifiers(_ modifiers: [String]?) -> String {
        guard let modifiers else { return "" }
        let names = Set(modifiers.compactMap(HotkeyDisplay.canonicalModifier))
        return HotkeyDisplay.modifierOrder.filter { names.contains($0) }.joined(separator: ",")
    }
}

// MARK: - 表格数据源

extension MappingTableEditor: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier, row < rows.count else { return nil }
        let entry = rows[row]
        let isSource = identifier.rawValue == "source"

        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = makeCell(identifier: identifier)
        }

        cell.textField?.stringValue = isSource ? entry.sourceText : entry.targetText
        cell.textField?.textColor = (isSource ? entry.sourceValid : entry.targetValid)
            ? .labelColor
            : .systemRed
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.font = .systemFont(ofSize: 12)
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

// MARK: - JSONValue 取值便捷

extension JSONValue {
    fileprivate var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    fileprivate var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    fileprivate var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

// MARK: - 编辑表单

/// 「＋ / 双击」弹出的编辑表单：来源 + 目标 + 参数。
///
/// 用 NSAlert 的 accessoryView 承载，参数区固定高度换内容，
/// 避免切换动作类型时 alert 尺寸跳动。
private final class MappingEntryForm: NSObject, NSTextFieldDelegate {
    let container = NSView()
    let statusLabel = NSTextField(labelWithString: "")

    let informativeText: String

    private let style: MappingTableEditor.Style
    private let stack = NSStackView()
    private let paramHolder = NSStackView()

    private let charField = NSTextField()
    private let sourceRecorder = HotkeyRecorder(frame: .zero)
    private let sourcePopup = NSPopUpButton()
    private let targetPopup = NSPopUpButton()
    private let keyRecorder = HotkeyRecorder(frame: .zero)
    private let bundleField = NSTextField()
    private let directionPopup = NSPopUpButton()
    private let paramHint = NSTextField(labelWithString: "该动作无需参数")

    private var targetKinds: [TargetKind] = []
    private var initialTargetValue: JSONValue?
    private var initialTargetKindUnrecognized = false
    private var targetPopupChanged = false

    /// 规范化来源，用于冲突检测
    private(set) var conflictKey = ""

    init(style: MappingTableEditor.Style, existing: JSONValue?, isMouseLayer: Bool) {
        self.style = style
        self.informativeText = isMouseLayer
            ? "来源是鼠标输入（滚轮 / 侧键），目标是动作。"
            : "来源是按键（可带修饰键），目标是按键或动作。"
        super.init()

        targetKinds = TargetKind.allCases.filter { kind in
            kind != .volumeScroll || isMouseLayer
        }

        setupUI()
        if let existing {
            prefill(existing)
        }
        updateParamArea()
    }

    // MARK: UI

    private func setupUI() {
        charField.placeholderString = "单个字符，如 e"
        charField.delegate = self
        charField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        charField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        charField.target = self
        charField.action = #selector(textFieldChanged)

        sourceRecorder.widthAnchor.constraint(equalToConstant: 250).isActive = true
        sourceRecorder.onChange = { [weak self] _ in
            self?.updateConflictKey()
        }

        for option in HotkeyDisplay.mouseInputOptions() {
            sourcePopup.addItem(withTitle: option.title)
            sourcePopup.lastItem?.representedObject = option.name
        }
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged)
        sourcePopup.widthAnchor.constraint(equalToConstant: 250).isActive = true

        for kind in targetKinds {
            targetPopup.addItem(withTitle: kind.title)
        }
        targetPopup.target = self
        targetPopup.action = #selector(targetChanged)
        targetPopup.widthAnchor.constraint(equalToConstant: 250).isActive = true

        keyRecorder.widthAnchor.constraint(equalToConstant: 250).isActive = true

        bundleField.placeholderString = "例如 com.apple.Safari"
        bundleField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        bundleField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        bundleField.delegate = self

        for direction in MappingTableEditor.directionOrder {
            let title = MappingTableEditor.directionTitles[direction] ?? direction
            directionPopup.addItem(withTitle: title)
            directionPopup.lastItem?.representedObject = direction
        }
        directionPopup.selectItem(at: 0)
        directionPopup.widthAnchor.constraint(equalToConstant: 250).isActive = true

        paramHolder.orientation = .horizontal
        paramHolder.alignment = .centerY
        paramHolder.spacing = 0
        paramHolder.heightAnchor.constraint(equalToConstant: 26).isActive = true
        paramHolder.widthAnchor.constraint(equalToConstant: 250).isActive = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.stringValue = ""
        statusLabel.heightAnchor.constraint(equalToConstant: 16).isActive = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let sourceRow = makeRow("来源", control: sourceControl)
        let targetRow = makeRow("目标", control: targetPopup)
        let paramRow = makeRow("参数", control: paramHolder)

        stack.addArrangedSubview(sourceRow)
        stack.addArrangedSubview(targetRow)
        stack.addArrangedSubview(paramRow)
        stack.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            container.widthAnchor.constraint(equalToConstant: 360),
        ])

        // NSAlert 只认 accessoryView 的 frame，不用 Auto Layout 撑尺寸
        let fitting = container.fittingSize
        container.translatesAutoresizingMaskIntoConstraints = true
        container.frame = NSRect(origin: .zero, size: NSSize(width: 360, height: fitting.height))
    }

    private var sourceControl: NSView {
        switch style {
        case .capsLayer: return charField
        case .hotkeyLayer: return sourceRecorder
        case .mouseLayer: return sourcePopup
        }
    }

    private func makeRow(_ title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    // MARK: 预填

    private func prefill(_ existing: JSONValue) {
        switch style {
        case .capsLayer:
            charField.stringValue = existing.string("from") ?? ""
        case .hotkeyLayer:
            if let from = existing.object("from"), let spec = MappingTableEditor.spec(from: from) {
                sourceRecorder.spec = spec
            }
        case .mouseLayer:
            if let input = existing.object("from")?["input"]?.stringValue {
                selectMouseInput(input)
            }
        }

        guard let target = existing.object("to") else {
            updateConflictKey()
            return
        }
        initialTargetValue = .object(target)

        if let kind = TargetKind(target: target) {
            selectTargetKind(kind)
            if let spec = MappingTableEditor.spec(from: target) {
                keyRecorder.spec = spec
            }
            bundleField.stringValue = target["bundle_identifier"]?.stringValue ?? ""
            if let direction = target["direction"]?.stringValue {
                selectDirection(direction)
            }
        } else {
            initialTargetKindUnrecognized = true
        }
        updateConflictKey()
    }

    private func selectMouseInput(_ name: String) {
        for index in 0..<sourcePopup.numberOfItems {
            if (sourcePopup.item(at: index)?.representedObject as? String)?.lowercased() == name.lowercased() {
                sourcePopup.selectItem(at: index)
                return
            }
        }
    }

    private func selectTargetKind(_ kind: TargetKind) {
        guard let index = targetKinds.firstIndex(of: kind) else { return }
        targetPopup.selectItem(at: index)
    }

    private func selectDirection(_ direction: String) {
        for index in 0..<directionPopup.numberOfItems {
            if (directionPopup.item(at: index)?.representedObject as? String) == direction {
                directionPopup.selectItem(at: index)
                return
            }
        }
    }

    // MARK: 交互

    @objc private func textFieldChanged() {
        updateConflictKey()
    }

    @objc private func sourceChanged() {
        updateConflictKey()
    }

    @objc private func targetChanged() {
        targetPopupChanged = true
        updateParamArea()
    }

    func controlTextDidChange(_ obj: Notification) {
        updateConflictKey()
    }

    private var selectedTargetKind: TargetKind {
        let index = targetPopup.indexOfSelectedItem
        guard index >= 0, index < targetKinds.count else { return .sendHotkey }
        return targetKinds[index]
    }

    private func updateParamArea() {
        for view in paramHolder.arrangedSubviews {
            paramHolder.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let control: NSView
        switch selectedTargetKind {
        case .sendHotkey:
            control = keyRecorder
        case .activateApplication, .activateAndSwitchBack:
            control = bundleField
        case .moveToAdjacentDisplay:
            control = directionPopup
        case .maximizeWindow, .missionControl, .volumeScroll:
            control = paramHint
        }
        paramHolder.addArrangedSubview(control)
    }

    private func updateConflictKey() {
        var key = ""
        switch style {
        case .capsLayer:
            let text = charField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { key = "caps:" + text.lowercased() }
        case .hotkeyLayer:
            if let spec = sourceRecorder.spec {
                key = "hotkey:" + spec.key.lowercased() + "|"
                    + MappingTableEditor.canonicalModifiers(spec.modifiers)
            }
        case .mouseLayer:
            if let name = sourcePopup.selectedItem?.representedObject as? String {
                key = "mouse:" + name.lowercased()
            }
        }
        conflictKey = key
    }

    // MARK: 校验与产出

    func validationMessage() -> String? {
        switch style {
        case .capsLayer:
            let text = charField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return "请输入来源按键" }
            if KeyConfigSupport.keyCode(named: text) == nil {
                return "无法识别的按键：\(text)（用单个字符，如 e / 1 / [）"
            }
        case .hotkeyLayer:
            if sourceRecorder.spec == nil { return "请录制来源组合键" }
        case .mouseLayer:
            if sourcePopup.selectedItem == nil { return "请选择鼠标输入" }
        }

        switch selectedTargetKind {
        case .sendHotkey:
            if keyRecorder.spec == nil { return "请录制目标快捷键" }
        case .activateApplication, .activateAndSwitchBack:
            if bundleField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                return "请输入应用的 Bundle ID"
            }
        default:
            break
        }
        return nil
    }

    func makeMapping(base: JSONValue?) -> JSONValue? {
        var dict: [String: JSONValue] = [:]
        if let base, case .object(let existing) = base {
            dict = existing
        }

        switch style {
        case .capsLayer:
            dict["from"] = .string(charField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        case .hotkeyLayer:
            guard let spec = sourceRecorder.spec else { return nil }
            var from: [String: JSONValue] = ["key": .string(spec.key)]
            if let modifiers = spec.modifiers, !modifiers.isEmpty {
                from["modifiers"] = .array(modifiers.map(JSONValue.string))
            }
            dict["from"] = .object(from)
        case .mouseLayer:
            guard let name = sourcePopup.selectedItem?.representedObject as? String else { return nil }
            dict["from"] = .object(["input": .string(name)])
        }

        // 无法识别的旧动作：用户没动目标下拉时原样保留，别在手滑编辑里丢配置
        if initialTargetKindUnrecognized, !targetPopupChanged, let initialTargetValue {
            dict["to"] = initialTargetValue
        } else {
            dict["to"] = makeTarget()
        }
        return .object(dict)
    }

    private func makeTarget() -> JSONValue {
        switch selectedTargetKind {
        case .sendHotkey:
            guard let spec = keyRecorder.spec else { return .object([:]) }
            var target: [String: JSONValue] = ["key": .string(spec.key)]
            if let modifiers = spec.modifiers, !modifiers.isEmpty {
                target["modifiers"] = .array(modifiers.map(JSONValue.string))
            }
            return .object(target)

        case .activateApplication, .activateAndSwitchBack:
            var target: [String: JSONValue] = [
                "action": .string("activate_application"),
                "bundle_identifier": .string(bundleField.stringValue.trimmingCharacters(in: .whitespaces)),
            ]
            if selectedTargetKind == .activateAndSwitchBack {
                target["already_active_behavior"] = .string("switch_to_last")
            }
            return .object(target)

        case .moveToAdjacentDisplay:
            let direction = directionPopup.selectedItem?.representedObject as? String ?? "right"
            return .object([
                "action": .string("move_window_to_adjacent_display"),
                "direction": .string(direction),
            ])

        case .maximizeWindow:
            return .object(["action": .string("maximize_window")])

        case .missionControl:
            return .object(["action": .string("mission_control")])

        case .volumeScroll:
            return .object(["action": .string("volume_scroll")])
        }
    }
}

// MARK: - 目标动作类型

private enum TargetKind: CaseIterable, Equatable {
    case sendHotkey
    case volumeScroll
    case activateApplication
    case activateAndSwitchBack
    case moveToAdjacentDisplay
    case maximizeWindow
    case missionControl

    var title: String {
        switch self {
        case .sendHotkey: return "发送快捷键"
        case .volumeScroll: return "音量滚动（滚轮）"
        case .activateApplication: return "激活应用"
        case .activateAndSwitchBack: return "激活应用（已在前台时切到上一个）"
        case .moveToAdjacentDisplay: return "移到相邻屏幕"
        case .maximizeWindow: return "最大化窗口"
        case .missionControl: return "调度中心"
        }
    }

    /// 从已有 `to` 对象反推类型（用于编辑预填）
    init?(target: [String: JSONValue]) {
        if let action = target["action"]?.stringValue {
            switch action {
            case "send_hotkey":
                self = .sendHotkey
                return
            case "volume_scroll":
                self = .volumeScroll
                return
            case "activate_application":
                self = target["already_active_behavior"]?.stringValue == "switch_to_last"
                    ? .activateAndSwitchBack
                    : .activateApplication
                return
            case "move_window_to_adjacent_display":
                self = .moveToAdjacentDisplay
                return
            case "maximize_window":
                self = .maximizeWindow
                return
            case "mission_control":
                self = .missionControl
                return
            default:
                return nil
            }
        }
        if target["key"] != nil {
            self = .sendHotkey
            return
        }
        return nil
    }
}
