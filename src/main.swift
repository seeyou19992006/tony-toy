import Foundation
import Cocoa
import Carbon

// 全局变量用于 Carbon 回调

// 短命子进程模式：仅在后台扫描应用名时由主进程拉起，批量转换汉字后立刻退出，
// 避免主进程常驻加载 ICU 中文拼音转换表。
if CommandLine.arguments.contains("--convert-pinyin") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    let map = Pinyin.batchConvertCharacters(text)
    if let json = try? JSONSerialization.data(withJSONObject: map) {
        FileHandle.standardOutput.write(json)
    }
    exit(0)
}

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
    let activator = Activator()
    activator.activate(AppEntry(name: bundleID, bundleID: bundleID, url: url))
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

    /// 配置窗口：按需创建，关闭窗口时释放视图树，减少空闲内存占用。
    private var settingsWindowController: SettingsWindowController?
    private var settingsCloseObserver: NSObjectProtocol?

    /// 密码管理器的全局热键（Carbon，随配置热更新）
    private let passwordHotkey = CarbonHotkey(
        name: "密码管理器", signature: OSType.fourCharCode("TnyP"))

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
        setupMainMenu()

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
        NotificationCenter.default.addObserver(
            forName: .tonyToyConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let updated = notification.object as? TonyToyConfig {
                self.config = updated
            } else {
                self.config = (try? self.configStore.load()) ?? self.config
            }
            self.buildMenu()
        }

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

        // 7. 密码管理器的全局热键（Carbon，随启用开关与热键配置动态注册/注销）
        passwordHotkey.onTrigger = { [weak self] in
            self?.showPasswordManager()
        }
        passwordFeature?.onHotkeyChanged = { [weak self] spec in
            guard let self, self.isEnabled(FeatureID.passwordVault) else { return }
            self.passwordHotkey.register(keyCode: spec.keyCode, modifiers: spec.modifiers)
        }
        passwordFeature?.onEnabledChanged = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                let spec = self.passwordFeature?.currentHotkeySpec
                self.passwordHotkey.register(
                    keyCode: spec?.keyCode ?? 9,
                    modifiers: spec?.modifiers ?? (UInt32(cmdKey) | UInt32(shiftKey)))
            } else {
                self.passwordHotkey.unregister()
            }
        }
        if isEnabled(FeatureID.passwordVault) {
            let pwdSpec = passwordFeature?.currentHotkeySpec
            passwordHotkey.register(
                keyCode: pwdSpec?.keyCode ?? 9,
                modifiers: pwdSpec?.modifiers ?? (UInt32(cmdKey) | UInt32(shiftKey)))
        }

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
        passwordHotkey.unregister()
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

    /// 往菜单加一个功能总开关。
    ///
    /// 5 个开关的构建逻辑完全一样，只有标题/id/action 不同——
    /// 抽出来避免每加一个功能就复制 3 行还容易写错 id。
    /// 往菜单加一个功能总开关。
    ///
    /// **不用 `state` 显示勾号**，改用图标——菜单同时存在「勾选列」和
    /// 「图标列」时，图标会被推到第二列，下半部分（启动器/密码管理器/
    /// 重启/退出）的图标就和上面的勾号错开一格。
    /// 全部走图标列后整列对齐，勾选状态用 ✓ / 空白表达。
    private func addToggle(to menu: NSMenu, title: String, featureID: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        let on = isEnabled(featureID)
        if on {
            item.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已启用")
        }
        menu.addItem(item)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "设置", action: #selector(showSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出 TonyToy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    private func buildMenu() {
        let menu = NSMenu()

        // MARK: 标题

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
        let buildTime = (Bundle.main.infoDictionary?["TonyToyBuildTime"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let versionTitle = (buildTime?.isEmpty == false)
            ? "TonyToy v\(version) · \(buildTime!)"
            : "TonyToy v\(version)"
        let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(NSMenuItem.separator())

        // MARK: 设置入口

        let settingsItem = NSMenuItem(
            title: "设置", action: #selector(showSettings), keyEquivalent: ",")
        // 透明占位图：这一项不放图标，但菜单已有图标列，
        // 不给 image 的话标题会贴到最左边，与下面各项的标题错开一格。
        settingsItem.image = NSImage(size: NSSize(width: 16, height: 16))
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // MARK: 功能总开关
        //
        // 只放「启用/禁用某个功能」这一层。功能内部的子选项
        // （如鼠标跟随、启动器每页项数）统一在设置窗口里管，
        // 避免托盘菜单变成无底洞。

        addToggle(to: menu, title: "鼠标侧键层", featureID: FeatureID.mouseLayer,
                  action: #selector(toggleVolume))
        addToggle(to: menu, title: "Caps 键层", featureID: FeatureID.capsLayer,
                  action: #selector(toggleCaps))
        addToggle(to: menu, title: "全局快捷键", featureID: FeatureID.hotkeyLayer,
                  action: #selector(toggleHotkeys))
        addToggle(to: menu, title: "窗口切换器", featureID: FeatureID.switcher,
                  action: #selector(toggleCmdTab))
        addToggle(to: menu, title: "MacDeck 启动器", featureID: FeatureID.gamepad,
                  action: #selector(toggleGamepadHome))

        menu.addItem(NSMenuItem.separator())

        // MARK: 窗口入口 + 应用操作
        //
        // 启动器和密码管理器都是「打开一个窗口」的动作，与上面的开关性质不同，
        // 放在这组里和重启/退出一起更符合直觉。

        // 热键标题从配置读——用户在设置里改完，菜单要跟着变
        //
        // 这几项都要给图标：菜单列是 [勾选位][图标位][标题]，
        // 开关有勾号、重启/退出有图标，中间两项都没有时标题会被居中悬浮，
        // 和上下都不对齐。
        let launcherHotkey = launcherFeature?.hotkeyTitle ?? LauncherSettings.selectedHotkey.title
        let launcherItem = NSMenuItem(
            title: "应用启动器 (\(launcherHotkey))",
            action: #selector(showLauncher), keyEquivalent: "")
        launcherItem.image = NSImage(
            systemSymbolName: "magnifyingglass", accessibilityDescription: "应用启动器")
        menu.addItem(launcherItem)

        let pwdHotkey = passwordFeature?.hotkeyTitle ?? "⌘⇧V"
        let pwdItem = NSMenuItem(
            title: "密码管理器 (\(pwdHotkey))", action: #selector(showPasswordManager), keyEquivalent: "")
        pwdItem.image = NSImage(
            systemSymbolName: "lock", accessibilityDescription: "密码管理器")
        menu.addItem(pwdItem)

        let restartItem = NSMenuItem(title: "重启", action: #selector(restartApp), keyEquivalent: "")
        restartItem.target = self
        restartItem.image = NSImage(systemSymbolName: "arrow.clockwise",
                                    accessibilityDescription: "重启")
        menu.addItem(restartItem)

        menu.addItem(
            NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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

        var latest = (try? configStore.load()) ?? config
        var featureConfig = latest.features[id] ?? FeatureConfig(isEnabled: feature.defaultEnabled)
        featureConfig.isEnabled.toggle()
        latest.features[id] = featureConfig
        config = latest

        try? configStore.save(latest)
        feature.apply(featureConfig)
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

    @objc private func toggleCmdTab() { setFeatureEnabled(FeatureID.switcher) }

    @objc private func showPasswordManager() {
        passwordFeature?.toggle()
    }

    @objc private func showLauncher() {
        launcherFeature?.show()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController()
            settingsWindowController = controller
            if let window = controller.window {
                settingsCloseObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    if let observer = self?.settingsCloseObserver {
                        NotificationCenter.default.removeObserver(observer)
                        self?.settingsCloseObserver = nil
                    }
                    self?.settingsWindowController = nil
                }
            }
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


}

// tooltip 延迟 300ms（必须在 NSApplication.shared 之前注册）
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 与独立版对齐：run 之前就确定 activationPolicy，窗口的 field editor 行为才正常
app.setActivationPolicy(.accessory)

// 诊断用：反复开关追踪窗口，验证 EventTap 拆除时不会留下悬垂回调
if CommandLine.arguments.contains("--keytrace-selftest") {
    DispatchQueue.main.async { KeyTraceSelfTest.run() }
}

app.run()
