import Foundation
import AppKit

/// 支持粘贴的 NSSecureTextField（系统默认禁止粘贴）
class PasteableSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 拦截 Cmd+V，直接调用 NSTextField 的 paste: 绕过安全限制
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            if let editor = currentEditor() {
                editor.paste(nil)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// 支持粘贴的 NSTextField（确保 Cmd+V 始终可用）
class PasteableTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            if let editor = currentEditor() {
                editor.paste(nil)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// 支持 Cmd+V 粘贴的 NSPanel（sheet 模式下 performKeyEquivalent 可能不触发，通过 keyDown 拦截）
class PasteablePanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 让子视图的 performKeyEquivalent 先处理
        if super.performKeyEquivalent(with: event) {
            return true
        }
        return false
    }
    
    override func cancelOperation(_ sender: Any?) {
        if let parent = sheetParent {
            parent.endSheet(self)
        } else {
            close()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            cancelOperation(nil)
            return
        }
        // 拦截 Cmd+V，找到当前焦点输入框并执行粘贴
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            if let field = firstResponder as? NSTextField, field.isEditable {
                if let editor = field.currentEditor() {
                    editor.paste(nil)
                    return
                }
            }
        }
        super.keyDown(with: event)
    }
}

/// 密码管理窗口控制器
class PasswordManagerWindow: NSWindow, NSWindowDelegate {
    let vaultService = VaultService()  // 改为 public
    private var tableView: NSTableView?
    private var searchField: NSSearchField?
    private var statusLabel: NSTextField?
    private var mainView: NSStackView?
    private var unlockView: NSStackView?
    private var masterPasswordInput: PasteableSecureTextField?
    
    /// 记录唤起面板前的前台应用，用于粘贴后恢复焦点
    private var previousApp: NSRunningApplication?
    
    /// 搜索框键盘事件监控
    private var searchFieldMonitor: Any?
    
    /// 当前选中粘贴的字段：默认密码
    private var activeField: EntryField = .password
    
