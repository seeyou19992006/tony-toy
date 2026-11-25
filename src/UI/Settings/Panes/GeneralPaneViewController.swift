import AppKit

/// 开机自启的落地方式：`~/Library/LaunchAgents` 下的 LaunchAgent plist。
///
/// 为什么不用 `SMLoginItemSetEnabled`：它要求 app 内嵌 helper bundle
/// （`Contents/Library/LoginItems/*.app`），本项目用 `swiftc` 直接产出可执行
/// 文件、没有 Xcode 工程，无法生成 helper。
///
/// 为什么只写文件、不调 `launchctl bootstrap`/`bootout`：
/// - launchd 在用户登录时会自动加载 `~/Library/LaunchAgents` 下的全部 plist，
///   「写入文件」本身就等价于「下次登录拉起应用」，无需手动注册；
/// - `launchctl bootstrap` 会因 `RunAtLoad` 立刻启动一份应用，而此刻应用
///   正在运行，单实例锁会让新进程直接退出，纯属噪音；
/// - 更危险的是 `launchctl bootout` 会终止该 job 名下的所有进程——
///   如果应用正是登录时由 launchd 拉起的，关掉这个开关等于把应用自己杀掉。
/// 所以这里只做文件的增删，语义最接近用户对「开机自启」开关的理解。
enum LoginItemManager {
    /// 必须与 `CFBundleIdentifier` 一致（`scripts/developer-settings.sh` 的
    /// `BUNDLE_ID`），否则同一台机器上的多个副本会互相覆盖 job。
    static let label = "com.sxl.tonytoy"

    /// `~/Library/LaunchAgents/com.sxl.tonytoy.plist`
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 当前是否已配置开机自启。以 plist 是否存在为准：
    /// launchd 的实际注册状态无法在不 fork 子进程的情况下读到，
    /// 而「文件在 = 下次登录会启动」正是用户关心的语义。
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 开启/关闭开机自启。返回 false 表示文件操作失败，
    /// 调用方据此把开关拨回原状态，避免界面与实际不一致。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        enabled ? enable() : disable()
    }

    // MARK: - 私有

    private static func enable() -> Bool {
        // 用 plist 序列化而不是拼 XML：路径里出现 & < > 等字符时
        // 手写字符串会产出非法 plist。
        let executable =
            Bundle.main.executablePath
            ?? CommandLine.arguments.first
            ?? "/Applications/TonyToy.app/Contents/MacOS/TonyToy"
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            // 崩溃后不无限重启：这是常驻状态栏应用，异常退出应该让用户看见
            "KeepAlive": false,
            // 只在图形登录会话加载，SSH 等会话不拉起（否则会和 GUI 实例抢单实例锁）
            "LimitLoadToSessionType": "Aqua",
        ]

        do {
            let directory = plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            dbg("已写入开机自启 LaunchAgent: \(plistURL.path)")
            return true
        } catch {
            dbg("写入开机自启 LaunchAgent 失败: \(error)")
            return false
        }
    }

    private static func disable() -> Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return true }
        do {
            try FileManager.default.removeItem(at: plistURL)
            dbg("已移除开机自启 LaunchAgent: \(plistURL.path)")
            return true
        } catch {
            dbg("移除开机自启 LaunchAgent 失败: \(error)")
            return false
        }
    }
}

final class GeneralPaneViewController: SettingsPaneViewController {
    private lazy var themePopUpButton = NSPopUpButton()
    private lazy var launchAtLoginSwitch = NSSwitch()

    init() {
        super.init(title: "通用", icon: "gearshape")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        themePopUpButton.controlSize = .small
        launchAtLoginSwitch.controlSize = .small

        contentStack.addArrangedSubview(makeSectionTitle("全局行为"))
        contentStack.setCustomSpacing(6, after: contentStack.arrangedSubviews.last!)
        addFullWidthSubview(makeGroupBox([
            makeRow(title: "主题", control: themePopUpButton),
            makeRow(title: "开机自启", control: launchAtLoginSwitch),
        ]))

        configureControls()
    }

    // MARK: - 初始状态

    private func configureControls() {
        // 配置读不出来（版本过高/文件损坏）时用默认值展示，开关仍可操作，
        // 只是保存会失败——由 persist 记录日志。
        let general = (try? ConfigStore.shared.load())?.general ?? GeneralConfig()

        themePopUpButton.addItems(
            withTitles: ThemePreference.allCases.map { $0.displayName })
        themePopUpButton.target = self
        themePopUpButton.action = #selector(themeDidChange(_:))
        themePopUpButton.selectItem(
            at: ThemePreference.allCases.firstIndex(of: general.theme) ?? 0)

        // 开关状态以 plist 是否存在为准：配置文件里的 launchAtLogin 只是
        // 上一次写入的留痕，plist 被外部删掉后它就不再代表实际行为了。
        launchAtLoginSwitch.state = LoginItemManager.isEnabled ? .on : .off
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginDidChange(_:))
    }

    // MARK: - 交互

    @objc private func themeDidChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard ThemePreference.allCases.indices.contains(index) else { return }
        // 立即生效 + 落盘，无需重启（已打开的窗口会即时重绘）
        ThemeApplier.setPreference(ThemePreference.allCases[index])
    }

    @objc private func launchAtLoginDidChange(_ sender: NSSwitch) {
        let wantsEnabled = sender.state == .on
        guard LoginItemManager.setEnabled(wantsEnabled) else {
            // 写 plist 失败（如 ~/Library 只读）：把开关拨回去，别让界面撒谎
            sender.state = wantsEnabled ? .off : .on
            return
        }
        guard persist({ $0.launchAtLogin = wantsEnabled }) else {
            // 配置只读：回滚 plist，维持「文件存在 = 开机自启开启」这条唯一真相
            LoginItemManager.setEnabled(!wantsEnabled)
            sender.state = wantsEnabled ? .off : .on
            return
        }
    }

    // MARK: - 持久化

    /// 修改 `general` 并落盘。返回 false 表示没写进去（只读/解析失败），
    /// 调用方负责回滚控件状态。
    @discardableResult
    private func persist(_ mutate: (inout GeneralConfig) -> Void) -> Bool {
        let store = ConfigStore.shared
        guard var config = try? store.load() else {
            dbg("通用设置读取失败，本次修改未持久化")
            return false
        }
        mutate(&config.general)
        do {
            try store.save(config)
            return true
        } catch {
            dbg("通用设置保存失败: \(error)")
            return false
        }
    }
}
