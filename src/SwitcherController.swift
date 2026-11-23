import AppKit
import ApplicationServices

/// 切换器里的一项：应用本身，或它的某一个窗口
struct SwitcherItem {
    let entry: AppEntry
    let window: AXUIElement?
    let windowTitle: String?
    let hasWindow: Bool

    /// 磁贴下的小字
    var displayTitle: String {
        windowTitle ?? entry.name
    }

    /// 顶部标题栏：应用名 + 窗口标题
    var fullTitle: String {
        guard let windowTitle, windowTitle != entry.name else { return entry.name }
        return "\(entry.name) — \(windowTitle)"
    }

    /// 去掉窗口标题里重复的应用名。
    /// Chrome 这类浏览器会在标题末尾追加「 - Google Chrome」，顶部标题栏又加了一次应用名。
    static func sanitize(title: String, appName: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)

        for separator in [" - ", " — ", " – ", " | "] {
            let suffix = separator + appName
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                break
            }
            let prefix = appName + separator
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? appName : result
    }
}

/// ⌘Tab 切换器：独立的二维网格窗口
final class SwitcherController {
    static let shared = SwitcherController()

    private let window = SwitcherWindow()
    private let activator = Activator()
    private var isShown = false

    private init() {}

    var isVisible: Bool {
        isShown && window.isVisible
    }

    func show() {
        let items = Self.buildItems()
        guard !items.isEmpty else { return }
        isShown = true
        window.show(items: items)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func moveHorizontal(by delta: Int) {
        guard isVisible else { return }
        window.moveHorizontal(by: delta)
    }

    func moveVertical(by delta: Int) {
        guard isVisible else { return }
        window.moveVertical(by: delta)
    }

    func moveSequential(by delta: Int) {
        guard isVisible else { return }
        window.moveSequential(by: delta)
    }

    func commit() {
        guard isVisible else { return }
        let target = window.current
        isShown = false
        window.hide()
        guard let target else { return }

        // 先激活应用，再抬升具体窗口
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: target.entry.bundleID).first {
            running.activate(options: [.activateIgnoringOtherApps])
        } else {
            activator.activate(target.entry)
        }

        guard let element = target.window else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    func cancel() {
        guard isVisible else { return }
        isShown = false
        window.hide()
    }

    /// 正在运行的应用；多窗口应用展开成多个窗口项
    private static func buildItems() -> [SwitcherItem] {
        let windowed = WindowedApps.current()
        let windowedIDs = Set(windowed.map(\.bundleID))
        let background = WindowedApps.running()
            .filter { !windowedIDs.contains($0.bundleID) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var items: [SwitcherItem] = []

        for entry in windowed + background {
            guard let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: entry.bundleID).first else {
                items.append(SwitcherItem(entry: entry, window: nil,
                                          windowTitle: nil, hasWindow: false))
                continue
            }

            let windows = WindowEnumerator.standardWindows(of: app.processIdentifier)

            if windows.count > 1 {
                // 平铺：每个窗口一个磁贴
                for info in windows {
                    let title = SwitcherItem.sanitize(title: info.title, appName: entry.name)
                    items.append(SwitcherItem(entry: entry, window: info.element,
                                              windowTitle: title, hasWindow: true))
                }
            } else if let info = windows.first {
                let title = SwitcherItem.sanitize(title: info.title, appName: entry.name)
                items.append(SwitcherItem(entry: entry, window: info.element,
                                          windowTitle: title, hasWindow: true))
            } else {
                items.append(SwitcherItem(entry: entry, window: nil,
                                          windowTitle: nil, hasWindow: false))
            }
        }

        return items
    }
}
