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
    /// MacDeck 的 bundle id。手柄 Home 键统一由 TonyToy 接管，用来切换它的大屏。
    private static let macDeckBundleIdentifier = "com.sunxiaolong.macdeck"

    private var statusItem: NSStatusItem?

    private let configStore = ConfigStore.shared
    private let featureRegistry = FeatureRegistry.shared

    /// 当前配置缓存。菜单开关状态从这里读，避免每次点菜单都读盘。
    private var config: TonyToyConfig = .default

    /// 配置窗口。用 lazy 是为了不在启动时创建整套 AppKit 视图——
    /// 大多数用户一次也不会打开设置，没必要为此拖慢冷启动。
    private lazy var settingsWindowController = SettingsWindowController()
    private var isHotkeyHandlerInstalled = false  // 防止重复安装 handler

    // MARK: - 功能访问

    private func feature(_ id: String) -> Feature? {
        featureRegistry.feature(withID: id)
    }

    private var volumeFeature: MouseLayerFeature? {
        feature(FeatureID.mouseLayer) as? MouseLayerFeature
    }

    private var capsFeature: CapsLayerFeature? {
        feature(FeatureID.capsLayer) as? CapsLayerFeature
    }

    private var hotkeyFeature: HotkeyLayerFeature? {
        feature(FeatureID.hotkeyLayer) as? HotkeyLayerFeature
    }

    private var switcherFeature: SwitcherFeature? {
        feature(FeatureID.switcher) as? SwitcherFeature
    }

    private var launcherFeature: LauncherFeature? {
        feature(FeatureID.launcher) as? LauncherFeature
    }

    private var passwordFeature: PasswordVaultFeature? {
        feature(FeatureID.passwordVault) as? PasswordVaultFeature
    }

    private var gamepadFeature: GamepadFeature? {
        feature(FeatureID.gamepad) as? GamepadFeature
    }

    /// 读某功能的开关状态（未配置时用 Feature 自己声明的默认值）
    private func isEnabled(_ id: String) -> Bool {
        config.features[id]?.isEnabled ?? feature(id)?.defaultEnabled ?? true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dbg("=== launch pid=\(getpid()) ===")

        // 1. 申请辅助功能权限 (Accessibility)
        checkAccessibility()

        NSApp.setActivationPolicy(.accessory)

        // 2. 注册所有功能。顺序即侧边栏显示顺序。
        registerFeatures()

        // 3. 首次启动：把 4 个旧配置文件迁移到统一的 config.json。
        //    旧文件保留为 .migrated，迁移出错时用户能恢复。
        //    必须在 startAll 之前——先迁移再加载，否则读到的是空配置。
        let configDirectory = ConfigStore.defaultURL.deletingLastPathComponent()
        let migrator = ConfigMigrator(directory: configDirectory, store: configStore)
        if let result = try? migrator.migrateIfNeeded(), result.didMigrate {
            dbg("已迁移 \(result.migratedFeatureCount) 个功能节点到 config.json")
        }

        // 4. 加载配置并启动功能（内部做版本检查 + 默认值补齐 + 热更新接线）
        featureRegistry.startAll()
        config = (try? configStore.load()) ?? .default

        // 5. 应用主题（重启后恢复）
        ThemeApplier.apply(config.general.theme)

        // 6. 音量变化时更新菜单栏提示
        volumeFeature?.onVolumeChanged = { [weak self] volume in
            self?.statusItem?.button?.toolTip = "音量 \(Int((volume * 100).rounded()))%"
        }

        setupStatusItem()

        // 配置由更新版本写过：功能全部未启动，且不写入配置。
        // 静默跑默认值会让用户以为「设置丢了」，必须明确告知。
        if let issue = FeatureRegistry.shared.loadIssue,
            case .futureVersion(let version) = issue
        {
            // 状态栏应用默认不激活，直接弹模态会压在别的窗口后面（无 Dock 图标
            // 也没法用 ⌘Tab 切过去），看起来就像「应用卡死」。先激活再弹。
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "配置由更新版本写入"
            alert.informativeText = """
                config.json 的版本（\(version)）高于当前应用支持的版本（\(TonyToyConfig.currentVersion)）。

                为避免覆盖高版本配置，本次没有加载任何功能，也不会写入配置文件。
                请升级 TonyToy，或备份后手动处理 ~/.config/tony-toy/config.json。
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开配置文件夹")
            alert.addButton(withTitle: "知道了")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(ConfigStore.defaultURL.deletingLastPathComponent())
            }
        }

        // 7. 密码管理器的全局热键（Carbon，与 Feature 的启停无关）
        registerPasswordManagerHotkey()

        // 8. 后台预热，避免首次 ⌘Tab 才建立 AX 连接和读取图标
        Prewarmer.start()
    }
    
    /// 注册所有功能。新增功能只需在这里加一行。
    private func registerFeatures() {
        featureRegistry.register(CapsLayerFeature())
        featureRegistry.register(HotkeyLayerFeature())
        featureRegistry.register(MouseLayerFeature())
        featureRegistry.register(SwitcherFeature())
        featureRegistry.register(LauncherFeature())
        featureRegistry.register(PasswordVaultFeature())
        featureRegistry.register(GamepadFeature())
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 确保退出时注销所有 tap、释放资源
        featureRegistry.stopAll()
    }

    private func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 菜单栏用模板图：只保留 alpha，深浅色模式由系统自动反转
        if let button = statusItem?.button {
            let icon = NSImage(named: "StatusIcon")
            icon?.isTemplate = true
            icon?.size = NSSize(width: 18, height: 18)
            button.image = icon
        }
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

        // 打开配置窗口。放在版本号之后，与下面的功能开关分组隔开。
        let settingsItem = NSMenuItem(
            title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        let volItem = NSMenuItem(title: "鼠标侧键层", action: #selector(toggleVolume), keyEquivalent: "")
        volItem.state = isEnabled(FeatureID.mouseLayer) ? .on : .off
        menu.addItem(volItem)

        let capsItem = NSMenuItem(title: "Caps 键层", action: #selector(toggleCaps), keyEquivalent: "")
        capsItem.state = isEnabled(FeatureID.capsLayer) ? .on : .off
        menu.addItem(capsItem)

        let hotkeyItem = NSMenuItem(title: "全局快捷键层", action: #selector(toggleHotkeys), keyEquivalent: "")
        hotkeyItem.state = isEnabled(FeatureID.hotkeyLayer) ? .on : .off
        menu.addItem(hotkeyItem)

        let cmdTabItem = NSMenuItem(title: "⌘Tab 接管", action: #selector(toggleCmdTab), keyEquivalent: "")
        cmdTabItem.state = isEnabled(FeatureID.switcher) ? .on : .off
        menu.addItem(cmdTabItem)

        let mouseFollowItem = NSMenuItem(title: "切换时鼠标移到窗口中心",
                                         action: #selector(toggleMouseFollow), keyEquivalent: "")
        let mouseFollowOn = config.features[FeatureID.switcher]?.values["mouseFollow"] == .bool(true)
        mouseFollowItem.state = mouseFollowOn ? .on : .off
        menu.addItem(mouseFollowItem)

        menu.addItem(NSMenuItem.separator())
        
        // 这是「打开窗口」的动作项，不是开关，不要带勾选
        let pwdItem = NSMenuItem(title: "密码管理器 (⌘⇧V)", action: #selector(showPasswordManager), keyEquivalent: "")
        menu.addItem(pwdItem)

        let launcherItem = NSMenuItem(title: "应用启动器 (\(LauncherSettings.selectedHotkey.title))",
                                      action: #selector(showLauncher), keyEquivalent: "")
        menu.addItem(launcherItem)

        let gamepadItem = NSMenuItem(title: "Switch Home 拉起 MacDeck（未运行时）",
                                     action: #selector(toggleGamepadHome), keyEquivalent: "")
        gamepadItem.state = isEnabled(FeatureID.gamepad) ? .on : .off
        menu.addItem(gamepadItem)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "重启", action: #selector(restartApp), keyEquivalent: "")
        restartItem.target = self
        restartItem.image = NSImage(systemSymbolName: "arrow.clockwise",
                                    accessibilityDescription: "重启")
        menu.addItem(restartItem)

        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - 开关动作
    //
    // 统一走 `setFeatureEnabled`：改内存 → 落盘 → 通知 Feature 热更新。
    // 不要直接调 controller.setEnabled——Feature 才是配置的持有者，
    // 绕过它会和配置窗口的状态打架。

    @objc private func toggleVolume() { setFeatureEnabled(FeatureID.mouseLayer) }
    @objc private func toggleCaps() { setFeatureEnabled(FeatureID.capsLayer) }
    @objc private func toggleHotkeys() { setFeatureEnabled(FeatureID.hotkeyLayer) }
    @objc private func toggleGamepadHome() { setFeatureEnabled(FeatureID.gamepad) }

    /// 切换某功能的开关并立即生效
    private func setFeatureEnabled(_ id: String) {
        guard let feature = feature(id) else { return }

        var featureConfig = config.features[id] ?? FeatureConfig()
        featureConfig.isEnabled.toggle()
        config.features[id] = featureConfig

        feature.apply(featureConfig)
        try? configStore.save(config)
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

    /// 鼠标跟随是切换器的子选项，不是独立功能——
    /// 存到 `features.switcher.values.mouseFollow`，切换器下次弹出生效。
    @objc private func toggleMouseFollow() {
        var featureConfig = config.features[FeatureID.switcher] ?? FeatureConfig()
        let current = featureConfig.values["mouseFollow"] == .bool(true)
        featureConfig.values["mouseFollow"] = .bool(!current)
        config.features[FeatureID.switcher] = featureConfig

        switcherFeature?.applyValues(featureConfig)
        try? configStore.save(config)
        buildMenu()
    }

    @objc private func toggleCmdTab() { setFeatureEnabled(FeatureID.switcher) }

    @objc private func showPasswordManager() {
        passwordFeature?.toggle()
    }

    @objc private func showLauncher() {
        launcherFeature?.show()
    }

    @objc private func showSettings() {
        settingsWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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

}

// tooltip 延迟 300ms（必须在 NSApplication.shared 之前注册）
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 与独立版对齐：run 之前就确定 activationPolicy，窗口的 field editor 行为才正常
app.setActivationPolicy(.accessory)
app.run()
