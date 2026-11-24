import AppKit
import ApplicationServices
import IOKit.hid

/// 「关于」分区：版本信息、权限状态与诊断工具。
///
/// 这一页的内容都是「出问题时才会来看」的，所以不占菜单栏，
/// 统一收在设置窗口里。权限状态做成可刷新——用户点了「去授权」
/// 在系统设置里勾选后回到这里，不用重开窗口。
final class AboutPaneViewController: SettingsPaneViewController {
    /// 状态标签提升为属性，「重新检查权限」才能就地刷新文字
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let inputMonitoringStatusLabel = NSTextField(labelWithString: "")

    /// 按键追踪面板。懒创建——大多数用户不会用到，
    /// 提前建一个带 tap 的窗口纯属浪费。
    private var keyTracePanel: KeyTracePanel?

    init() {
        super.init(title: "关于", icon: "info.circle")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // MARK: 版本

        contentStack.addArrangedSubview(makeSectionTitle("版本"))
        contentStack.addArrangedSubview(
            makeRow(title: "版本", control: makeValueLabel(Self.versionText)))
        contentStack.addArrangedSubview(
            makeRow(title: "配置版本", control: makeValueLabel(Self.configVersionText)))

        // MARK: 权限

        contentStack.addArrangedSubview(makeSectionTitle("权限"))
        contentStack.addArrangedSubview(
            makeRow(
                title: "辅助功能",
                control: makePermissionControl(
                    statusLabel: accessibilityStatusLabel,
                    action: #selector(openAccessibilitySettings))))
        contentStack.addArrangedSubview(
            makeRow(
                title: "输入监控",
                control: makePermissionControl(
                    statusLabel: inputMonitoringStatusLabel,
                    action: #selector(openInputMonitoringSettings))))
        contentStack.addArrangedSubview(
            makePlaceholder("授权后状态可能不会立即变化，可点击「重新检查权限」或重启应用。"))

        updatePermissionLabels()

        // MARK: 诊断

        contentStack.addArrangedSubview(makeSectionTitle("诊断"))
        contentStack.addArrangedSubview(makeDiagnosticButtons())
        contentStack.addArrangedSubview(
            makePlaceholder("调试日志仅在带 --debug 参数启动时生成；日志路径为 /tmp/launcher-debug.log。"))
    }

    // MARK: - 版本信息

    /// `TonyToy v1.0.2 (1)`；`Info.plist` 没有 `CFBundleVersion` 时省略括号。
    ///
    /// 版本号必须从 `Bundle.main` 读：`scripts/build.sh` 在打包时写入
    /// `CFBundleShortVersionString`，源码里不重复维护一份，避免两处不一致。
    /// 注意当前 `write_info_plist` 没有写 `CFBundleVersion`，所以正常构建下
    /// 只会显示 `TonyToy v1.0.2`，不会伪造一个构建号。
    private static var versionText: String {
        let name = stringValue(for: "CFBundleName") ?? "TonyToy"
        let shortVersion = stringValue(for: "CFBundleShortVersionString") ?? "未知"
        if let build = stringValue(for: "CFBundleVersion") {
            return "\(name) v\(shortVersion) (\(build))"
        }
        return "\(name) v\(shortVersion)"
    }

    /// 从配置里读版本号。配置不存在时 `load()` 返回默认值（当前为 v1），
    /// 所以这里仍然显示 `config.json v1`，与用户实际会拿到的一致。
    private static var configVersionText: String {
        do {
            let config = try ConfigStore.shared.load()
            return "config.json v\(config.version)"
        } catch ConfigError.futureVersion(let version) {
            // 配置文件由更新版本写过。不静默显示成本应用版本，否则用户
            // 会以为「版本没变但功能不生效」，排查方向全错。
            return "config.json v\(version)（高于本应用支持的 v\(TonyToyConfig.currentVersion)）"
        } catch {
            return "config.json 读取失败"
        }
    }

    private static func stringValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    // MARK: - 权限

    /// 用系统 API 现查，不用缓存：用户在系统设置里改完权限回来，
    /// 缓存值就过期了。
    private func updatePermissionLabels() {
        let accessibilityGranted = AXIsProcessTrusted()
        style(
            accessibilityStatusLabel,
            granted: accessibilityGranted)

        // IOHIDCheckAccess 在 macOS 10.15+ 可用。granted 对应 0，
        // 但这里用常量比较，不依赖具体数值。
        let inputMonitoringGranted =
            IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        style(
            inputMonitoringStatusLabel,
            granted: inputMonitoringGranted)
    }

    private func style(_ label: NSTextField, granted: Bool) {
        label.stringValue = granted ? "✅ 已授权" : "❌ 未授权"
        label.textColor = granted ? .systemGreen : .systemRed
    }

    @objc private func refreshPermissions() {
        updatePermissionLabels()
    }

    @objc private func openAccessibilitySettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            presentAlert(title: "无法打开系统设置", message: "URL 无效：\(urlString)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 诊断

    private func makeDiagnosticButtons() -> NSView {
        let buttons = NSStackView(views: [
            makeButton("打开配置文件夹", action: #selector(openConfigFolder)),
            makeButton("导出调试日志", action: #selector(exportDebugLog)),
            makeButton("重新检查权限", action: #selector(refreshPermissions)),
        ])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        // 输入链路诊断：排查「某个键为什么没反应」用
        let inputButtons = NSStackView(views: [
            makeButton("输入诊断报告", action: #selector(showInputDiagnostics)),
            makeButton("按键追踪…", action: #selector(showKeyTrace)),
        ])
        inputButtons.orientation = .horizontal
        inputButtons.alignment = .centerY
        inputButtons.spacing = 8

        let stack = NSStackView(views: [buttons, inputButtons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    @objc private func showInputDiagnostics() {
        let report = InputDiagnostics.report()

        let alert = NSAlert()
        alert.messageText = "输入链路诊断"
        alert.informativeText = report
        alert.alertStyle = .informational
        alert.addButton(withTitle: "复制到剪贴板")
        alert.addButton(withTitle: "关闭")

        // informativeText 不适合长文本，用 NSTextView 承载以保持等宽
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.string = report
        scroll.documentView = text
        alert.accessoryView = scroll

        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        }
    }

    @objc private func showKeyTrace() {
        if keyTracePanel == nil {
            keyTracePanel = KeyTracePanel()
        }
        keyTracePanel?.show()
    }

    @objc private func openConfigFolder() {
        let directory = ConfigStore.defaultURL.deletingLastPathComponent()
        let fileManager = FileManager.default

        // 用户从未保存过配置时目录不存在；先建出来再打开，
        // 否则 Finder 只会停在 `~/.config`，用户还得自己找。
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(
                    at: directory, withIntermediateDirectories: true)
            } catch {
                presentAlert(
                    title: "无法打开配置文件夹",
                    message: "创建目录失败：\(error.localizedDescription)")
                return
            }
        }

        if !NSWorkspace.shared.open(directory) {
            presentAlert(title: "无法打开配置文件夹", message: directory.path)
        }
    }

    @objc private func exportDebugLog() {
        let source = URL(fileURLWithPath: "/tmp/launcher-debug.log")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: source.path) else {
            presentAlert(
                title: "没有可导出的调试日志",
                message: "日志只在带 --debug 参数启动时生成。请用 --debug 启动应用、复现问题后再来导出。")
            return
        }

        guard let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
        else {
            presentAlert(title: "导出失败", message: "找不到桌面目录。")
            return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())

        // 同一秒内点两次时不能覆盖上一次导出的文件，顺序加后缀。
        var destination = desktop.appendingPathComponent("tonytoy-debug-\(timestamp).log")
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = desktop.appendingPathComponent(
                "tonytoy-debug-\(timestamp)-\(suffix).log")
            suffix += 1
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            presentAlert(title: "导出失败", message: error.localizedDescription)
            return
        }

        dbg("调试日志已导出到 \(destination.path)")

        let alert = NSAlert()
        alert.messageText = "调试日志已导出"
        alert.informativeText = destination.path
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "在访达中显示")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    // MARK: - 控件构造

    private func makeValueLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        // 允许选中复制，反馈版本/路径时不用手抄
        label.isSelectable = true
        return label
    }

    /// 权限行右侧：状态图标 + 「去授权」按钮
    private func makePermissionControl(statusLabel: NSTextField, action: Selector) -> NSView {
        statusLabel.font = .systemFont(ofSize: 12)
        let button = makeButton("去授权", action: action)
        let stack = NSStackView(views: [statusLabel, button])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
