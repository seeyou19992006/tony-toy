import Cocoa
import IOKit.hid

/// 输入链路的诊断工具。
///
/// 排查「某个键不生效」时的标准流程：
/// 1. 权限是否齐全（缺辅助功能 → 所有 tap 都建不起来）
/// 2. 有几个 tap 在跑，各自监听什么（漏掉的 tap 会让按键走不到 AppKit）
/// 3. 某个键到底有没有到 AppKit（`KeyTracePanel` 做实时追踪）
///
/// 这三步之前全靠读代码和临时加 `dbg` 猜，现在有固定入口。
enum InputDiagnostics {
    // MARK: - 权限

    struct PermissionState {
        let accessibility: Bool
        let inputMonitoring: Bool
    }

    static func permissions() -> PermissionState {
        PermissionState(
            accessibility: AXIsProcessTrusted(),
            // tap 想拿到键盘事件，两者都需要
            inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
                == kIOHIDAccessTypeGranted
        )
    }

    // MARK: - 报告

    /// 完整诊断报告（文本，可直接贴给别人看）
    static func report() -> String {
        let perms = permissions()
        var lines: [String] = []

        lines.append("=== 权限 ===")
        lines.append("辅助功能    \(perms.accessibility ? "已授权" : "未授权（tap 无法创建）")")
        lines.append("输入监控    \(perms.inputMonitoring ? "已授权" : "未授权（可能收不到键盘事件）")")

        lines.append("")
        lines.append("=== 输入监听器 ===")
        lines.append(InputRegistry.shared.describe())

        lines.append("")
        lines.append("=== 说明 ===")
        lines.append("按键到达 AppKit 之前要经过上面所有 tap。")
        lines.append("任何一个 tap 消费了事件，下游都收不到——")
        lines.append("排查时先看谁在监听 keyDown，再用按键追踪确认在哪一层消失。")

        return lines.joined(separator: "\n")
    }

