import AppKit
import ApplicationServices

/// 切换器里的一项：应用本身，或它的某一个窗口
struct SwitcherItem {
    let entry: AppEntry
    let window: AXUIElement?
    let windowTitle: String?
    let hasWindow: Bool

    /// 用于 MRU 历史的稳定标识
    var identity: String {
        "\(entry.bundleID)|\(windowTitle ?? "")"
    }

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

/// ⌘Tab 切换器：所有显示器各一个面板，共享同一份状态
final class SwitcherController {
    static let shared = SwitcherController()

    private var windows: [SwitcherWindow] = []
    private var items: [SwitcherItem] = []
    private var selected = 0
    private var rows = 1
    private var cols = 1
    private var isShown = false

    private let activator = Activator()

    /// 最近使用的窗口，越靠前越新；用于「上一个窗口」的切换
    private static var mruOrder: [String] = []
    private static let mruLimit = 20

    private init() {}

    /// 当前真实的前台窗口标识。
    /// 用户可能通过点击等方式切换焦点，MRU 必须以此为准，否则默认选中会和实际窗口不一致。
    private static func frontmostWindowIdentity() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let raw = value else { return nil }

        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(raw as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
        let rawTitle = (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let appName = app.localizedName ?? ""
        let title = SwitcherItem.sanitize(title: rawTitle.isEmpty ? "未命名窗口" : rawTitle,
                                          appName: appName)
        return "\(bundleID)|\(title)"
    }

    private static func remember(_ item: SwitcherItem) {
        let key = item.identity
        mruOrder.removeAll { $0 == key }
        mruOrder.insert(key, at: 0)
        if mruOrder.count > mruLimit {
            mruOrder.removeLast(mruOrder.count - mruLimit)
        }
    }

    var isVisible: Bool {
        isShown && windows.contains { $0.isVisible }
    }

    // MARK: - 展示

    func show() {
        items = Self.buildItems()
        guard !items.isEmpty else { return }

        (rows, cols) = Self.grid(for: items.count)
        // 与系统切换器一致：初次弹出选中第二个，第一个通常是当前应用
        selected = items.count > 1 ? 1 : 0
        isShown = true

        windows.forEach { $0.hide() }
        windows = NSScreen.screens.map { SwitcherWindow(screen: $0) }
        for window in windows {
            window.present(items: items, rows: rows, cols: cols, selected: selected)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        for window in windows.dropFirst() {
            window.orderFrontRegardless()
        }
    }

    func hide() {
        isShown = false
        windows.forEach { $0.hide() }
        windows.removeAll()
    }

    /// 竖向 x 行、横向 x+2 列，取最小的 x 容纳全部磁贴
    static func grid(for count: Int) -> (rows: Int, cols: Int) {
        guard count > 0 else { return (1, 3) }
        var x = 1
        while x * (x + 2) < count { x += 1 }
        let cols = x + 2
        let rows = (count + cols - 1) / cols
        return (rows, cols)
    }

    // MARK: - 导航

    /// 某个格子的一维下标；该列在该行不存在时回退到该行最后一个
    private func index(row: Int, column: Int) -> Int? {
        let start = row * cols
        guard start < items.count else { return nil }
        let end = min(start + cols, items.count) - 1
        return min(start + column, end)
    }

    private func applySelection() {
        for window in windows {
            window.updateSelection(selected)
        }
    }

    /// 横向移动：按阅读顺序，行末接下一行行首
    func moveHorizontal(by delta: Int) {
        guard isVisible, !items.isEmpty else { return }
        let row = selected / cols
        let rowStart = row * cols
        let rowEnd = min(rowStart + cols, items.count) - 1

        if delta > 0 {
            if selected < rowEnd {
                selected += 1
            } else {
                let nextStart = rowEnd + 1
                selected = nextStart < items.count ? nextStart : 0
            }
        } else {
            if selected > rowStart {
                selected -= 1
            } else if rowStart > 0 {
                let prevStart = (row - 1) * cols
                selected = min(prevStart + cols, items.count) - 1
            } else {
                selected = items.count - 1
            }
        }
        applySelection()
    }

    /// 纵向移动：同列跨行；该列在目标行不存在时落到目标行末尾
    func moveVertical(by delta: Int) {
        guard isVisible, !items.isEmpty else { return }
        let row = selected / cols
        let column = selected % cols
        let totalRows = (items.count + cols - 1) / cols

        var targetRow = row + (delta > 0 ? 1 : -1)
        if targetRow < 0 { targetRow = totalRows - 1 }
        if targetRow >= totalRows { targetRow = 0 }

        if let target = index(row: targetRow, column: column) {
            selected = target
        }
        applySelection()
    }

    /// Tab 顺序前进/后退
    func moveSequential(by delta: Int) {
        guard isVisible, !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
        applySelection()
    }

    // MARK: - 执行

    var current: SwitcherItem? {
        items.indices.contains(selected) ? items[selected] : nil
    }

    func commit() {
        guard isVisible else { return }
        let target = current
        hide()
        guard let target else { return }
        Self.remember(target)

        guard let element = target.window else {
            // 无窗口：复用启动器的逻辑，reopen 无效时补 ⌘N 让应用自己开窗
            activator.activate(target.entry)
            return
        }

        // 有窗口：先激活应用，再抬升具体窗口
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: target.entry.bundleID).first {
            running.activate(options: [.activateIgnoringOtherApps])
        } else {
            activator.activate(target.entry)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    func cancel() {
        guard isVisible else { return }
        hide()
    }

    // MARK: - 数据

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

            if windows.isEmpty {
                items.append(SwitcherItem(entry: entry, window: nil,
                                          windowTitle: nil, hasWindow: false))
            } else {
                // 平铺：每个窗口一个磁贴
                for info in windows {
                    let title = SwitcherItem.sanitize(title: info.title, appName: entry.name)
                    items.append(SwitcherItem(entry: entry, window: info.element,
                                              windowTitle: title, hasWindow: true))
                }
            }
        }

        // 以真实前台窗口为 MRU 首位，保证「上一个窗口」准确
        if let front = frontmostWindowIdentity() {
            mruOrder.removeAll { $0 == front }
            mruOrder.insert(front, at: 0)
        }

        // 清掉已经不存在的窗口，避免占用名次
        let existing = Set(items.map(\.identity))
        mruOrder = mruOrder.filter { existing.contains($0) }

        return sortByMRU(items)
    }

    /// 按最近使用排序，保证「上一个窗口」稳定落在第二位
    private static func sortByMRU(_ items: [SwitcherItem]) -> [SwitcherItem] {
        guard !mruOrder.isEmpty else { return items }

        var rank: [String: Int] = [:]
        for (index, key) in mruOrder.enumerated() {
            rank[key] = index
        }

        return items.enumerated().sorted { left, right in
            let leftRank = rank[left.element.identity] ?? Int.max
            let rightRank = rank[right.element.identity] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return left.offset < right.offset
        }.map(\.element)
    }
}
