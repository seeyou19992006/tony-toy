import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

/// 把选中的应用带到前台；有窗口则抬升，没窗口则发 reopen 事件让它自己开窗
final class Activator {
    func activate(_ entry: AppEntry) {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleID).first else {
            openApplication(entry)
            return
        }

        if hasVisibleWindows(pid: running.processIdentifier) {
            running.activate(options: [.activateIgnoringOtherApps])
            raiseFrontWindow(of: running.processIdentifier)
        } else {
            // 后台运行但窗口已关：走 reopen，等价于点 Dock 图标
            if !sendReopenEvent(bundleID: running.bundleIdentifier) {
                running.activate(options: [.activateIgnoringOtherApps])
                openApplication(entry)
            }
        }
    }

    private func openApplication(_ entry: AppEntry) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.environment = cleanEnvironment()
        NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration) { _, error in
            if let error {
                NSLog("启动应用失败: \(error.localizedDescription)")
            }
        }
    }

    /// 不把自己进程里的终端相关变量传给被启动的应用：
    /// 若启动器本身是从终端起来的，TERM=dumb 之类的值会让新开的终端里 htop 退回 ASCII 绘图
    private func cleanEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let terminalKeys = ["TERM", "TERMINFO", "TERMINFO_DIRS", "TERM_PROGRAM",
                            "TERM_PROGRAM_VERSION", "COLORTERM", "TERM_SESSION_ID"]
        for key in terminalKeys {
            environment.removeValue(forKey: key)
        }
        return environment
    }

    /// 发送 kAEReopenApplication，触发应用的 applicationShouldHandleReopen
    private func sendReopenEvent(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)

        let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kCoreEventClass),
                                                      eventID: AEEventID(kAEReopenApplication),
                                                      targetDescriptor: target,
                                                      returnID: AEReturnID(kAutoGenerateReturnID),
                                                      transactionID: AETransactionID(kAnyTransactionID))
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 2)
            return true
        } catch {
            NSLog("reopen 事件发送失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 用窗口列表判断，不依赖辅助功能权限
    private func hasVisibleWindows(pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }
    }

    /// 辅助功能权限可选：没授权时跳过，activate 已能把最近的窗口带出来
    private func raiseFrontWindow(of pid: pid_t) {
        guard AXIsProcessTrusted() else { return }

        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        guard result == .success,
              let windows = value as? [AXUIElement],
              let frontWindow = windows.first else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            AXUIElementPerformAction(frontWindow, kAXRaiseAction as CFString)
        }
    }
}
