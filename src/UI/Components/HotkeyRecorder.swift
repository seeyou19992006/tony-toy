import AppKit

// MARK: - 显示名转换

/// 键名 ⇄ 显示名、键码 ⇄ 键名的转换，录制器和映射表编辑器共用。
///
/// 键名一律使用 `input-aliases.json` 里的名字（`escape` / `up_arrow` /
/// `spacebar` / `a`……），不另造一套。反向（键码 → 键名）不硬编码键位表：
/// 读别名配置里的名字，再逐个问 `KeyConfigSupport.keyCode(named:)` 反解，
/// 这样用户改了 `input-aliases.json`、或者换了键盘布局（ISO/JIS 的
/// `grave_accent_and_tilde`），录制出来的名字与运行时解析保持一致。
enum HotkeyDisplay {
    /// 修饰键的显示顺序：⌘ → ⇧ → ⌥ → ⌃ → fn（与需求给的 `⌘⇧A` 一致）
    static let modifierOrder = ["command", "shift", "option", "control", "fn"]

    private static let modifierSymbols: [String: String] = [
        "command": "⌘",
        "shift": "⇧",
        "option": "⌥",
        "control": "⌃",
        "fn": "fn",
    ]

    /// 单键显示名。未收录的键名退化成「下划线换空格」。
    private static let specialKeyNames: [String: String] = [
        "escape": "⎋",
        "up_arrow": "↑",
        "down_arrow": "↓",
        "left_arrow": "←",
        "right_arrow": "→",
        "return_or_enter": "↩",
        "tab": "⇥",
        "spacebar": "Space",
        "delete_or_backspace": "⌫",
        "delete_forward": "⌦",
        "caps_lock": "⇪",
        "page_up": "⇞",
        "page_down": "⇟",
        "home": "↖",
        "end": "↘",
    ]

    private static let punctuationKeyNames: [String: String] = [
        "hyphen": "-",
        "equal_sign": "=",
        "open_bracket": "[",
        "close_bracket": "]",
        "quote": "'",
        "semicolon": ";",
        "backslash": "\\",
        "comma": ",",
        "slash": "/",
        "period": ".",
        "grave_accent_and_tilde": "`",
    ]

    // MARK: 修饰键

    /// `left_command` / `cmd` / `alt` 等写法统一成规范名
    static func canonicalModifier(_ name: String) -> String? {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("left_") {
            value = String(value.dropFirst("left_".count))
        } else if value.hasPrefix("right_") {
            value = String(value.dropFirst("right_".count))
        }
        switch value {
        case "command", "cmd", "meta":
            return "command"
        case "shift":
            return "shift"
        case "option", "alt", "alternate":
            return "option"
        case "control", "ctrl":
            return "control"
        case "fn", "function":
            return "fn"
        default:
            return nil
        }
    }

    /// 修饰键数组 → 按规范顺序拼接的符号（去重、忽略未知项）
    static func symbols(for modifiers: [String]?) -> String {
        guard let modifiers else { return "" }
        let canonical = Set(modifiers.compactMap(canonicalModifier))
        return modifierOrder
            .filter { canonical.contains($0) }
            .compactMap { modifierSymbols[$0] }
            .joined()
    }

    /// 单个 NSEvent 修饰位 → 规范名（修饰键录制时用）
    static func modifierName(for flag: NSEvent.ModifierFlags) -> String? {
        switch flag {
        case .command: return "command"
        case .shift: return "shift"
        case .option: return "option"
        case .control: return "control"
        case .function: return "fn"
        default: return nil
        }
    }

    // MARK: 键名

    static func displayName(forKey key: String) -> String {
        let lower = key.lowercased()
        if let special = specialKeyNames[lower] {
            return special
        }
        if let punctuation = punctuationKeyNames[lower] {
            return punctuation
        }
        if lower.count == 1 {
            return lower.uppercased()
        }
        return lower.replacingOccurrences(of: "_", with: " ")
    }

    static func displayName(for spec: HotkeyKeySpec?) -> String {
        guard let spec else { return "" }
        return symbols(for: spec.modifiers) + displayName(forKey: spec.key)
    }

    /// 键码 → 键名（录制用）。别名配置读不到时返回 nil，调用方降级显示。
    static func keyName(for keyCode: CGKeyCode) -> String? {
        keyNameByCode[keyCode]
    }

    // MARK: 别名数据（懒加载 + 缓存）

    private static let aliasConfig: InputAliasRegistryConfig? = {
        let store = InputAliasRegistryStore()
        // 只读，不调用 ensureConfigExists()：配置窗口不该在打开时产生副作用文件。
        for url in [store.configURL, store.templateURL] {
            if let data = try? Data(contentsOf: url),
               let config = try? JSONDecoder().decode(InputAliasRegistryConfig.self, from: data) {
                return config
            }
        }
        return nil
    }()

