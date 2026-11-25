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

    /// 切换后是否把鼠标移到目标窗口中心（配置项，默认关闭）。
    var mouseFollow = false

    /// 是否显示无窗口应用（配置项，默认开启）。
    var showWindowlessApps = true

    /// 应用配置（配置窗口改了设置后调用，下次弹出生效）
    func configure(mouseFollow: Bool, showWindowlessApps: Bool) {
        self.mouseFollow = mouseFollow
        self.showWindowlessApps = showWindowlessApps
    }

    private let activator = Activator()

    /// 最近使用的窗口，越靠前越新；用于「上一个窗口」的切换
    private static var mruOrder: [String] = []
    private static let mruLimit = 20

    private init() {}

    /// 当前真实的前台窗口标识。
    /// 用户可能通过点击等方式切换焦点，MRU 必须以此为准，否则默认选中会和实际窗口不一致。
    private static func frontmostWindowIdentity() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        guard app.activationPolicy == .regular || app.processIdentifier == selfPID else {
            return nil
        }

        let appName = app.localizedName ?? ""
        if app.processIdentifier == selfPID {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow
                    ?? NSApp.windows.first(where: { $0.isVisible && $0.level == .normal }) else {
                return nil
            }
            let rawTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = SwitcherItem.sanitize(title: rawTitle, appName: appName)
            return "\(bundleID)|\(title)"
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }

        let axWindow = unsafeBitCast(raw, to: AXUIElement.self)
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
        let rawTitle = (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = SwitcherItem.sanitize(title: rawTitle, appName: appName)
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

    @discardableResult
    func show() -> Bool {
        items = Self.buildItems(showWindowlessApps: showWindowlessApps)
        guard !items.isEmpty else { return false }

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
        return true
    }

    func hide() {
        isShown = false
        windows.forEach { $0.hide() }
        windows.removeAll()
    }

    /// 按固定区间决定行数，再按总数向上取整计算列数：
    /// 1-4 -> 1*x，5-10 -> 2*x，11-19 -> 3*x，20+ -> 4*x
    static func grid(for count: Int) -> (rows: Int, cols: Int) {
        guard count > 0 else { return (1, 3) }
        let targetRows: Int
        switch count {
        case 1...4: targetRows = 1
        case 5...10: targetRows = 2
        case 11...19: targetRows = 3
        default: targetRows = 4
        }
        let cols = (count + targetRows - 1) / targetRows
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
        guard let target = current else {
            hide()
            return
        }
        Self.remember(target)

        // 面板还是 key 的时候激活，否则系统会拒绝
        activator.activate(target.entry)
        hide()

        // 鼠标跟随是切换器的配置项，不再读全局 UserDefaults
        Activator.mouseFollowEnabled = mouseFollow

        if target.entry.bundleID == Bundle.main.bundleIdentifier {
            let targetTitle = target.windowTitle
            let match = NSApp.windows.first(where: { win in
                guard win.level == .normal, win.styleMask.contains(.titled),
                      win.isVisible || win.isMiniaturized else { return false }
                let sanitized = SwitcherItem.sanitize(
                    title: win.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    appName: target.entry.name)
                return targetTitle == nil || sanitized == targetTitle
            })
            if let match {
                if match.isMiniaturized { match.deminiaturize(nil) }
                NSApp.activate(ignoringOtherApps: true)
                match.makeKeyAndOrderFront(nil)
            }
            return
        }

        guard let element = target.window else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    /// 完全退出选中的无窗口应用。
    /// 退出后立即关闭面板：否则松开 ⌘ 触发 commit 会把刚退出的应用重新拉起。
    func quitSelected() {
        guard isVisible, let item = current, !item.hasWindow else { return }
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: item.entry.bundleID).first else {
            hide()
            return
        }

        app.terminate()
        hide()
    }

    func cancel() {
        guard isVisible else { return }
        hide()
    }

    // MARK: - 数据

    /// 正在运行的应用；多窗口应用展开成多个窗口项
    private static func buildItems(showWindowlessApps: Bool) -> [SwitcherItem] {
        let snapshot = WindowedApps.snapshot()
        let windowed = snapshot.entries
        let windowedIDs = Set(windowed.map(\.bundleID))
        let background = showWindowlessApps
            ? WindowedApps.running()
                .filter { !windowedIDs.contains($0.bundleID) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            : []

        var items: [SwitcherItem] = []

        let confirmedWindowPIDs = snapshot.confirmedWindowPIDs
        let otherSpaceWindowedIDs = windowedIDs
        let selfPID = ProcessInfo.processInfo.processIdentifier
        for entry in windowed + background {
            guard let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: entry.bundleID).first else {
                if showWindowlessApps {
                    items.append(SwitcherItem(entry: entry, window: nil,
                                              windowTitle: nil, hasWindow: false))
                }
                continue
            }

            if app.processIdentifier == selfPID {
                // 避免在主线程对自己发 AX IPC 导致阻塞，直接读 NSApp.windows
                let ownWindows = NSApp.windows.filter {
                    $0.level == .normal && $0.styleMask.contains(.titled)
                        && ($0.isVisible || $0.isMiniaturized)
                        && $0.frame.width > 1 && $0.frame.height > 1
                }
                for win in ownWindows {
                    let rawTitle = win.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = SwitcherItem.sanitize(title: rawTitle, appName: entry.name)
                    items.append(SwitcherItem(entry: entry, window: nil,
                                              windowTitle: title, hasWindow: true))
                }
                continue
            }

            let windows = WindowEnumerator.standardWindows(of: app.processIdentifier)

            if windows.isEmpty {
                // 若该进程在任意显示器上屏中、在其他 Space 处于原生全屏、或 `kAXMainWindow` 为标准窗口
                //（如非活跃 Space 上的 DBX），即使 `kAXWindows` 返回空也保持亮色。
                let hasOtherSpaceWindow = confirmedWindowPIDs.contains(app.processIdentifier)
                    || (otherSpaceWindowedIDs.contains(entry.bundleID)
                        && WindowEnumerator.hasStandardMainWindow(of: app.processIdentifier))
                if hasOtherSpaceWindow {
                    items.append(SwitcherItem(entry: entry, window: nil,
                                              windowTitle: nil, hasWindow: true))
                } else if showWindowlessApps {
                    items.append(SwitcherItem(entry: entry, window: nil,
                                              windowTitle: nil, hasWindow: false))
                }
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

        // 清掉已经不存在的窗口，避免占用名次；
        // 对位于其他 Space 的应用（AX 取不到标题，windowTitle == nil），保留其既有 MRU 记录。
        let existing = Set(items.map(\.identity))
        let offscreenBundleIDs = Set(
            items.filter { $0.hasWindow && $0.windowTitle == nil }.map(\.entry.bundleID)
        )
        mruOrder = mruOrder.filter { key in
            if existing.contains(key) { return true }
            if let sep = key.firstIndex(of: "|") {
                return offscreenBundleIDs.contains(String(key[..<sep]))
            }
            return false
        }

        // 无窗口的应用始终排在末尾：窗口列表来自 AX，
        // 而 CGWindowList 可能把只剩隐藏窗口的应用算作「有窗口」，导致它混在中间
        let ordered = sortByMRU(items)
        var result: [SwitcherItem] = []
        result.reserveCapacity(ordered.count)
        result.append(contentsOf: ordered.filter(\.hasWindow))
        result.append(contentsOf: ordered.filter { !$0.hasWindow })
        return result
    }

    /// 按最近使用排序，保证「上一个窗口」稳定落在第二位
    private static func sortByMRU(_ items: [SwitcherItem]) -> [SwitcherItem] {
        guard !mruOrder.isEmpty else { return items }

        var rank: [String: Int] = [:]
        var bundleBestRank: [String: Int] = [:]
        for (index, key) in mruOrder.enumerated() {
            rank[key] = index
            if let sep = key.firstIndex(of: "|") {
                let bundleID = String(key[..<sep])
                if bundleBestRank[bundleID] == nil {
                    bundleBestRank[bundleID] = index
                }
            }
        }

        return items.enumerated().sorted { left, right in
            let leftRank = rank[left.element.identity]
                ?? (left.element.hasWindow && left.element.windowTitle == nil
                    ? bundleBestRank[left.element.entry.bundleID] : nil)
                ?? Int.max
            let rightRank = rank[right.element.identity]
                ?? (right.element.hasWindow && right.element.windowTitle == nil
                    ? bundleBestRank[right.element.entry.bundleID] : nil)
                ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return left.offset < right.offset
        }.map(\.element)
    }
}
