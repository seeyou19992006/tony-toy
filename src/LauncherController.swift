import Cocoa

/// 应用启动器：只搜应用，回车切到该应用最近使用的窗口
final class LauncherController {
    static let shared = LauncherController()

    private let index = AppIndex()
    private let activator = Activator()
    private let hotkey = LauncherHotkeyManager()
    private var palette: PaletteWindow?

    private init() {}

    func start() {
        dbg("launcher start begin")
        index.scan()
        dbg("launcher scan done entries=\(index.entries.count)")

        palette = PaletteWindow(index: index) { [weak self] entry in
            self?.activator.activate(entry)
        }

        let registered = hotkey.register(LauncherSettings.selectedHotkey) { [weak self] in
            self?.show()
        }
        dbg("launcher hotkey registered=\(registered) key=\(LauncherSettings.selectedHotkey.title)")
        if !registered {
            NSLog("launcher hotkey register failed: \(LauncherSettings.selectedHotkey.title)")
        }
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
}
