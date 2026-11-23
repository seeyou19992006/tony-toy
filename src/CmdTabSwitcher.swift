import Foundation
import Cocoa

/// 接管 ⌘Tab：按下时呼出启动器，按住 ⌘ 期间循环选择，松开 ⌘ 执行选中项
final class CmdTabSwitcher {
    private var eventTap: CFMachPort?
    private var isActive = false
    private var retryCount = 0

    private let tabKeyCode: Int64 = 48
    private let escKeyCode: Int64 = 53
    private let returnKeyCode: Int64 = 36
    private let leftKeyCode: Int64 = 123
    private let rightKeyCode: Int64 = 124
    private let downKeyCode: Int64 = 125
    private let upKeyCode: Int64 = 126
    // 字母导航：E 上、D 下、S 左、F 右
    private let eKeyCode: Int64 = 14
    private let dKeyCode: Int64 = 2
    private let sKeyCode: Int64 = 1
    private let fKeyCode: Int64 = 3

    func start() {
        stop()
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                let switcher = Unmanaged<CmdTabSwitcher>.fromOpaque(refcon!).takeUnretainedValue()
                return switcher.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            retryCount += 1
            dbg("cmdtap failed retry=\(retryCount)")
            if retryCount <= 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.start()
                }
            }
            return
        }
        retryCount = 0
        dbg("cmdtap created")
        eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        isActive = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // ⌘Tab：第一次呼出，之后在列表里循环
        if type == .keyDown, keyCode == tabKeyCode, flags.contains(.maskCommand) {
            let backward = flags.contains(.maskShift)
            if !isActive {
                isActive = true
                DispatchQueue.main.async {
                    SwitcherController.shared.show()
                }
            } else {
                DispatchQueue.main.async {
                    SwitcherController.shared.moveSequential(by: backward ? -1 : 1)
                }
            }
            return nil
        }

        // 松开 ⌘：执行选中项
        if type == .flagsChanged, isActive, !flags.contains(.maskCommand) {
            isActive = false
            DispatchQueue.main.async {
                SwitcherController.shared.commit()
            }
            return Unmanaged.passUnretained(event)
        }

        // 按住 ⌘ 期间：方向键或 E/D/S/F 导航，全部吞掉避免提示音
        if type == .keyDown, isActive {
            switch keyCode {
            case escKeyCode:
                isActive = false
                DispatchQueue.main.async { SwitcherController.shared.cancel() }
                return nil
            case returnKeyCode:
                isActive = false
                DispatchQueue.main.async { SwitcherController.shared.commit() }
                return nil
            case leftKeyCode, sKeyCode:
                DispatchQueue.main.async { SwitcherController.shared.moveHorizontal(by: -1) }
                return nil
            case rightKeyCode, fKeyCode:
                DispatchQueue.main.async { SwitcherController.shared.moveHorizontal(by: 1) }
                return nil
            case upKeyCode, eKeyCode:
                DispatchQueue.main.async { SwitcherController.shared.moveVertical(by: -1) }
                return nil
            case downKeyCode, dKeyCode:
                DispatchQueue.main.async { SwitcherController.shared.moveVertical(by: 1) }
                return nil
            default:
                // 其它按键放行，交给 Caps 层映射（Caps+E/D/S/F → 方向键）
                break
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
