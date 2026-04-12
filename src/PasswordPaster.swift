import Foundation
import AppKit
import Carbon

/// 密码粘贴服务 - 复制到剪贴板并模拟 Cmd+V
class PasswordPaster {
    /// 复制密码到剪贴板并自动粘贴
    static func paste(password: String) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        // 写入密码
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)

        // 模拟 Cmd+V
        simulateCmdV()

        // 延迟后恢复原剪贴板
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    /// 模拟 Cmd+V 键盘事件 - 使用 CGEventCreateKeyboardEvent
    private static func simulateCmdV() {
        print("📋 PasswordPaster: 发送 Cmd+V 事件")

        // 使用 nil source 让系统选择
        let source: CGEventSource? = nil

        // Cmd+V - 使用 CGEventCreateKeyboardEvent
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true) else {
            print("❌ cmdDown 失败")
            return
        }
        cmdDown.flags = .maskCommand

        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) else {
            print("❌ vDown 失败")
            return
        }
        vDown.flags = .maskCommand

        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            print("❌ vUp 失败")
            return
        }

        guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else {
            print("❌ cmdUp 失败")
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

        print("✅ PasswordPaster: Cmd+V 发送完成")
    }
}
