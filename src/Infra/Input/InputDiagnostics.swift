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
/// 用一个独立的 `listenOnly` tap 观察事件——它不消费、不修改，
/// 能看到「事件是否产生」，但看不到「被哪个 tap 消费」
/// （CGEvent 层没有这种 API）。配合 `InputRegistry` 的监听器列表，
/// 可以推断出是哪一个。
final class KeyTracePanel: NSObject {
    private var window: NSWindow?
    private var textView: NSTextView?
    private var observer: EventTap?

    /// 是否正在追踪
    private(set) var isTracing = false

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "按键追踪"
        window.center()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView()
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        window.contentView = scrollView

        self.window = window
        self.textView = textView

        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startTracing()
    }

    // MARK: - 追踪

    func startTracing() {
        guard !isTracing else { return }
        isTracing = true

        append("=== 开始追踪（按任意键查看）===")
        append("这里显示的是「系统层是否存在该事件」。")
        append("如果某个键在这里有记录、但应用没反应，说明它被上游 tap 消费了。")
        append("")

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
    }

    func stopTracing() {
        observer?.stop()
        observer = nil
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

        let kind = type == .keyDown ? "keyDown" : "flagsChanged"
        let suffix = type == .keyDown ? "  ← 系统层有这个事件" : ""
        append("\(kind)  keyCode=\(keyCode)  [\(mods.joined())]\(suffix)")
    }

    private func append(_ line: String) {
        guard let textView else { return }
        let text = textView.string.isEmpty ? line : textView.string + "\n" + line
        textView.string = text
        textView.scrollToEndOfDocument(nil)
    }
}

extension KeyTracePanel: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopTracing()
        window = nil
        textView = nil
    }
}
