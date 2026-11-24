import Cocoa

/// 启动器面板的按键接管。
///
/// 面板是 `NSPanel`（`hidesOnDeactivate = false`）：用户点到别处时它仍在屏幕上，
/// 但已经失去键盘焦点，本地事件监听收不到按键。这个 tap 保证只要面板还显示着：
/// - `Esc` 一定能关掉它
/// - `←`/`→` 一定能翻页（光标在输入框两端时）
/// - `⌘1`–`⌘8` 一定能执行当前页对应项
///
/// 与 `CmdTabSwitcher` 的分工：那个只管 ⌘Tab 会话（按住 ⌘ 期间的网格导航），
/// 由「⌘Tab 接管」开关控制启停；这个只管面板自己的交互，跟随启动器启停。
/// 两者不合并——否则关掉 ⌘Tab 接管会连带让面板收不到 Esc。
final class LauncherPanelKeys {
    private lazy var tap = EventTap(
        name: "launcherPanel",
        events: .make([.keyDown])
    ) { [weak self] type, event in
        self?.handle(type: type, event: event)
    }

    func start() {
        tap.start()
    }

    func stop() {
        tap.stop()
    }

    // MARK: - 事件处理

    private func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        guard LauncherController.shared.isPanelVisible else { return event }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Esc：关闭面板
        if keyCode == 53 {
            DispatchQueue.main.async {
                LauncherController.shared.dismissPanel()
            }
            return nil
        }

        // 其余按键（左右翻页、⌘1-8）交给面板判断，未处理就放行给输入框。
        // tap 回调本身就跑在主线程，直接调用即可，不能用 main.sync 否则死锁。
        let handled = LauncherController.shared.handlePanelKey(
            keyCode: keyCode, flags: event.flags)
        return handled ? nil : event
    }
}
