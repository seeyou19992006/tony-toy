import Cocoa

/// 应用启动器：只搜应用，回车切到该应用最近使用的窗口
final class LauncherController {
    static let shared = LauncherController()

    private let index = AppIndex()
    private let activator = Activator()
    private let hotkey = LauncherHotkeyManager()
    private let escTap = LauncherEscTap()
    private var palette: PaletteWindow?

    /// 当前热键。启动时用 `LauncherSettings` 的旧预设兜底，
    /// 加载配置后由 `LauncherFeature.applyValues` 覆盖成 config.json 里的值。
    private(set) var hotkeySpec = LauncherSettings.selectedHotkey

    /// 菜单栏显示用的热键标题（如 `⌥ D`）
    var hotkeyTitle: String { hotkeySpec.title }

    /// 是否已启动。改热键时要判断——没启动就没热键可重注册。
    private var isStarted = false

    private init() {}

    func start() {
        dbg("launcher start begin")
        isStarted = true
        index.scan()
        dbg("launcher scan done entries=\(index.entries.count)")

        palette = PaletteWindow(index: index) { [weak self] entry in
            self?.activator.activate(entry)
        }

        escTap.start()

        registerHotkey()
    }

    /// 重新注册热键（改配置后调用）。
    ///
    /// `LauncherHotkeyManager.register` 内部会先 `unregister`，
    /// 所以重复调用是安全的，不会残留旧热键。
    func updateHotkey(_ spec: HotkeySpec) {
        // 值没变就不动，避免启动时多余的 unregister/register
        guard spec != hotkeySpec else { return }
        hotkeySpec = spec
        // 没启动时只更新值——`start()` 会用新值注册
        guard isStarted else { return }
        registerHotkey()
    }

    private func registerHotkey() {
        let registered = hotkey.register(hotkeySpec) { [weak self] in
            self?.show()
        }
        dbg("launcher hotkey registered=\(registered) key=\(hotkeySpec.title)")
        if !registered {
            NSLog("launcher hotkey register failed: \(hotkeySpec.title)")
        }
    }

    /// 停止：注销热键、停 Esc tap、释放面板。
    ///
    /// 之前没有这个方法，配置窗口里关不掉启动器。
    func stop() {
        // 先隐藏再释放，避免面板残留在屏幕上
        palette?.orderOut(nil)
        palette = nil
        hotkey.unregister()
        escTap.stop()
        isStarted = false
        dbg("launcher stopped")
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
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
