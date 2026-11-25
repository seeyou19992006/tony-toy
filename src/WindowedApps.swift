import AppKit
import CoreGraphics

/// 一个应用当前的运行状态
enum AppRuntimeState {
    case notRunning
    case running
    case runningWithWindow
}

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(
    _ cid: UInt32, _ mask: UInt32, _ windowIDs: CFArray
) -> CFArray?

enum WindowedApps {
    private static let allSpacesMask: UInt32 = 0x7

    /// 屏幕上以及其它 Space（含原生全屏）真正有窗口的应用，按窗口层级排序（最近使用在前）
    static func current() -> [AppEntry] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let cid = CGSMainConnectionID()
        let selfPID = ProcessInfo.processInfo.processIdentifier

        var seen = Set<pid_t>()
        var entries: [AppEntry] = []

        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }
            guard !seen.contains(pid) else { continue }

            let isOnscreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
            if !isOnscreen {
                guard let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                      windowBelongsToAnySpace(cid: cid, windowNumber: windowNumber) else { continue }
            }

            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular || pid == selfPID,
                  let bundleID = app.bundleIdentifier,
                  let url = app.bundleURL else { continue }

            seen.insert(pid)
            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            entries.append(AppEntry(name: name, bundleID: bundleID, url: url))
        }

        return entries
    }

    /// 菜单栏条（1920×30）、图标窗及未上屏的隐藏辅助窗口不属于任何 Space；
    /// 真实窗口（无论大小，含全屏与跨桌面窗口）均绑定到至少一个 Space ID。
    private static func windowBelongsToAnySpace(cid: UInt32, windowNumber: Int) -> Bool {
        let spaces = CGSCopySpacesForWindows(cid, allSpacesMask, [windowNumber] as CFArray) as? [UInt64]
        return !(spaces?.isEmpty ?? true)
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