    /// 所有可选键名。右键菜单和程序化设置都用它。
    ///
    /// 存在的意义：65 键键盘没有独立的 `` ` `` 键（在 Esc 位置，
    /// 要靠 Fn/层切换），光靠「按下捕获」录不到。必须留一条手动指定键名的路。
    static func allKeyNames() -> [String] {
        let names = aliasConfig.map { Array($0.keyboardKeys.keys) } ?? fallbackKeyboardKeyNames
        return names.sorted()
    }

    private static let keyNameByCode: [CGKeyCode: String] = {
        let names = aliasConfig.map { Array($0.keyboardKeys.keys) } ?? fallbackKeyboardKeyNames
        var map: [CGKeyCode: String] = [:]
        for name in names.sorted() {
            guard let code = KeyConfigSupport.keyCode(named: name), map[code] == nil else {
                continue
            }
            map[code] = name.lowercased()
        }
        return map
    }()

    /// 别名配置整个读不出来时的兜底名字（键码仍由 KeyConfigSupport 解析）。
    private static let fallbackKeyboardKeyNames = [
        "a", "s", "d", "f", "h", "g", "z", "x", "c", "v", "b", "q", "w", "e",
        "r", "y", "t", "1", "2", "3", "4", "6", "5", "equal_sign", "9", "7",
        "hyphen", "8", "0", "close_bracket", "o", "u", "open_bracket", "i",
        "p", "return_or_enter", "l", "j", "quote", "k", "semicolon", "backslash",
        "comma", "slash", "n", "m", "period", "tab", "spacebar",
        "grave_accent_and_tilde", "delete_or_backspace", "escape", "caps_lock",
        "delete_forward", "left_arrow", "right_arrow", "down_arrow", "up_arrow",
    ]

    /// 鼠标输入下拉项（名称 + 中文标题）
    static func mouseInputOptions() -> [(name: String, title: String)] {
        let names = aliasConfig.map { Array($0.mouseInputs.keys) }
            ?? ["scroll_wheel", "left_click", "right_click", "middle_click",
                "button3", "button4", "button5", "button6", "button7", "button8"]
        return names.sorted().map { (name: $0, title: mouseInputTitle($0)) }
    }

    static func mouseInputTitle(_ name: String) -> String {
        switch name.lowercased() {
        case "scroll_wheel": return "滚轮"
        case "left_click", "button1": return "左键"
        case "right_click", "button2": return "右键"
        case "middle_click", "button3": return "中键"
        case "button4": return "侧键 4"
        case "button5": return "侧键 5"
        case "button6": return "侧键 6"
        case "button7": return "侧键 7"
        case "button8": return "侧键 8"
        default: return name
        }
    }
}

// MARK: - 录制控件

/// 按键录制控件。
///
/// 点击进入录制态（背景变强调色），捕获下一次 keyDown + modifiers，
/// 显示为 `⌘⇧A`。按 Esc 取消，按 Delete 清空。
///
/// 录制期间必须让 TonyToy 自己的 Caps/热键/鼠标 tap 放行，否则按键在
/// 到达 AppKit 之前就被 tap 吃掉了。tap 里统一读
/// `HotkeyRecorder.isRecording` 即可（见该属性的说明）。
final class HotkeyRecorder: NSView {
    /// 录制完成回调（清空时为 nil）
    var onChange: ((HotkeyKeySpec?) -> Void)?

    /// 当前值
    var spec: HotkeyKeySpec? {
        didSet {
            if !isRecordingSelf {
                pendingModifiers = []
                needsDisplay = true
            }
        }
    }

    /// 是否有任意一个录制器正在录制。
    ///
    /// 各 CGEvent tap 的回调里第一句判它：为 true 时直接
    /// `return Unmanaged.passUnretained(event)`，不要 consume/改写，
    /// 按键才能落到本控件的本地事件监控里。
    ///
    ///     if HotkeyRecorder.isRecording { return Unmanaged.passUnretained(event) }
    ///
    /// 想在状态切换时主动挂起/恢复 tap，可挂 `onRecordingChanged`。
    static var isRecording: Bool { activeRecorder != nil }

    /// 录制开始/结束回调（true = 开始）。tap 侧可用它避免每次事件都查标志位。
    static var onRecordingChanged: ((Bool) -> Void)?

    private static weak var activeRecorder: HotkeyRecorder?

    /// 本控件是否正在录制
    var isRecording: Bool { Self.activeRecorder === self }

    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var pendingModifiers: [String] = []
    /// 录制前保存的值，Esc 取消时回滚
    private var specBeforeRecording: HotkeyKeySpec?

