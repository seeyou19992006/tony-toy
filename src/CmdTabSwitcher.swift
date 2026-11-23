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
                    LauncherController.shared.beginSwitcher()
                }
            } else {
                DispatchQueue.main.async {
                    LauncherController.shared.moveSwitcherSelection(by: backward ? -1 : 1)
                }
            }
            return nil
        }

        // 松开 ⌘：执行选中项
        if type == .flagsChanged, isActive, !flags.contains(.maskCommand) {
            isActive = false
            DispatchQueue.main.async {
                LauncherController.shared.commitSwitcher()
            }
            return Unmanaged.passUnretained(event)
        }

        if keyCode == 53 {
            dbg("cmdtab sees esc: active=\(isActive)")
        }

        // 按住 ⌘ 时 Esc 取消、回车直接执行
        if type == .keyDown, isActive {
            if keyCode == escKeyCode {
                isActive = false
                DispatchQueue.main.async {
                    LauncherController.shared.cancelSwitcher()
                }
                return nil
            }
            if keyCode == returnKeyCode {
                isActive = false
                DispatchQueue.main.async {
                    LauncherController.shared.commitSwitcher()
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
