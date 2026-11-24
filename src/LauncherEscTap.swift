import Foundation
import Cocoa

/// 面板可见期间全局接收 Esc。
/// 面板可能因为别的应用抢焦点而失去键盘焦点，此时本地监听收不到 Esc，
/// 这个 tap 保证只要面板还显示着，Esc 就一定能把它关掉。
final class LauncherEscTap {
    private var eventTap: CFMachPort?
    private var retryCount = 0

    func start() {
        stop()
        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let monitor = Unmanaged<LauncherEscTap>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            retryCount += 1
            if retryCount <= 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.start()
                }
            }
            return
        }
        retryCount = 0
        eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard LauncherController.shared.isPanelVisible else {
            return Unmanaged.passUnretained(event)
        }

        // Esc：关闭面板
        if keyCode == 53 {
            DispatchQueue.main.async {
                LauncherController.shared.cancelSwitcher()
            }
            return nil
        }

        // 其余按键（左右翻页、⌘1-8）交给面板判断，未处理就放行给输入框。
        // tap 回调本身就跑在主线程，直接调用即可，不能用 main.sync 否则死锁。
        let handled = LauncherController.shared.handlePanelKey(keyCode: keyCode, flags: event.flags)
        return handled ? nil : Unmanaged.passUnretained(event)
    }
}