    /// 可切换的粘贴字段
    enum EntryField: Int {
        case username = 0
        case password = 1
        case host = 2
    }
    
    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 675, height: 550)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "TonyPwd - 密码管理器"
        self.minSize = NSSize(width: 525, height: 400)
        self.delegate = self
        self.isReleasedWhenClosed = false
        self.level = .floating  // 保持在最前
        self.center()  // 居中显示

        setupUI()
    }

    deinit {
        if let monitor = searchFieldMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    override func orderOut(_ sender: Any?) {
        // 隐藏面板前注销密码框焦点，确保系统立刻退出 SecureEventInput
        if firstResponder is NSTextView {
            makeFirstResponder(nil)
        }
        super.orderOut(sender)
    }

    private func handleEscapeKey() {
        if let addPanel = currentAddPanel {
            endSheet(addPanel)
        } else if let editPanel = currentEditPanel {
            endSheet(editPanel)
        } else {
            let appToRestore = previousApp
            orderOut(nil)
            DispatchQueue.main.async {
                appToRestore?.activate()
            }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        handleEscapeKey()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           isVisible {
            if let editor = firstResponder as? NSTextView, editor.hasMarkedText() {
                return super.performKeyEquivalent(with: event)
            }
            handleEscapeKey()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// 重写 keyDown：处理 ESC 关闭面板/恢复焦点
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            handleEscapeKey()
        } else {
            super.keyDown(with: event)
        }
    }
    
    private func setupUI() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 675, height: 550))
        contentView = containerView
        containerView.autoresizingMask = [.width, .height]
        
        // 创建解锁视图
        unlockView = NSStackView(frame: containerView.bounds)
        unlockView?.autoresizingMask = [.width, .height]
        unlockView?.orientation = .vertical
        unlockView?.spacing = 15
        unlockView?.alignment = .centerX
        unlockView?.edgeInsets = NSEdgeInsets(top: 100, left: 50, bottom: 100, right: 50)
        
        let lockIcon = NSTextField(labelWithString: "🔒")
        lockIcon.font = NSFont.systemFont(ofSize: 60)
        lockIcon.alignment = .center
        unlockView?.addArrangedSubview(lockIcon)
        
        let titleLabel = NSTextField(labelWithString: "输入主密码")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.alignment = .center
        unlockView?.addArrangedSubview(titleLabel)
        
        let passwordInput = PasteableSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        passwordInput.placeholderString = "主密码"
        passwordInput.font = NSFont.systemFont(ofSize: 14)
        passwordInput.target = self
        passwordInput.action = #selector(unlockVault)
        passwordInput.identifier = NSUserInterfaceItemIdentifier("masterPasswordInput")
        unlockView?.addArrangedSubview(passwordInput)
        masterPasswordInput = passwordInput  // 保存引用
        
        let unlockButton = NSButton(title: "解锁 / 创建", target: self, action: #selector(unlockVault))
        unlockButton.bezelStyle = .rounded
        unlockButton.keyEquivalent = "\r"
        unlockView?.addArrangedSubview(unlockButton)
        
        containerView.addSubview(unlockView!)
        
        // 创建主视图（默认隐藏）
        mainView = NSStackView(frame: containerView.bounds)
        mainView?.autoresizingMask = [.width, .height]
        mainView?.orientation = .vertical
        mainView?.spacing = 10
        mainView?.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        mainView?.isHidden = true
        
        // 顶部：搜索 + 添加
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 8
        
        let search = NSSearchField(frame: NSRect(x: 0, y: 0, width: 380, height: 30))
        search.placeholderString = "搜索密码..."
        search.target = self
        search.action = #selector(searchChanged)
        topRow.addArrangedSubview(search)
        searchField = search
        
        // 即时搜索：监听文本变化，绕过 NSSearchField 内置延迟
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(searchChanged),
            name: NSControl.textDidChangeNotification,
            object: search
        )
        
        // 本地监控：搜索框键盘事件（回车粘贴、方向键导航、左右切换字段）
        searchFieldMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  self.isVisible,
                  event.window === self || event.window?.sheetParent === self else {
                return event
            }
            
            // 以下快捷键仅在搜索框有焦点时生效
            guard self.searchField?.currentEditor() != nil else { return event }
            
            switch event.keyCode {
            case 36: // Return 键 - 粘贴当前选中行（或第一个匹配结果）
                if let entry = self.selectedEntry() {
                    self.pasteEntryValue(entry)
                    return nil
                }
            case 125: // 下箭头 - 选中下一行
                if let table = self.tableView {
                    let filtered = self.vaultService.search(self.searchField?.stringValue ?? "")
                    if !filtered.isEmpty {
                        let current = table.selectedRow
                        let next = current < 0 ? 0 : min(current + 1, filtered.count - 1)
                        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                        table.scrollRowToVisible(next)
                        return nil
                    }
                }
            case 126: // 上箭头 - 选中上一行
                if let table = self.tableView {
                    let filtered = self.vaultService.search(self.searchField?.stringValue ?? "")
                    if !filtered.isEmpty {
                        let current = table.selectedRow
                        let prev = current <= 0 ? 0 : max(current - 1, 0)
                        table.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
                        table.scrollRowToVisible(prev)
                        return nil
                    }
                }
            case 124: // 右箭头 - 搜索框为空时切换到下一个字段（按 UI 列顺序：host→username→password）
                guard (self.searchField?.stringValue ?? "").isEmpty else { break }
                switch self.activeField {
                case .host: self.activeField = .username
                case .username: self.activeField = .password
                case .password: self.activeField = .host
                }
                self.refreshSelectedCell()
                return nil
            case 123: // 左箭头 - 搜索框为空时切换到上一个字段（password→username→host）
                guard (self.searchField?.stringValue ?? "").isEmpty else { break }
                switch self.activeField {
                case .host: self.activeField = .password
                case .password: self.activeField = .username
                case .username: self.activeField = .host
                }
                self.refreshSelectedCell()
                return nil
            default:
                break
            }
            return event
        }
        
        let addButton = NSButton(title: "+ 添加", target: self, action: #selector(addEntry))
        addButton.bezelStyle = .rounded
        topRow.addArrangedSubview(addButton)
        
        mainView?.addArrangedSubview(topRow)
        
        // 中间：表格
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        
        let table = NSTableView()
        
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("nameCol"))
        nameCol.title = "服务名"
        nameCol.width = 120
        nameCol.resizingMask = .userResizingMask
        table.addTableColumn(nameCol)
        
        let hostCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hostCol"))
        hostCol.title = "IP / 域名"
        hostCol.width = 140
        hostCol.resizingMask = .userResizingMask
        table.addTableColumn(hostCol)
        
        let userCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("userCol"))
        userCol.title = "用户名"
        userCol.width = 120
        userCol.resizingMask = .userResizingMask
        table.addTableColumn(userCol)
        
        let pwdCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pwdCol"))
        pwdCol.title = "密码"
        pwdCol.width = 180
        pwdCol.resizingMask = .userResizingMask
        table.addTableColumn(pwdCol)
        
        table.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(pasteSelected)
        table.usesAlternatingRowBackgroundColors = true
        table.selectionHighlightStyle = .none
        table.allowsColumnSelection = false
        table.allowsTypeSelect = false
        table.menu = buildTableMenu()
        
        scroll.documentView = table
        mainView?.addArrangedSubview(scroll)
        tableView = table
        
        // 底部：状态 + 锁定
        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 10
        
        let status = NSTextField(labelWithString: "0 个密码")
        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = NSColor.secondaryLabelColor
        bottomRow.addArrangedSubview(status)
        statusLabel = status
        
        bottomRow.addArrangedSubview(NSView())  // 弹簧
        
        let lockButton = NSButton(title: "🔒 锁定", target: self, action: #selector(lockVault))
        lockButton.bezelStyle = .rounded
        lockButton.font = NSFont.systemFont(ofSize: 11)
        bottomRow.addArrangedSubview(lockButton)
        
        mainView?.addArrangedSubview(bottomRow)
        
        containerView.addSubview(mainView!)
    }
    
    // MARK: - 显示控制

    @objc func showMainView() {
        // 先让密码框退出第一响应者，避免隐藏视图后系统 SecureEventInput 残留，
        // 否则会导致全局 CGEventTap（Caps 层/快捷键）全部收不到键盘事件。
        if firstResponder is NSTextView {
            makeFirstResponder(nil)
        }
        masterPasswordInput?.stringValue = ""
        unlockView?.isHidden = true
        mainView?.isHidden = false
        reloadData()
        // 延迟设置焦点，等待窗口成为 key window
        DispatchQueue.main.async {
            self.makeFirstResponder(self.searchField)
        }
    }

    @objc func showUnlockView() {
        if firstResponder is NSTextView {
            makeFirstResponder(nil)
        }
        unlockView?.isHidden = false
        mainView?.isHidden = true
        // 延迟设置焦点，等待窗口成为 key window
        DispatchQueue.main.async {
            self.masterPasswordInput?.stringValue = ""
            self.makeFirstResponder(self.masterPasswordInput)
        }
    }
    
    // MARK: - 操作
    
    @objc private func unlockVault() {
        guard let password = masterPasswordInput?.stringValue, !password.isEmpty else { return }

        do {
            if vaultService.vaultExists {
                try vaultService.unlock(masterPassword: password)
            } else {
                try vaultService.createVault(masterPassword: password)
            }
            showMainView()
        } catch {
            print("❌ Vault 错误: \(error)")
            showErrorAlert(error.localizedDescription)
            masterPasswordInput?.stringValue = ""
        }
    }
    
    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "❌ 错误"
        alert.addButton(withTitle: "确定")

        // 使用 NSTextView 替代 NSTextField，使其可选中和复制
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        textView.string = message
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.windowBackgroundColor
        textView.textContainerInset = NSSize(width: 0, height: 0)

        // 设置文本视图的容器
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        alert.accessoryView = scrollView
        alert.runModal()
    }
    
    @objc private func lockVault() {
        vaultService.lock()
        showUnlockView()
    }
    
    @objc private func searchChanged() {
        activeField = .password  // 搜索变化时重置为密码
        reloadData()
    }
    
    private var currentAddPanel: PasteablePanel?
    
    /// 构建带眼睛切换的密码输入行（安全输入框 + 明文输入框 + 眼睛按钮）
    private func makePasswordRow(placeholder: String = "密码 (支持粘贴)", value: String = "") -> (view: NSView, field: PasteableSecureTextField) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.identifier = NSUserInterfaceItemIdentifier("passwordRow")
        
        // 安全输入框（默认显示）
        let secureField = PasteableSecureTextField()
        secureField.placeholderString = placeholder
        secureField.font = NSFont.systemFont(ofSize: 13)
        secureField.identifier = NSUserInterfaceItemIdentifier("passwordField")
        secureField.translatesAutoresizingMaskIntoConstraints = false
        if !value.isEmpty {
            secureField.stringValue = value
        }
        row.addSubview(secureField)
        
        // 明文输入框（默认隐藏，眼睛打开时显示）
        let plainField = PasteableTextField()
        plainField.placeholderString = placeholder
        plainField.font = NSFont.systemFont(ofSize: 13)
        plainField.identifier = NSUserInterfaceItemIdentifier("passwordPlainField")
        plainField.translatesAutoresizingMaskIntoConstraints = false
        plainField.isHidden = true
        if !value.isEmpty {
            plainField.stringValue = value
        }
        row.addSubview(plainField)
        
        // 眼睛按钮
        let eyeBtn = NSButton()
        eyeBtn.bezelStyle = .inline
        eyeBtn.isBordered = false
        eyeBtn.imagePosition = .imageOnly
        eyeBtn.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "显示密码")
        eyeBtn.alternateImage = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "隐藏密码")
        eyeBtn.imageScaling = .scaleProportionallyDown
        eyeBtn.setButtonType(.toggle)
        eyeBtn.identifier = NSUserInterfaceItemIdentifier("panelEyeBtn")
        eyeBtn.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(eyeBtn)
        
        eyeBtn.target = self
        eyeBtn.action = #selector(togglePanelPasswordVisibility(_:))
        
        NSLayoutConstraint.activate([
            // 安全输入框
            secureField.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: eyeBtn.leadingAnchor, constant: -4),
            secureField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            secureField.heightAnchor.constraint(equalToConstant: 28),
            
            // 明文输入框（与安全输入框完全重叠）
            plainField.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            plainField.trailingAnchor.constraint(equalTo: eyeBtn.leadingAnchor, constant: -4),
            plainField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            plainField.heightAnchor.constraint(equalToConstant: 28),
            
            // 眼睛按钮
            eyeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            eyeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            eyeBtn.widthAnchor.constraint(equalToConstant: 24),
            eyeBtn.heightAnchor.constraint(equalToConstant: 24),
            
            row.heightAnchor.constraint(equalToConstant: 28),
        ])
        
        return (row, secureField)
    }
    
    /// 面板中眼睛按钮切换密码明文/隐藏
    @objc private func togglePanelPasswordVisibility(_ sender: NSButton) {
        guard let rowView = sender.superview else { return }
        guard let secureField = rowView.subviews.first(where: { $0.identifier?.rawValue == "passwordField" }) as? PasteableSecureTextField,
              let plainField = rowView.subviews.first(where: { $0.identifier?.rawValue == "passwordPlainField" }) as? NSTextField else { return }
        
        let showPlain = sender.state == .on
        if showPlain {
            // 同步值：安全框 → 明文框
            plainField.stringValue = secureField.stringValue
        } else {
            // 同步值：明文框 → 安全框
            secureField.stringValue = plainField.stringValue
        }
        secureField.isHidden = showPlain
        plainField.isHidden = !showPlain
    }
    
    @objc private func addEntry() {
        // 避免重复打开
        guard currentAddPanel == nil && currentEditPanel == nil else { return }
        
        let panel = PasteablePanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 320),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        panel.title = "添加密码"
        panel.isReleasedWhenClosed = false
        
        let container = NSStackView(frame: panel.contentView!.bounds)
        container.orientation = .vertical
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        let nameField = PasteableTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 28))
        nameField.placeholderString = "服务名"
        nameField.font = NSFont.systemFont(ofSize: 13)
        nameField.identifier = NSUserInterfaceItemIdentifier("nameField")
        container.addArrangedSubview(nameField)
        
        let hostField = PasteableTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 28))
        hostField.placeholderString = "IP / 域名"
        hostField.font = NSFont.systemFont(ofSize: 13)
        hostField.identifier = NSUserInterfaceItemIdentifier("hostField")
        container.addArrangedSubview(hostField)
        
        let usernameField = PasteableTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 28))
        usernameField.placeholderString = "用户名"
        usernameField.font = NSFont.systemFont(ofSize: 13)
        usernameField.identifier = NSUserInterfaceItemIdentifier("usernameField")
        container.addArrangedSubview(usernameField)
        
        let passwordRow = makePasswordRow()
        container.addArrangedSubview(passwordRow.view)
        
        let notesField = NSTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 60))
        notesField.placeholderString = "备注"
        notesField.font = NSFont.systemFont(ofSize: 13)
        notesField.identifier = NSUserInterfaceItemIdentifier("notesField")
        notesField.isEditable = true
        notesField.isSelectable = true
        notesField.lineBreakMode = .byWordWrapping
        notesField.usesSingleLineMode = false
        container.addArrangedSubview(notesField)
        
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        
        let cancelBtn = NSButton(title: "取消", target: self, action: #selector(closeAddPanel))
        cancelBtn.bezelStyle = .rounded
        buttonRow.addArrangedSubview(cancelBtn)
        
        buttonRow.addArrangedSubview(NSView())
        
        let saveBtn = NSButton(title: "保存", target: nil, action: nil)
        saveBtn.bezelStyle = .rounded
        saveBtn.bezelColor = NSColor.controlAccentColor
        saveBtn.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(saveBtn)
        
        container.addArrangedSubview(buttonRow)
        panel.contentView?.addSubview(container)
        
        saveBtn.target = self
        saveBtn.action = #selector(saveNewEntry)
        currentAddPanel = panel

        // 以 sheet 模态显示
        self.beginSheet(panel) { [weak self] _ in
            self?.currentAddPanel = nil
        }
        DispatchQueue.main.async {
            panel.makeFirstResponder(nameField)
        }
    }
    
    @objc private func closeAddPanel() {
        guard let panel = currentAddPanel else { return }
        self.endSheet(panel)
    }
    
    @objc private func saveNewEntry() {
        guard let panel = currentAddPanel else { return }
        guard let container = panel.contentView?.subviews.first as? NSStackView else { return }

        let nameField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "nameField" }) as? NSTextField
        let hostField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "hostField" }) as? NSTextField
        let usernameField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "usernameField" }) as? NSTextField
        let notesField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "notesField" }) as? NSTextField
        // 密码：安全框或明文框（眼睛切换时只有一个可见）
        let passwordSecureField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "passwordRow" })?.subviews.first(where: { $0.identifier?.rawValue == "passwordField" }) as? PasteableSecureTextField
        let passwordPlainField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "passwordRow" })?.subviews.first(where: { $0.identifier?.rawValue == "passwordPlainField" }) as? NSTextField
        let passwordValue = passwordSecureField?.isHidden == true ? passwordPlainField?.stringValue : passwordSecureField?.stringValue

        guard let name = nameField?.stringValue, !name.isEmpty,
              let password = passwordValue, !password.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "请填写必填项"
            alert.addButton(withTitle: "确定")
            alert.beginSheetModal(for: panel)
            return
        }
        
        do {
            try vaultService.addEntry(
                name: name,
                host: hostField?.stringValue ?? "",
                username: usernameField?.stringValue ?? "",
                password: password,
                notes: notesField?.stringValue ?? ""
            )
            self.endSheet(panel)
            reloadData()
        } catch {
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "确定")
            alert.beginSheetModal(for: panel)
        }
    }
    
    @objc private func pasteSelected() {
        guard let table = tableView else { return }
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard row >= 0 else { return }
        let filtered = vaultService.search(searchField?.stringValue ?? "")
        guard row < filtered.count else { return }

        // 根据双击的列更新 activeField，使粘贴的字段与点击的列一致
        let col = table.clickedColumn
        if col >= 0 {
            let colId = table.tableColumns[col].identifier.rawValue
            switch colId {
            case "hostCol": activeField = .host
            case "userCol": activeField = .username
            case "pwdCol": activeField = .password
            default: break
            }
            refreshSelectedCell()
        }

        pasteEntryValue(filtered[row])
    }
    
    // MARK: - 编辑条目
    
    private var currentEditPanel: PasteablePanel?
    private var editingEntryId: UUID?
    
    @objc private func editEntry() {
        guard let entry = selectedEntry() else { return }
        // 避免重复打开
        guard currentAddPanel == nil && currentEditPanel == nil else { return }
        
        editingEntryId = entry.id
        
        let panel = PasteablePanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 320),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        panel.title = "编辑密码"
        panel.isReleasedWhenClosed = false
        
        let container = NSStackView(frame: panel.contentView!.bounds)
        container.orientation = .vertical
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        let nameField = PasteableTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 28))
        nameField.placeholderString = "服务名"
        nameField.font = NSFont.systemFont(ofSize: 13)
        nameField.stringValue = entry.name
        nameField.identifier = NSUserInterfaceItemIdentifier("nameField")
        container.addArrangedSubview(nameField)
        
        let hostField = PasteableTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 28))
        hostField.placeholderString = "IP / 域名"
        hostField.font = NSFont.systemFont(ofSize: 13)
        hostField.stringValue = entry.host
        hostField.identifier = NSUserInterfaceItemIdentifier("hostField")
        container.addArrangedSubview(hostField)
        
        let usernameField = PasteableTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 28))
        usernameField.placeholderString = "用户名"
        usernameField.font = NSFont.systemFont(ofSize: 13)
        usernameField.stringValue = entry.username
        usernameField.identifier = NSUserInterfaceItemIdentifier("usernameField")
        container.addArrangedSubview(usernameField)
        
        let passwordRow = makePasswordRow(value: entry.password)
        container.addArrangedSubview(passwordRow.view)
        
        let notesField = NSTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 60))
        notesField.placeholderString = "备注"
        notesField.font = NSFont.systemFont(ofSize: 13)
        notesField.stringValue = entry.notes
        notesField.identifier = NSUserInterfaceItemIdentifier("notesField")
        notesField.isEditable = true
        notesField.isSelectable = true
        notesField.lineBreakMode = .byWordWrapping
        notesField.usesSingleLineMode = false
        container.addArrangedSubview(notesField)
        
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        
        let cancelBtn = NSButton(title: "取消", target: self, action: #selector(closeEditPanel))
        cancelBtn.bezelStyle = .rounded
        buttonRow.addArrangedSubview(cancelBtn)
        
        buttonRow.addArrangedSubview(NSView())
        
        let saveBtn = NSButton(title: "保存", target: nil, action: nil)
        saveBtn.bezelStyle = .rounded
        saveBtn.bezelColor = NSColor.controlAccentColor
        saveBtn.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(saveBtn)
        
        container.addArrangedSubview(buttonRow)
        panel.contentView?.addSubview(container)
        
        saveBtn.target = self
        saveBtn.action = #selector(saveEditEntry)
        currentEditPanel = panel
        
        // 以 sheet 模态显示
        self.beginSheet(panel) { [weak self] _ in
            self?.currentEditPanel = nil
        }
        DispatchQueue.main.async {
            panel.makeFirstResponder(nameField)
        }
    }
    
    @objc private func closeEditPanel() {
        guard let panel = currentEditPanel else { return }
        self.endSheet(panel)
    }
    
    @objc private func saveEditEntry() {
        guard let panel = currentEditPanel,
              let entryId = editingEntryId else { return }
        guard let container = panel.contentView?.subviews.first as? NSStackView else { return }
        
        let nameField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "nameField" }) as? NSTextField
        let hostField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "hostField" }) as? NSTextField
        let usernameField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "usernameField" }) as? NSTextField
        let notesField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "notesField" }) as? NSTextField
        // 密码：安全框或明文框（眼睛切换时只有一个可见）
        let passwordSecureField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "passwordRow" })?.subviews.first(where: { $0.identifier?.rawValue == "passwordField" }) as? PasteableSecureTextField
        let passwordPlainField = container.arrangedSubviews.first(where: { $0.identifier?.rawValue == "passwordRow" })?.subviews.first(where: { $0.identifier?.rawValue == "passwordPlainField" }) as? NSTextField
        let passwordValue = passwordSecureField?.isHidden == true ? passwordPlainField?.stringValue : passwordSecureField?.stringValue
        
        guard let name = nameField?.stringValue, !name.isEmpty,
              let password = passwordValue, !password.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "请填写必填项"
            alert.addButton(withTitle: "确定")
            alert.beginSheetModal(for: panel)
            return
        }
        
        // 找到原条目并更新
        let updated = vaultService.entries.first { $0.id == entryId }
        guard var entry = updated else { return }
        entry.name = name
        entry.host = hostField?.stringValue ?? ""
        entry.username = usernameField?.stringValue ?? ""
        entry.password = password
        entry.notes = notesField?.stringValue ?? ""
        entry.updatedAt = Date()
        
        do {
            try vaultService.updateEntry(entry)
            self.endSheet(panel)
            reloadData()
        } catch {
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "确定")
            alert.beginSheetModal(for: panel)
        }
    }
    
    @objc private func deleteEntry() {
        guard let entry = selectedEntry() else { return }
        let alert = NSAlert()
        alert.messageText = "删除确认"
        alert.informativeText = "确定要删除「\(entry.name)」吗？"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try vaultService.deleteEntry(id: entry.id)
                reloadData()
            } catch {
                let errAlert = NSAlert()
                errAlert.messageText = "删除失败"
                errAlert.informativeText = error.localizedDescription
                errAlert.addButton(withTitle: "确定")
                errAlert.runModal()
            }
        }
    }
    
    /// 眼睛按钮：切换密码明文/隐藏
    @objc private func togglePasswordVisibility(_ sender: NSButton) {
        guard tableView != nil else { return }
        let row = sender.tag
        let filtered = vaultService.search(searchField?.stringValue ?? "")
        guard row >= 0, row < filtered.count else { return }
        
        let entry = filtered[row]
        let isShown = sender.state == .on
        
        // 找到同一 passwordTag 内的 passwordLabel
        if let passwordTag = sender.superview,
           let passwordLabel = passwordTag.subviews.first(where: { $0.identifier?.rawValue == "passwordLabel" }) as? NSTextField {
            passwordLabel.stringValue = isShown ? entry.password : String(repeating: "•", count: entry.password.count)
        }
    }

    /// 根据 activeField 粘贴选中条目的用户名或密码
    private func pasteEntryValue(_ entry: PasswordEntry) {
        let value: String
        switch activeField {
        case .username:
            value = entry.username
        case .password:
            value = entry.password
        case .host:
            value = entry.host
        }
        
        // 保存需要恢复焦点的应用
        let appToRestore = previousApp
        
        // 隐藏窗口
        orderOut(nil)
        
        // 恢复前台应用焦点后由 PasswordPaster 写入剪贴板并粘贴
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let app = appToRestore {
                app.activate()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                PasswordPaster.paste(password: value)
            }
        }
    }
    
    /// 在窗口显示前记录当前前台应用
    func recordPreviousApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        } else {
            previousApp = nil
        }
    }
    
    /// 获取当前选中的条目（表格选中行，若无选中则取第一个）
    private func selectedEntry() -> PasswordEntry? {
        guard let table = tableView else { return nil }
        let filtered = vaultService.search(searchField?.stringValue ?? "")
        if filtered.isEmpty { return nil }
        let row = table.selectedRow
        // 无选中或选中行无效时取第一个
        let index = (row >= 0 && row < filtered.count) ? row : 0
        return filtered[index]
    }
    
    private func reloadData() {
        tableView?.reloadData()
        let filtered = vaultService.search(searchField?.stringValue ?? "")
        statusLabel?.stringValue = "\(filtered.count) 个密码"
        // 延迟选行，等表格布局完成后再选中，避免行索引越界
        if !filtered.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        }
    }
}

