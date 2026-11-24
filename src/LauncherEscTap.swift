import Cocoa

/// 面板可见期间全局接收按键。
///
/// 面板可能因为别的应用抢焦点而失去键盘焦点，此时本地监听收不到按键，
/// 这个 tap 保证只要面板还显示着，Esc 一定能关掉它、左右键一定能翻页。
///
/// 创建/重试/禁用恢复/录制放行都由 `EventTap` 统一处理。
final class LauncherEscTap {
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
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard LauncherController.shared.isPanelVisible else { return event }

        // Esc：关闭面板
        if keyCode == 53 {
            DispatchQueue.main.async {
                LauncherController.shared.cancelSwitcher()
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
