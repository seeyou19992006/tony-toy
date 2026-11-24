import AppKit

/// 翻转坐标系的文档视图：滚动内容从顶部开始排列。
///
/// NSView 默认 y=0 在底部，非翻转的 documentView 又总是贴在滚动视图底部，
/// 结果是内容短于窗口时整块贴到窗口底边（实测 Pane 文案出现在底部）。
/// 翻转后内容从顶部开始，内容变长时也正好从第一行开始滚动。
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// 配置窗口右侧分区的基类。
///
/// 子类在 `viewDidLoad` 里往 `contentStack` 添加行。
/// 行统一用 `makeRow(title:control:)` 构造，保证全窗口样式一致——
/// 手写布局而不是自动生成，因为自动生成布局在项目这个规模会变成负担
/// （想调个间距都要跟生成器搏斗）。
class SettingsPaneViewController: NSViewController {
    let paneTitle: String
    let paneIcon: String

    /// 纵向内容栈，子类往里加视图
    private(set) lazy var contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    init(title: String, icon: String) {
        self.paneTitle = title
        self.paneIcon = icon
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func loadView() {
        let container = NSView()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // NSScrollView 的 documentView 需要有明确尺寸，
        // 用容器 + 四边约束把 contentStack 撑开，滚动范围才正确。
        // 容器必须翻转（见 FlippedDocumentView），否则内容会贴底。
        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)
        scrollView.documentView = documentView

        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // 用 contentView（NSClipView）而不是 scrollView：系统设置「始终显示
            // 滚动条」时 clipView 比 scrollView 窄 17pt，用 scrollView 会让
            // documentView 右侧 17pt 落到滚动条下面，最小窗口时控件被裁。
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])

        view = container
    }

    // MARK: - 行构造

    /// 统一的「左标题 + 右控件」行
    func makeRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        // 不设宽度下限：窗口 minSize 已保证内容区最小 391pt，
        // 硬编码 400 会在最小窗口下把右边距从 24 压到 15。
        return row
    }

    /// 分区标题（用于一页内再分组）
    func makeSectionTitle(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// 占位说明（本阶段各 Pane 都是空的）
    func makePlaceholder(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabelColor
        return label
    }
}

// MARK: - 声明式设置项渲染

extension SettingsPaneViewController {
    /// 按 `Feature.settings` 自动生成控件。
    ///
    /// 每个 Pane 只需一行 `buildSettings(for: feature)`——新增设置项只改
    /// Feature 的 `settings`，界面自动跟上。这是 Feature 化的核心收益：
    /// 不用为每个功能手写一遍「标题 + 控件 + 读写绑定」。
    func buildSettings(for feature: Feature) {
        let config = (try? ConfigStore.shared.load()) ?? .default
        let featureConfig = config.features[feature.id] ?? FeatureConfig()

        for item in feature.settings {
            if let row = makeRow(for: item, feature: feature, featureConfig: featureConfig) {
                contentStack.addArrangedSubview(row)
            }
        }
    }

    // MARK: - 单项渲染

    private func makeRow(
        for item: SettingItem, feature: Feature, featureConfig: FeatureConfig
    ) -> NSView? {
        switch item {
        case .toggle(let key, let title, let defaultValue):
            return makeToggleRow(key: key, title: title, defaultValue: defaultValue,
                                 feature: feature, featureConfig: featureConfig)

        case .hotkey(let key, let title, let defaultValue):
            return makeHotkeyRow(key: key, title: title, defaultValue: defaultValue,
                                 feature: feature, featureConfig: featureConfig)

        case .number(let key, let title, let defaultValue, let range):
            return makeNumberRow(key: key, title: title, defaultValue: defaultValue,
                                 range: range, feature: feature, featureConfig: featureConfig)

        case .picker(let key, let title, let options, let defaultValue):
            return makePickerRow(key: key, title: title, options: options,
                                 defaultValue: defaultValue, feature: feature,
                                 featureConfig: featureConfig)

        case .table(_, let title):
            return makeTableRow(title: title, feature: feature, featureConfig: featureConfig)
        }
    }

    // MARK: - 开关

    private func makeToggleRow(
        key: String, title: String, defaultValue: Bool,
        feature: Feature, featureConfig: FeatureConfig
    ) -> NSView {
        let toggle = NSSwitch()
        toggle.controlSize = .small

        // `enabled` 是功能总开关，存在 isEnabled；其余 toggle 存在 values 里
        if key == "enabled" {
            toggle.state = featureConfig.isEnabled ? .on : .off
        } else if case .bool(let value)? = featureConfig.values[key] {
            toggle.state = value ? .on : .off
        } else {
            toggle.state = defaultValue ? .on : .off
        }

        let target = ToggleTarget { [weak self] isOn in
            self?.updateConfig(feature: feature) { config in
                if key == "enabled" {
                    config.isEnabled = isOn
                } else {
                    config.values[key] = .bool(isOn)
                }
            }
        }
        toggle.target = target
        toggle.action = #selector(ToggleTarget.fire(_:))
        // target 是 weak 的，必须强引用住
        retainTarget(target)

        return makeRow(title: title, control: toggle)
    }

    // MARK: - 快捷键

    private func makeHotkeyRow(
        key: String, title: String, defaultValue: HotkeyKeySpec,
        feature: Feature, featureConfig: FeatureConfig
    ) -> NSView {
        let recorder = HotkeyRecorder()
        recorder.spec = Self.decodeHotkey(featureConfig.values[key]) ?? defaultValue
        recorder.onChange = { [weak self] spec in
            self?.updateConfig(feature: feature) { config in
                config.values[key] = Self.encodeHotkey(spec)
            }
        }
        return makeRow(title: title, control: recorder)
    }