// MARK: - TableView 代理

extension PasswordManagerWindow: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        vaultService.search(searchField?.stringValue ?? "").count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let filtered = vaultService.search(searchField?.stringValue ?? "")
        guard row < filtered.count else { return nil }
        
        let entry = filtered[row]
        let colId = tableColumn?.identifier.rawValue ?? ""
        let isSelected = tableView.selectedRow == row
        
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier(colId)
        
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        
        switch colId {
        case "nameCol":
            label.stringValue = entry.name
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            if !entry.notes.isEmpty {
                cell.toolTip = entry.notes
            }
        case "hostCol":
            label.stringValue = entry.host.isEmpty ? "-" : entry.host
        case "userCol":
            label.stringValue = entry.username.isEmpty ? "-" : entry.username
        case "pwdCol":
            let maskedPassword = String(repeating: "•", count: entry.password.count)
            label.stringValue = maskedPassword
            label.identifier = NSUserInterfaceItemIdentifier("passwordLabel")
            // 眼睛按钮
            let eyeBtn = NSButton()
            eyeBtn.identifier = NSUserInterfaceItemIdentifier("eyeBtn")
            eyeBtn.bezelStyle = .inline
            eyeBtn.isBordered = false
            eyeBtn.imagePosition = .imageOnly
            eyeBtn.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "显示密码")
            eyeBtn.alternateImage = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "隐藏密码")
            eyeBtn.imageScaling = .scaleProportionallyDown
            eyeBtn.setButtonType(.toggle)
            eyeBtn.tag = row
            eyeBtn.target = self
            eyeBtn.action = #selector(togglePasswordVisibility(_:))
            eyeBtn.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(eyeBtn)
            // 调整约束：label 在左，眼睛在右
            label.trailingAnchor.constraint(equalTo: eyeBtn.leadingAnchor, constant: -4).isActive = true
            NSLayoutConstraint.activate([
                eyeBtn.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                eyeBtn.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                eyeBtn.widthAnchor.constraint(equalToConstant: 22),
                eyeBtn.heightAnchor.constraint(equalToConstant: 22),
            ])
        default:
            break
        }
        
        // 高亮交给 refreshRowHighlight 控制，viewFor 只负责内容
        cell.wantsLayer = true
        cell.layer?.backgroundColor = NSColor.clear.cgColor
        if isSelected {
            applyRowHighlight(table: tableView, row: row)
        }
        
        return cell
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 36
    }
    
    /// 选中行变化时刷新高亮
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = tableView else { return }
        // 直接清除旧行 + 高亮新行，不依赖 reloadData
        if let userInfo = notification.userInfo,
           let oldRows = userInfo["NSOldSelectedRows"] as? IndexSet {
            for row in oldRows where row >= 0 && row < table.numberOfRows {
                for col in 0..<table.numberOfColumns {
                    guard let cell = table.view(atColumn: col, row: row, makeIfNecessary: false) else { continue }
                    cell.wantsLayer = true
                    cell.layer?.backgroundColor = NSColor.clear.cgColor
                }
            }
        }
        if table.selectedRow >= 0 {
            applyRowHighlight(table: table, row: table.selectedRow)
        }
        // 鼠标点击行后焦点会留在表格，拉回搜索框以保持键盘快捷键生效
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let sf = self.searchField else { return }
            if self.firstResponder !== sf.currentEditor() {
                self.makeFirstResponder(sf)
            }
        }
    }
    
    /// 刷新选中行的字段高亮
    private func refreshSelectedCell() {
        guard let table = tableView, table.selectedRow >= 0, table.selectedRow < table.numberOfRows else { return }
        applyRowHighlight(table: table, row: table.selectedRow)
    }

    /// 给指定行设置高亮：active 列强调色，其他列浅底色
    private func applyRowHighlight(table: NSTableView, row: Int) {
        // 先清除所有可见行的高亮
        let visibleRows = table.rows(in: table.visibleRect)
        for r in visibleRows.lowerBound..<visibleRows.upperBound {
            for col in 0..<table.numberOfColumns {
                guard let cell = table.view(atColumn: col, row: r, makeIfNecessary: false) else { continue }
                cell.wantsLayer = true
                cell.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
        // 再给选中行上色
        guard row >= 0, row < table.numberOfRows else { return }
        for col in 0..<table.numberOfColumns {
            guard let cell = table.view(atColumn: col, row: row, makeIfNecessary: false) else { continue }
            let colId = cell.identifier?.rawValue ?? ""
            cell.wantsLayer = true
            switch (colId, activeField) {
            case ("hostCol", .host), ("userCol", .username), ("pwdCol", .password):
                cell.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
            case ("nameCol", _):
                cell.layer?.backgroundColor = NSColor.clear.cgColor
            default:
                cell.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    /// 构建表格右键菜单
    private func buildTableMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "编辑", action: #selector(editEntry), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "删除", action: #selector(deleteEntry), keyEquivalent: ""))
        return menu
    }
}