    /// 打开系统设置的对应权限面板
    static func openPrivacyPane(inputMonitoring: Bool) {
        let anchor = inputMonitoring ? "Privacy_ListenEvent" : "Privacy_Accessibility"
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 按键追踪

/// 实时显示按键在各层 tap 的到达情况。
///
/// 用一个独立的 tap 观察事件。它用的是 `.defaultTap`（需要辅助功能授权），
/// 但 handler 永远原样返回事件，所以不消费、也不修改。
///
/// 它能回答的只有「事件有没有到达这一层」，回答不了「被哪个 tap 消费了」——
/// CGEvent 层没有这种 API。不过因为它是 headInsert、排在所有人前面，
/// 只要它看到了，事件在此之前一定是完好的；应用仍收不到，问题就出在后面。
final class KeyTracePanel: NSObject {
    private var window: NSWindow?
    private var textView: NSTextView?
    private var observer: EventTap?
    private var gamepadTrace: GamepadTrace?
    private var homeObserverID: UUID?
    /// 说明文字只在第一次打开时写一遍，重开窗口不再重复刷屏
    private var hasShownIntro = false

    private var pauseButton: NSButton?
    /// 暂停只是不往文本里写，tap 本身照常运行——
    /// 停掉再重建会有延迟和状态丢失，而暂停的用途只是「别滚，让我看清」。
    private var isPaused = false

    /// 是否正在追踪
    private(set) var isTracing = false

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // 重开面板当成一次新的开始，别让上次的暂停状态把人绕进去。
            // 要放在 startTracing 之前，否则「重新开始追踪」那行会被暂停挡掉。
            setPaused(false, silent: true)
            // 上次是关掉窗口退出的（只停追踪不销毁窗口），这里要把追踪接回去
            if !isTracing { startTracing() }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "按键追踪"
        window.center()

        // 必须关掉。NSWindow 默认 isReleasedWhenClosed = true，关闭时 AppKit
        // 会自己 release 一次；但我们用 ARC 强引用持有（self.window），
        // 于是引用计数被多减一次 → 事件循环 drain autorelease pool 时
        // objc_release 撞上已释放对象，整个进程 SIGSEGV 崩掉。
        // 表现就是「关掉追踪窗口，TonyToy 整个退了」。
        window.isReleasedWhenClosed = false

        let container = NSView()

        // 顶部工具栏：清空 / 暂停
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .centerY
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 6, right: 10)

        let clearButton = NSButton(
            title: "清空", target: self, action: #selector(clearLog))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.font = .systemFont(ofSize: 12)

        let pauseButton = NSButton(
            title: "暂停", target: self, action: #selector(togglePause))
        pauseButton.bezelStyle = .rounded
        pauseButton.controlSize = .small
        pauseButton.font = .systemFont(ofSize: 12)

        toolbar.addArrangedSubview(clearButton)
        toolbar.addArrangedSubview(pauseButton)
        // 让两个按钮靠左，剩下的横向空间被这一块吃掉
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(spacer)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        container.addSubview(toolbar)
        container.addSubview(scrollView)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        window.contentView = container

        self.window = window
        self.textView = textView
        self.pauseButton = pauseButton

        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startTracing()
    }

    // MARK: - 追踪

    /// 自测用：等价于用户点窗口的关闭按钮
    func closeForTest() {
        window?.close()
    }

    func startTracing() {
        guard !isTracing else { return }
        isTracing = true

        if !hasShownIntro {
            hasShownIntro = true
            append("=== 开始追踪（按任意键 / 手柄键查看）===")
            append("判断方法：下面每一行都是「这个键的事件，被本面板的观察 tap 看到了」。")
            append("观察 tap 用 headInsert 插在事件流最前面，比应用和所有其他 tap 都早，")
            append("所以在两个方向上都能给出确定结论：")
            append("  · 这里有记录  → 事件确实产生了，键和权限都没问题。")
            append("                 应用仍没反应，就是被排在后面的某个 tap 吃掉了")
            append("                 （对照「输入诊断」里的监听器列表，顺序越靠后越可疑）")
            append("  · 这里没记录  → 事件根本没进到这一层：权限不足、键盘本身、")
            append("                 或者更靠前的环节就断了")
            append("手柄 Home：来自原始 HID 报告，应用在后台也能收到。")
            append("手柄其他键：来自 GameController，需要手柄已被系统识别。")
            append("")
        } else {
            append("")
            append("=== 重新开始追踪 ===")
        }

        // 用独立 tap 观察。注意它自己也会出现在 InputRegistry 里，
        // 但 kind 是 eventTap，不消费事件（handler 永远返回 event）。
        let tap = EventTap(
            name: "keyTrace（只观察）",
            events: .make([.keyDown, .flagsChanged])
        ) { [weak self] type, event in
            self?.record(type: type, event: event)
            return event
        }
        observer = tap
        tap.start()

        startGamepadTracing()
    }

    // MARK: - 手柄追踪

    private func startGamepadTracing() {
        // Home 走原始 HID。这里只注册旁听者，不动 GamepadFeature 的回调，
        // 也不会因为它把 homeWake 关掉就看不到按键。
        HomeKeyBridge.shared.start()
        homeObserverID = HomeKeyBridge.shared.addHomeObserver { [weak self] device in
            self?.appendEvent("手柄  Home  ← 原始 HID  [\(device)]")
        }

        let trace = GamepadTrace()
        trace.onButton = { [weak self] name, device, pressed in
            guard pressed else { return }
            self?.appendEvent("手柄  \(name)  ← GameController  [\(device)]")
        }
        trace.start()
        gamepadTrace = trace
    }

    func stopTracing() {
        observer?.stop()
        observer = nil

        gamepadTrace?.stop()
        gamepadTrace = nil

        if let homeObserverID {
            HomeKeyBridge.shared.removeHomeObserver(homeObserverID)
            self.homeObserverID = nil
        }

        isTracing = false
    }

    private func record(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        var mods: [String] = []
        if flags.contains(.maskCommand) { mods.append("⌘") }
        if flags.contains(.maskShift) { mods.append("⇧") }
        if flags.contains(.maskAlternate) { mods.append("⌥") }
        if flags.contains(.maskControl) { mods.append("⌃") }
        if flags.contains(.maskSecondaryFn) { mods.append("fn") }

        // 行尾不再解释「这行意味着什么」——每行都一样，纯噪声，
        // 该说明的放在顶部说明区讲一次。这里只对齐，方便扫读。
        let kind = type == .keyDown ? "keyDown     " : "flagsChanged"
        appendEvent("\(kind)  keyCode=\(String(format: "%3d", keyCode))  [\(mods.joined())]")
    }

    /// 带时间戳的事件行。键盘和手柄混在一起，靠时间对齐才看得出先后。
    private func appendEvent(_ line: String) {
        append("\(Self.timeFormatter.string(from: Date()))  \(line)")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func append(_ line: String) {
        guard !isPaused else { return }
        writeLine(line)
    }

    /// 无条件写入。工具栏自己的提示（已清空 / 已暂停）走这里——
    /// 否则暂停状态下连「已暂停」都写不进去。
    private func writeLine(_ line: String) {
        guard let textView, let storage = textView.textStorage else { return }

        // 增量追加，不要每次都 `textView.string = 全量`。
        // 后者是 O(n²)：按住键连发时几千行拼下来会卡住主线程，
        // 事件 tap 处理超时 → 系统发 tapDisabledByTimeout，
        // 追踪自己反而成了"按键失灵"的来源。
        let prefix = storage.length == 0 ? "" : "\n"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        storage.append(NSAttributedString(string: prefix + line, attributes: attributes))

        // 兜底上限：长时间开着不至于把内存吃光
        if storage.length > 200_000 {
            storage.deleteCharacters(in: NSRange(location: 0, length: 100_000))
        }

        textView.scrollToEndOfDocument(nil)
    }

    // MARK: - 工具栏

    @objc private func clearLog() {
        textView?.textStorage?.setAttributedString(NSAttributedString(string: ""))
        writeLine("— 已清空 —")
    }

    @objc private func togglePause() {
        setPaused(!isPaused)
    }

    private func setPaused(_ value: Bool, silent: Bool = false) {
        guard isPaused != value else { return }
        isPaused = value
        pauseButton?.title = value ? "继续" : "暂停"
        window?.title = value ? "按键追踪（已暂停）" : "按键追踪"
        guard !silent else { return }
        writeLine(value ? "— 已暂停：新事件不再记录 —" : "— 已继续 —")
    }
}

extension KeyTracePanel: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 只停追踪，**不要**在这里把 window / textView 置 nil。
        // 此刻 AppKit 还在走关闭流程，把窗口释放掉会让它后续访问悬垂指针
        // （和 isReleasedWhenClosed 那次崩溃是同一类问题）。
        // 窗口对象留着复用，下次 show() 直接 makeKeyAndOrderFront。
        stopTracing()
    }
}
