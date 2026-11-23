import Foundation
import Cocoa
import Carbon

// 全局变量用于 Carbon 回调
weak var _PasswordManagerSharedSelf: AppDelegate?

// 调试用：跑一次搜索并打印结果
if let flag = CommandLine.arguments.firstIndex(of: "--search"),
   flag + 1 < CommandLine.arguments.count {
    let index = AppIndex()
    index.scan()
    print("索引总数: \(index.entries.count)")
    for entry in index.search(CommandLine.arguments[flag + 1]).prefix(10) {
        print("  \(entry.name)  \(entry.bundleID)")
    }
    exit(0)
}

// 调试用：按 bundle id 激活应用（走完整 Activator 逻辑）
if let flag = CommandLine.arguments.firstIndex(of: "--open"),
   flag + 1 < CommandLine.arguments.count,
   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CommandLine.arguments[flag + 1]) {
    let bundleID = CommandLine.arguments[flag + 1]
    Activator().activate(AppEntry(name: bundleID, bundleID: bundleID, url: url))
    RunLoop.main.run(until: Date().addingTimeInterval(2.5))
    exit(0)
}

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
    private let passwordManager = PasswordManagerWindow()
    private let launcherController = LauncherController.shared
    private let cmdTabSwitcher = CmdTabSwitcher()
    private var isHotkeyHandlerInstalled = false  // 防止重复安装 handler

    private var isVolumeEnabled = true
    private var isHotkeyEnabled = true
    private var isCmdTabEnabled = true
    private var isMouseFollowEnabled = false
    private var isCapsEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        dbg("=== launch pid=\(getpid()) ===")
        let persistedState = menuStateStore.load()
        isVolumeEnabled = persistedState.isVolumeEnabled
        isCapsEnabled = persistedState.isCapsEnabled
        isHotkeyEnabled = persistedState.isHotkeyEnabled
        isCmdTabEnabled = persistedState.isCmdTabEnabled
        isMouseFollowEnabled = persistedState.isMouseFollowEnabled

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
        
        // 注册密码管理器快捷键 (Cmd+Shift+V)
        registerPasswordManagerHotkey()

        // 启动应用启动器 (⌥D)
        launcherController.start()
        // 接管 ⌘Tab
        if isCmdTabEnabled {
            cmdTabSwitcher.start()
        }

        // 后台预热，避免首次 ⌘Tab 才建立 AX 连接和读取图标
        Prewarmer.start()

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

        let cmdTabItem = NSMenuItem(title: "⌘Tab 接管", action: #selector(toggleCmdTab), keyEquivalent: "")
        cmdTabItem.state = isCmdTabEnabled ? .on : .off
        menu.addItem(cmdTabItem)

        let mouseFollowItem = NSMenuItem(title: "切换时鼠标移到窗口中心",
                                         action: #selector(toggleMouseFollow), keyEquivalent: "")
        mouseFollowItem.state = isMouseFollowEnabled ? .on : .off
        menu.addItem(mouseFollowItem)

        menu.addItem(NSMenuItem.separator())
        
        // 这是「打开窗口」的动作项，不是开关，不要带勾选
        let pwdItem = NSMenuItem(title: "密码管理器 (⌘⇧V)", action: #selector(showPasswordManager), keyEquivalent: "")
        menu.addItem(pwdItem)

        let launcherItem = NSMenuItem(title: "应用启动器 (\(LauncherSettings.selectedHotkey.title))",
                                      action: #selector(showLauncher), keyEquivalent: "")
        menu.addItem(launcherItem)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "重启", action: #selector(restartApp), keyEquivalent: "")
        restartItem.target = self
        restartItem.image = NSImage(systemSymbolName: "arrow.clockwise",
                                    accessibilityDescription: "重启")
        menu.addItem(restartItem)

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
    
    @objc private func restartApp() {
        // 单实例锁要求旧进程先退出，所以延迟一点再拉起新实例
        let path = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open -n '\''\(path)'\''"]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func toggleMouseFollow() {
        isMouseFollowEnabled.toggle()
        persistMenuState()
        buildMenu()
    }

    @objc private func toggleCmdTab() {
        isCmdTabEnabled.toggle()
        if isCmdTabEnabled {
            cmdTabSwitcher.start()
        } else {
            cmdTabSwitcher.stop()
        }
        persistMenuState()
        buildMenu()
    }

    @objc private func showPasswordManager() {
        if !passwordManager.isVisible {
            // 记录当前前台应用，以便粘贴密码时恢复焦点
            passwordManager.recordPreviousApp()

            // 先激活应用，确保窗口能获得焦点
            NSApp.activate(ignoringOtherApps: true)

            // 检查是否已解锁
            if !passwordManager.vaultService.isUnlocked {
                passwordManager.showUnlockView()
            } else {
                passwordManager.showMainView()
            }
            passwordManager.makeKeyAndOrderFront(nil)
        } else {
            passwordManager.orderOut(nil)
        }
    }
    
    @objc private func showLauncher() {
        launcherController.show()
    }

    private func registerPasswordManagerHotkey() {
        // 防止重复安装 handler
        guard !isHotkeyHandlerInstalled else { return }
        isHotkeyHandlerInstalled = true

        // 使用 Carbon 注册全局快捷键
        var hotKeyRef: EventHotKeyRef?
        let modifierKeys: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)
        let keyCode: UInt32 = 9  // V 键

        var spec = EventHotKeyID()
        spec.signature = 1953390948  // 'PwdM'
        spec.id = 1

        let status = RegisterEventHotKey(
            keyCode,
            modifierKeys,
            spec,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            // 使用全局变量避免闭包捕获
            _PasswordManagerSharedSelf = self

            let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }

                // 与启动器共用事件分发目标，只响应 PwdM 这一个热键
                var identifier = EventHotKeyID()
                let readStatus = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                                   EventParamType(typeEventHotKeyID), nil,
                                                   MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard readStatus == noErr,
                      identifier.signature == 1953390948,  // 'PwdM'
                      identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    _PasswordManagerSharedSelf?.showPasswordManager()
                }
                return noErr
            }

            var eventTypeSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let userData: UnsafeMutableRawPointer? = nil
            InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventTypeSpec, userData, nil)
            print("✅ 密码管理器快捷键已注册: Cmd+Shift+V")
        }
    }

    private func persistMenuState() {
        menuStateStore.save(
            MenuToggleState(
                isVolumeEnabled: isVolumeEnabled,
                isCapsEnabled: isCapsEnabled,
                isHotkeyEnabled: isHotkeyEnabled,
                isCmdTabEnabled: isCmdTabEnabled,
                isMouseFollowEnabled: isMouseFollowEnabled,
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

// tooltip 延迟 300ms（必须在 NSApplication.shared 之前注册）
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 与独立版对齐：run 之前就确定 activationPolicy，窗口的 field editor 行为才正常
app.setActivationPolicy(.accessory)
app.run()
