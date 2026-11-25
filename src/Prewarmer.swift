import AppKit
import ApplicationServices

/// 后台预热：把「首次调用」的开销从 ⌘Tab 弹出时刻提前到启动阶段
enum Prewarmer {
    private static var installed = false

    static func start() {
        guard !installed else { return }
        installed = true

        // 应用启动/退出后重新预热，保证列表和连接都是热的
        let center = NotificationCenter.default
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                warm()
            }
        }

        warm()
    }

    static func warm() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        DispatchQueue.global(qos: .utility).async {
            // 1. 窗口服务器连接
            _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                           kCGNullWindowID)

            // 2. 每个应用的辅助功能连接
            for app in apps {
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(axApp, 0.25)
                var value: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
            }

            // 3. 仅预热有窗口应用的彩色图标，避免为所有后台应用提前生成灰度位图
            let windowed = Set(WindowedApps.current().map(\.bundleID))
            for app in apps {
                guard let bundleID = app.bundleIdentifier,
                      windowed.contains(bundleID),
                      let url = app.bundleURL else { continue }
                let entry = AppEntry(name: app.localizedName ?? bundleID,
                                     bundleID: bundleID, url: url)
                _ = IconCache.icon(for: entry, gray: false)
            }
        }
    }
}
