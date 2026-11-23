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
            // 有窗口：在调用方隐藏面板之前激活，否则系统拒绝跨应用激活
            running.activate(options: [])
            raiseFrontWindow(of: running.processIdentifier)
            return
        }

        // 无窗口：走 LaunchServices 激活。它不依赖本进程是否为活动应用，
        // 而 NSRunningApplication.activate 在面板隐藏后会被系统拒绝。
        openApplication(entry)

        // 有些应用（Finder、部分系统应用）激活后不会自己开窗，补一个 ⌘N。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.hasVisibleWindows(pid: running.processIdentifier) else { return }
            self.sendNewWindowShortcut(pid: running.processIdentifier)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.focusFrontWindow(of: running.processIdentifier)
            }
        }
    }

    /// 把键盘焦点显式给到该应用最前面的窗口
    private func focusFrontWindow(of pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let front = windows.first else { return }

        // 未最小化 + 设为主窗口 + 抬升，三步都要，否则只是画出来但没焦点
        AXUIElementSetAttributeValue(front, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(axApp, kAXMainWindowAttribute as CFString, front)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, front)
        AXUIElementPerformAction(front, kAXRaiseAction as CFString)
    }

    /// 给目标应用发 ⌘N，让有文档模型的应用自己开一个窗口
    private func sendNewWindowShortcut(pid: pid_t) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyCode: CGKeyCode = 45  // N
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.postToPid(pid)
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
