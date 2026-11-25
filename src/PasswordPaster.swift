import Foundation
import AppKit
import Carbon

/// 密码粘贴服务 - 复制到剪贴板并模拟 Cmd+V
class PasswordPaster {
    /// 复制密码后延迟清除剪贴板的秒数（由 PasswordVaultFeature 同步配置）
    static var clearDelaySeconds: TimeInterval = 30
    private static var clearGeneration: UInt64 = 0

    /// 复制密码到剪贴板并自动粘贴
    static func paste(password: String) {
        let pasteboard = NSPasteboard.general

        // 写入密码
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)

        // 模拟 Cmd+V
        simulateCmdV()

        // 延迟清除剪贴板：仅当剪贴板内容仍是本次写入的密码时才清空，避免误删用户后续复制的内容
        clearGeneration &+= 1
        let generation = clearGeneration
        let delay = max(1, clearDelaySeconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard clearGeneration == generation else { return }
            if pasteboard.string(forType: .string) == password {
                pasteboard.clearContents()
            }
        }
    }

    /// 模拟 Cmd+V 键盘事件 - 使用 CGEventCreateKeyboardEvent
    private static func simulateCmdV() {
        dbg("PasswordPaster: 发送 Cmd+V 事件")

        // 使用 nil source 让系统选择
        let source: CGEventSource? = nil

        // Cmd+V - 使用 CGEventCreateKeyboardEvent
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true) else {
            dbg("PasswordPaster: cmdDown 失败")
            return
        }
        cmdDown.flags = .maskCommand

        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) else {
            dbg("PasswordPaster: vDown 失败")
            return
        }
        vDown.flags = .maskCommand

        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            dbg("PasswordPaster: vUp 失败")
            return
        }

        guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else {
            dbg("PasswordPaster: cmdUp 失败")
            return
        }

        // 发送到 HID 事件 tap
        cmdDown.post(tap: .cghidEventTap)
        usleep(10000)
        vDown.post(tap: .cghidEventTap)
        usleep(10000)
        vUp.post(tap: .cghidEventTap)
        usleep(10000)
        cmdUp.post(tap: .cghidEventTap)

        dbg("PasswordPaster: Cmd+V 发送完成")
    }
}