    // MARK: - 数字

    private func makeNumberRow(
        key: String, title: String, defaultValue: Int, range: ClosedRange<Int>,
        feature: Feature, featureConfig: FeatureConfig
    ) -> NSView {
        let field = NSTextField(string: "")
        field.formatter = NumberFormatter()
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let current: Int
        if case .int(let value)? = featureConfig.values[key] {
            current = value
        } else {
            current = defaultValue
        }
        field.integerValue = current

        let target = NumberTarget(range: range) { [weak self] value in
            self?.updateConfig(feature: feature) { config in
                config.values[key] = .int(value)
            }
        }
        field.target = target
        field.action = #selector(NumberTarget.fire(_:))
        retainTarget(target)

        return makeRow(title: title, control: field)
    }

    // MARK: - 下拉

    private func makePickerRow(
        key: String, title: String, options: [(value: String, label: String)],
        defaultValue: String, feature: Feature, featureConfig: FeatureConfig
    ) -> NSView {
        let popup = NSPopUpButton()
        popup.controlSize = .small
        for option in options {
            popup.addItem(withTitle: option.label)
            popup.lastItem?.representedObject = option.value
        }

        let current: String
        if case .string(let value)? = featureConfig.values[key] {
            current = value
        } else {
            current = defaultValue
        }
        if let index = options.firstIndex(where: { $0.value == current }) {
            popup.selectItem(at: index)
        }

        let target = PickerTarget { [weak self] value in
            self?.updateConfig(feature: feature) { config in
                config.values[key] = .string(value)
            }
        }
        popup.target = target
        popup.action = #selector(PickerTarget.fire(_:))
        retainTarget(target)

        return makeRow(title: title, control: popup)
    }

    // MARK: - 映射表

    private func makeTableRow(
        title: String, feature: Feature, featureConfig: FeatureConfig
    ) -> NSView {
        let style: MappingTableEditor.Style
        switch feature.id {
        case FeatureID.capsLayer: style = .capsLayer
        case FeatureID.hotkeyLayer: style = .hotkeyLayer
        default: style = .mouseLayer
        }

        let editor = MappingTableEditor(
            style: style,
            mappings: MappingTableEditor.mappings(from: featureConfig.values["mappings"]),
            onChange: { [weak self] mappings in
                self?.updateConfig(feature: feature) { config in
                    config.values["mappings"] = .array(mappings)
                }
            }
        )

        let label = makeSectionTitle(title)
        let stack = NSStackView(views: [label, editor])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    // MARK: - 读写

    /// 改配置：写内存 → 落盘 → 通知 Feature 热更新
    private func updateConfig(feature: Feature, _ mutate: (inout FeatureConfig) -> Void) {
        let store = ConfigStore.shared
        var config = (try? store.load()) ?? .default
        var featureConfig = config.features[feature.id] ?? FeatureConfig()
        mutate(&featureConfig)
        config.features[feature.id] = featureConfig

        feature.apply(featureConfig)
        try? store.save(config)
    }

    // MARK: - 编解码

    static func decodeHotkey(_ value: JSONValue?) -> HotkeyKeySpec? {
        guard case .object(let dict)? = value,
            case .string(let key)? = dict["key"]
        else { return nil }
        var modifiers: [String] = []
        if case .array(let list)? = dict["modifiers"] {
            modifiers = list.compactMap { item in
                if case .string(let text) = item { return text }
                return nil
            }
        }
        return HotkeyKeySpec(key: key, modifiers: modifiers)
    }

    static func encodeHotkey(_ spec: HotkeyKeySpec?) -> JSONValue {
        guard let spec else { return .null }
        return .object([
            "key": .string(spec.key),
            "modifiers": .array((spec.modifiers ?? []).map { .string($0) }),
        ])
    }

    // MARK: - target 保活

    /// AppKit 的 target 是 weak 引用，闭包 target 必须自己强引用住，
    /// 否则下次 GC 就成悬垂指针（点开关没反应）。
    private func retainTarget(_ target: AnyObject) {
        retainedTargets.append(target)
    }

    private var retainedTargets: [AnyObject] {
        get { objc_getAssociatedObject(self, &Self.targetsKey) as? [AnyObject] ?? [] }
        set { objc_setAssociatedObject(self, &Self.targetsKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    private static var targetsKey: UInt8 = 0
}

// MARK: - 闭包 target

/// `NSSwitch` / `NSTextField` / `NSPopUpButton` 的 target 必须是
/// `@objc` 方法，用一个包装类承接闭包。
private final class ToggleTarget: NSObject {
    private let handler: (Bool) -> Void
    init(_ handler: @escaping (Bool) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSSwitch) { handler(sender.state == .on) }
}

private final class NumberTarget: NSObject {
    private let range: ClosedRange<Int>
    private let handler: (Int) -> Void
    init(range: ClosedRange<Int>, _ handler: @escaping (Int) -> Void) {
        self.range = range
        self.handler = handler
    }
    @objc func fire(_ sender: NSTextField) {
        let clamped = min(max(sender.integerValue, range.lowerBound), range.upperBound)
        sender.integerValue = clamped
        handler(clamped)
    }
}

private final class PickerTarget: NSObject {
    private let handler: (String) -> Void
    init(_ handler: @escaping (String) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? String else { return }
        handler(value)
    }
}
