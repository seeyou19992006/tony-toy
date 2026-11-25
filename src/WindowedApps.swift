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

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: UInt32) -> CFArray?

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(
    _ cid: UInt32, _ mask: UInt32, _ windowIDs: CFArray
) -> CFArray?

enum WindowedApps {
    private static let allSpacesMask: UInt32 = 0x7

    struct WindowSnapshot {
        let entries: [AppEntry]
        /// 在任意显示器上屏中，或在其他 Space 处于原生全屏的进程 PID
        let confirmedWindowPIDs: Set<pid_t>
    }

    /// 屏幕上以及其它 Space（含原生全屏）真正有窗口的应用，按窗口层级排序（最近使用在前）
    static func current() -> [AppEntry] {
        snapshot().entries
    }

    /// 单次扫描同时产出有窗口应用列表与「可见/全屏进程 PID」，避免切换器重复扫描 CGWindowList。
    static func snapshot() -> WindowSnapshot {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let cid = CGSMainConnectionID()
        let activeSpaces = currentActiveSpaceIDs(cid: cid)
        let screenSizes = NSScreen.screens.map(\.frame.size)
        let selfPID = ProcessInfo.processInfo.processIdentifier

        var seen = Set<pid_t>()
        var axChecked = [pid_t: Bool]()
        var entries: [AppEntry] = []
        var confirmedWindowPIDs = Set<pid_t>()

        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }

            let isOnscreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
            var isConfirmedVisibleOrFullscreen = isOnscreen

            if !isOnscreen {
                guard let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                      let spaces = CGSCopySpacesForWindows(
                          cid, allSpacesMask, [windowNumber] as CFArray) as? [UInt64],
                      !spaces.isEmpty else { continue }

                // 位于当前 Space 但未上屏的通常是系统/应用隐藏的辅助窗；只有跨 Space 才继续判定
                let onOtherSpace = !Set(spaces).subtracting(activeSpaces).isEmpty
                guard onOtherSpace else { continue }

                let matchesScreen = matchesAnyScreenFrame(info: info, screenSizes: screenSizes)
                isConfirmedVisibleOrFullscreen = matchesScreen
                if !matchesScreen && !seen.contains(pid) {
                    let hasAXWindow: Bool
                    if let cached = axChecked[pid] {
                        hasAXWindow = cached
                    } else {
                        let found = pid == selfPID
                            ? hasOwnStandardWindow()
                            : (!WindowEnumerator.standardWindows(of: pid).isEmpty
                                || WindowEnumerator.hasStandardMainWindow(of: pid))
                        axChecked[pid] = found
                        hasAXWindow = found
                    }
                    guard hasAXWindow else { continue }
                }
            }

            if isConfirmedVisibleOrFullscreen {
                confirmedWindowPIDs.insert(pid)
            }

            guard !seen.contains(pid),
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular || pid == selfPID,
                  let bundleID = app.bundleIdentifier,
                  let url = app.bundleURL else { continue }

            seen.insert(pid)
            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            entries.append(AppEntry(name: name, bundleID: bundleID, url: url))
        }

        return WindowSnapshot(entries: entries, confirmedWindowPIDs: confirmedWindowPIDs)
    }

    private static func currentActiveSpaceIDs(cid: UInt32) -> Set<UInt64> {
        let displays = (CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]]) ?? []
        var active = Set<UInt64>()
        for display in displays {
            if let current = display["Current Space"] as? [String: Any],
               let id = (current["id64"] as? NSNumber)?.uint64Value {
                active.insert(id)
            }
        }
        return active
    }

    private static func matchesAnyScreenFrame(info: [String: Any], screenSizes: [CGSize]) -> Bool {
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let width = (bounds["Width"] as? NSNumber)?.doubleValue,
              let height = (bounds["Height"] as? NSNumber)?.doubleValue else { return false }
        return screenSizes.contains {
            abs($0.width - width) <= 2 && abs($0.height - height) <= 2
        }
    }

    private static func hasOwnStandardWindow() -> Bool {
        NSApp.windows.contains {
            $0.level == .normal && $0.styleMask.contains(.titled)
                && ($0.isVisible || $0.isMiniaturized)
                && $0.frame.width > 1 && $0.frame.height > 1
        }
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