    // MARK: 构造

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    deinit {
        removeMonitor()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
            Self.onRecordingChanged?(false)
        }
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolTip = "点击后按下要录制的按键；Esc 取消，Delete 清空；右键手动选键名"
        setAccessibilityLabel("快捷键录制")
        setAccessibilityRole(.button)
    }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 150, height: 26)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelRecording()
            return
        }
        guard resignObserver == nil else { return }
        // 窗口失焦时取消录制，否则全局本地监控会把别的窗口的按键也吃掉。
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.cancelRecording()
        }
    }

    // MARK: 录制

    /// 右键手动选键名。
    ///
    /// 为什么需要：65 键 / 60 键键盘没有独立的 `` ` `` 键（它在 Esc 位置，
    /// 要靠 Fn 或层切换），凭「按下捕获」永远录不到。
    /// 这里给一条按名字指定的路，不依赖物理键位。
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        let header = NSMenuItem(title: "手动指定按键", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        for name in HotkeyDisplay.allKeyNames() {
            let item = NSMenuItem(
                title: "\(HotkeyDisplay.displayName(forKey: name))   \(name)",
                action: #selector(pickKeyFromMenu(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = name
            menu.addItem(item)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func pickKeyFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let currentModifiers = spec?.modifiers ?? []
        spec = HotkeyKeySpec(key: name, modifiers: currentModifiers)
        stopRecording()
        onChange?(spec)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            cancelRecording()
        } else {
            beginRecording()
        }
    }

    /// 进入录制态（已录制中则无操作）
    func beginRecording() {
        guard !isRecording else { return }
        // 同一时间只允许一个录制器：先停掉别的
        if let active = Self.activeRecorder, active !== self {
            active.cancelRecording()
        }
        specBeforeRecording = spec
        pendingModifiers = []
        Self.activeRecorder = self
        Self.onRecordingChanged?(true)
        window?.makeFirstResponder(self)
        installMonitor()
        needsDisplay = true
    }

    /// 结束录制并保留已录到的值
    func stopRecording() {
        guard isRecording else { return }
        removeMonitor()
        Self.activeRecorder = nil
        Self.onRecordingChanged?(false)
        pendingModifiers = []
        needsDisplay = true
    }

    /// 结束录制并回滚到录制前的值（Esc / 失焦走这里，不触发 onChange）
    func cancelRecording() {
        guard isRecording else { return }
        stopRecording()
        spec = specBeforeRecording
    }

    private func installMonitor() {
        removeMonitor()
        // .keyDown + .flagsChanged：flagsChanged 只用来实时显示「按住 ⌘⇧」，
        // 不消费（返回 event），否则 AppKit 的修饰键状态会和实际不一致。
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// 返回 true 表示已消费该事件
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            pendingModifiers = modifierNames(from: event.modifierFlags)
            needsDisplay = true
            return false

        case .keyDown:
            guard !event.isARepeat else { return true }

            // 取消 / 清空只认「裸键」。
            //
            // 不能无条件把 Esc 当取消：65 键键盘没有独立的 ` 键，
            // 「⌘Esc → ⌘`」是很常见的映射，一律取消就永远录不进去。
            // 同理 ⌘Delete 也应该能录。
            let currentModifiers = modifierNames(from: event.modifierFlags)

            if event.keyCode == 53, currentModifiers.isEmpty {  // 裸 escape
                cancelRecording()
                return true
            }
            if (event.keyCode == 51 || event.keyCode == 117), currentModifiers.isEmpty {
                // 裸 delete / forward delete：清空
                spec = nil
                stopRecording()
                onChange?(nil)
                return true
            }

            guard let keyName = HotkeyDisplay.keyName(for: event.keyCode) else {
                // 别名表里没有这个键：响一声，保持录制态等下一个键
                NSSound.beep()
                return true
            }

            let newSpec = HotkeyKeySpec(key: keyName, modifiers: currentModifiers)
            spec = newSpec
            stopRecording()
            onChange?(spec)
            return true

        default:
            return false
        }
    }

    private func modifierNames(from flags: NSEvent.ModifierFlags) -> [String] {
        var names: [String] = []
        for flag in [NSEvent.ModifierFlags.function, .control, .option, .shift, .command]
        where flags.contains(flag) {
            if let name = HotkeyDisplay.modifierName(for: flag) {
                names.append(name)
            }
        }
        return names
    }

    // MARK: 绘制

    private var isRecordingSelf: Bool { isRecording }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        if isRecordingSelf {
            NSColor.controlAccentColor.setFill()
            path.fill()
        } else {
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let text: String
        let color: NSColor
        if isRecordingSelf {
            let prefix = HotkeyDisplay.symbols(for: pendingModifiers)
            text = prefix.isEmpty ? "按下按键…" : prefix + "…"
            color = .white
        } else if let spec {
            text = HotkeyDisplay.displayName(for: spec)
            color = .labelColor
        } else {
            text = "点击录制"
            color = .tertiaryLabelColor
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textRect = NSRect(
            x: 8,
            y: (bounds.height - attributed.size().height) / 2,
            width: bounds.width - 16,
            height: attributed.size().height
        )
        attributed.draw(in: textRect)
    }

    /// 键盘焦点时给一圈强调色边框（录制态本身已经是强调色底，不重复画）
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}
