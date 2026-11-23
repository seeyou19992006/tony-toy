import Cocoa

/// ⌘Tab 切换器：独立的二维网格窗口，只显示正在运行、有界面的应用
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
        let items = Self.runningEntries()
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
        if let target {
            activator.activate(target)
        }
    }

    func cancel() {
        guard isVisible else { return }
        isShown = false
        window.hide()
    }

    /// 正在运行且有界面的应用，按窗口层级（最近使用）优先
    private static func runningEntries() -> [AppEntry] {
        let windowed = WindowedApps.current()
        let windowedIDs = Set(windowed.map(\.bundleID))
        let background = WindowedApps.running()
            .filter { !windowedIDs.contains($0.bundleID) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return windowed + background
    }
}
