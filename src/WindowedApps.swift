import AppKit
import CoreGraphics

/// 一个应用当前的运行状态
enum AppRuntimeState {
    case notRunning
    case running
    case runningWithWindow
}

enum WindowedApps {
    /// 屏幕上真正有窗口的应用，按窗口层级排序（最近使用在前）
    static func current() -> [AppEntry] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []

        var seen = Set<pid_t>()
        var entries: [AppEntry] = []

        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }
            guard seen.insert(pid).inserted else { continue }
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  let url = app.bundleURL else { continue }

            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            entries.append(AppEntry(name: name, bundleID: bundleID, url: url))
        }
        return entries
    }

    /// 所有正在运行、有图形界面的应用（含后台无窗口的）
    static func running() -> [AppEntry] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  let url = app.bundleURL else { return nil }
            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            return AppEntry(name: name, bundleID: bundleID, url: url)
        }
    }

    /// 默认结果：有窗口的排前面（按窗口层级），后台运行的按名称排在后面
    static func defaultEntries() -> [AppEntry] {
        let windowed = current()
        let windowedIDs = Set(windowed.map(\.bundleID))
        let background = running()
            .filter { !windowedIDs.contains($0.bundleID) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return windowed + background
    }
}
