import Foundation
import Cocoa

// 强效单实例检测：利用内核级文件锁 (flock)
// 即使用户强杀进程 (kill -9)，内核也会自动释放锁。
func acquireGlobalLock() -> Bool {
    let lockPath = NSTemporaryDirectory() + "com.sxl.tonytoy.lock"
    let fd = open(lockPath, O_CREAT | O_WRONLY, 0o666)
    if fd == -1 { return false }
    
    // LOCK_EX (排他锁) | LOCK_NB (非阻塞模式)
    // 如果返回 -1 且 errno 是 EWOULDBLOCK，说明已有其他进程持有锁。
    if flock(fd, LOCK_EX | LOCK_NB) == -1 {
        close(fd)
        return false
    }
    // 注意：我们故意不关闭 fd，让锁伴随进程生命周期
    return true
}

if !acquireGlobalLock() {
    print("⚠️  TonyToy 已有实例在运行中，请不要重复启动。")
    exit(0)
}

func isAlreadyRunning() -> Bool {
    let currentApp = NSRunningApplication.current
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: currentApp.bundleIdentifier ?? "")
    
    // 如果实例数量大于 1，说明已有另一个在运行
    return runningApps.count > 1
}

if isAlreadyRunning() {
    print("⚠️  TonyToy 已在运行中，请不要同时启动多个实例，这会导致系统死锁。")
    exit(0)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let mouseLayerController = MouseLayerController()
    private let hotkeyController = HotkeyMapperController()
    private let capsController = CapsMapperController()
    private let menuStateStore = MenuStateStore()
    
    private var isVolumeEnabled = true
    private var isHotkeyEnabled = true
    private var isCapsEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let persistedState = menuStateStore.load()
        isVolumeEnabled = persistedState.isVolumeEnabled
        isCapsEnabled = persistedState.isCapsEnabled
        isHotkeyEnabled = persistedState.isHotkeyEnabled

        // 1. 申请辅助功能权限 (Accessibility)
        checkAccessibility()
        
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        
        mouseLayerController.onVolumeChanged = { [weak self] volume in
            self?.updateStatusIcon(volume: volume)
        }
        
        // 初始启动
        mouseLayerController.setEnabled(isVolumeEnabled)
        hotkeyController.setEnabled(isHotkeyEnabled)
        capsController.setEnabled(isCapsEnabled)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 确保退出时清理映射
        capsController.setEnabled(false)
        hotkeyController.setEnabled(false)
        mouseLayerController.setEnabled(false)
    }

    private func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(volume: 0.5)
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        
        // 增加版本显示 (不可点击)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
        let versionItem = NSMenuItem(title: "TonyToy v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem.separator())

        let volItem = NSMenuItem(title: "鼠标侧键层", action: #selector(toggleVolume), keyEquivalent: "")
        volItem.state = isVolumeEnabled ? .on : .off
        menu.addItem(volItem)
        
        let capsItem = NSMenuItem(title: "Caps 键层", action: #selector(toggleCaps), keyEquivalent: "")
        capsItem.state = isCapsEnabled ? .on : .off
        menu.addItem(capsItem)

        let hotkeyItem = NSMenuItem(title: "全局快捷键层", action: #selector(toggleHotkeys), keyEquivalent: "")
        hotkeyItem.state = isHotkeyEnabled ? .on : .off
        menu.addItem(hotkeyItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }

    @objc private func toggleVolume() {
        isVolumeEnabled.toggle()
        mouseLayerController.setEnabled(isVolumeEnabled)
        persistMenuState()
        buildMenu()
    }

    @objc private func toggleCaps() {
        isCapsEnabled.toggle()
        capsController.setEnabled(isCapsEnabled)
        persistMenuState()
        buildMenu()
    }

    @objc private func toggleHotkeys() {
        isHotkeyEnabled.toggle()
        hotkeyController.setEnabled(isHotkeyEnabled)
        persistMenuState()
        buildMenu()
    }

    private func persistMenuState() {
        menuStateStore.save(
            MenuToggleState(
                isVolumeEnabled: isVolumeEnabled,
                isCapsEnabled: isCapsEnabled,
                isHotkeyEnabled: isHotkeyEnabled
            )
        )
    }

    private func updateStatusIcon(volume: Float32) {
        guard let button = statusItem?.button else { return }
        let symbolName: String
        if volume <= 0.01 { symbolName = "speaker.slash.fill" }
        else if volume < 0.33 { symbolName = "speaker.wave.1.fill" }
        else if volume < 0.66 { symbolName = "speaker.wave.2.fill" }
        else { symbolName = "speaker.wave.3.fill" }
        
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Vol")?.withSymbolConfiguration(config)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
