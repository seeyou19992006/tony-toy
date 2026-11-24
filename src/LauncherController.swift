import Cocoa

/// 应用启动器：只搜应用，回车切到该应用最近使用的窗口
final class LauncherController {
    static let shared = LauncherController()

    private let index = AppIndex()
    private let activator = Activator()
    private let hotkey = LauncherHotkeyManager()
    private let escTap = LauncherEscTap()
    private var palette: PaletteWindow?

    private init() {}

    func start() {
        dbg("launcher start begin")
        index.scan()
        dbg("launcher scan done entries=\(index.entries.count)")

        palette = PaletteWindow(index: index) { [weak self] entry in
            self?.activator.activate(entry)
        }

        escTap.start()

        let registered = hotkey.register(LauncherSettings.selectedHotkey) { [weak self] in
            self?.show()
        }
        dbg("launcher hotkey registered=\(registered) key=\(LauncherSettings.selectedHotkey.title)")
        if !registered {
            NSLog("launcher hotkey register failed: \(LauncherSettings.selectedHotkey.title)")
        }
    }

    /// 面板当前是否可见，供 Caps 层判断是否放行 Esc
    var isPanelVisible: Bool {
        palette?.isVisible ?? false
    }

    /// 把按键交给面板处理；返回 true 表示已消费
    func handlePanelKey(keyCode: Int64, flags: CGEventFlags) -> Bool {
        palette?.handlePanelKey(keyCode: keyCode, flags: flags) ?? false
    }

    func show() {
        dbg("launcher show called")
        if palette == nil {
            start()
        }
        palette?.show()
    }

    func rescan() {
        index.scan()
    }

    // MARK: - ⌘Tab 切换器

    func beginSwitcher() {
        if palette == nil { start() }
        // 与系统切换器一致：初次弹出选中第二个，第一个通常是当前应用
        palette?.show(selecting: 1)
    }

    func moveSwitcherSelection(by delta: Int) {
        palette?.switcherMove(by: delta)
    }

    func commitSwitcher() {
        palette?.switcherCommit()
    }

    func cancelSwitcher() {
        palette?.switcherCancel()
    }
}
