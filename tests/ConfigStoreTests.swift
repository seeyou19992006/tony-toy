import Foundation

func testConfigDefaults() {
    let config = TonyToyConfig.default

    assertTrue(config.version == 1, "版本号应为 1")
    assertTrue(config.general.theme == .system, "主题默认跟随系统")
    assertTrue(config.general.showMenuBarIcon, "菜单栏图标默认显示")
    assertTrue(config.general.launchAtLogin == false, "开机自启默认关闭")
    print("testConfigDefaults passed")
}

func testConfigRoundTrip() {
    var config = TonyToyConfig.default
    config.general.theme = .dark
    config.features["capsLayer"] = FeatureConfig(
        isEnabled: true,
        values: ["mappings": .array([
            .object(["from": .string("e"), "to": .object(["key": .string("up_arrow")])])
        ])]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let data = try! encoder.encode(config)
    let decoded = try! JSONDecoder().decode(TonyToyConfig.self, from: data)

    assertTrue(decoded == config, "配置往返应保持不变")
    assertTrue(decoded.general.theme == .dark, "主题应持久化")
    print("testConfigRoundTrip passed")
}

func testFeatureEnabledLookup() {
    var config = TonyToyConfig.default
    config.features["gamepad"] = FeatureConfig(isEnabled: false, values: [:])

    assertTrue(config.isEnabled("gamepad") == false, "已配置的功能应返回其开关值")
    assertTrue(config.isEnabled("unknown") == true, "未知功能默认启用")
    print("testFeatureEnabledLookup passed")
}

func testConfigToleratesMissingFields() {
    // 只写了 theme，其他字段全缺失
    let json = #"{"general":{"theme":"dark"}}"#.data(using: .utf8)!
    let config = try! JSONDecoder().decode(TonyToyConfig.self, from: json)

    assertTrue(config.version == 1, "缺失 version 应用当前版本")
    assertTrue(config.general.theme == .dark, "已写字段应保留")
    assertTrue(config.general.launchAtLogin == false, "缺失 launchAtLogin 用默认值")
    assertTrue(config.general.showMenuBarIcon == true, "缺失 showMenuBarIcon 用默认值")
    assertTrue(config.features.isEmpty, "缺失 features 应为空")
    print("testConfigToleratesMissingFields passed")
}

func testFeatureConfigToleratesMissingFields() {
    let json = #"{"features":{"gamepad":{}}}"#.data(using: .utf8)!
    let config = try! JSONDecoder().decode(TonyToyConfig.self, from: json)

    assertTrue(config.features["gamepad"]?.isEnabled == true, "缺失 isEnabled 默认启用")
    assertTrue(config.features["gamepad"]?.values.isEmpty == true, "缺失 values 应为空")
    print("testFeatureConfigToleratesMissingFields passed")
}

func testConfigEmptyFeaturesByDefault() {
    let config = TonyToyConfig.default
    assertTrue(config.features.isEmpty, "默认配置的 features 应为空")
    assertTrue(TonyToyConfig.currentVersion == 1, "当前版本号应为 1")
    print("testConfigEmptyFeaturesByDefault passed")
}

func testConfigStoreSaveAndLoad() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("config.json")
    let store = ConfigStore(fileURL: fileURL)

    // 首次加载：文件不存在，返回默认值
    let initial = try! store.load()
    assertTrue(initial == TonyToyConfig.default, "文件不存在时返回默认配置")

    // 保存后重新加载
    var config = initial
    config.general.theme = .dark
    config.features["gamepad"] = FeatureConfig(isEnabled: false)
    try! store.save(config)

    let reloaded = try! store.load()
    assertTrue(reloaded.general.theme == .dark, "主题应落盘")
    assertTrue(reloaded.isEnabled("gamepad") == false, "功能开关应落盘")
    print("testConfigStoreSaveAndLoad passed")
}

func testConfigStoreCreatesDirectory() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // 目录还不存在，save 应自动创建
    let fileURL = tempDir.appendingPathComponent("config.json")
    let store = ConfigStore(fileURL: fileURL)
    try! store.save(.default)

    assertTrue(FileManager.default.fileExists(atPath: fileURL.path), "应自动创建父目录")
    print("testConfigStoreCreatesDirectory passed")
}

func testConfigStoreCorruptedFile() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("config.json")
    try! "这不是 JSON".write(to: fileURL, atomically: true, encoding: .utf8)

    let store = ConfigStore(fileURL: fileURL)
    let config = try! store.load()
    assertTrue(config == TonyToyConfig.default, "损坏的文件应回退到默认配置")

    // 损坏文件应被备份，不静默丢弃
    let backups = try! FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        .filter { $0.contains("corrupted") }
    assertTrue(!backups.isEmpty, "损坏文件应备份为 .corrupted")

    // 必须是「移走」而不是「复制」：复制的话原文件还在，
    // 下次启动会再解析失败一次，备份文件越积越多。
    assertTrue(
        !FileManager.default.fileExists(atPath: fileURL.path),
        "损坏的原文件应已被移走，不能留在原地")

    print("testConfigStoreCorruptedFile passed")
}

func testMigratorImportsMappingFiles() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-migrate-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Caps 层：from 是单个字符
    let capsJSON = #"{"version":1,"mappings":[{"from":"e","to":{"key":"up_arrow"}}]}"#
    try! capsJSON.write(
        to: tempDir.appendingPathComponent("caps-mappings.json"),
        atomically: true, encoding: .utf8)

    // 全局快捷键：from 是组合键
    let hotkeysJSON = """
    {"version":1,"mappings":[{"from":{"key":"escape","modifiers":["command"]}, \
    "to":{"key":"grave_accent_and_tilde","modifiers":["command"]}}]}
    """
    try! hotkeysJSON.write(
        to: tempDir.appendingPathComponent("hotkeys.json"),
        atomically: true, encoding: .utf8)

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let migrator = ConfigMigrator(directory: tempDir, store: store)
    let result = try! migrator.migrateIfNeeded()

    assertTrue(result.didMigrate, "首次迁移应返回 didMigrate = true")
    assertTrue(result.migratedFeatureCount == 2, "应迁移 2 个功能节点")

    let capsMappings = result.config.features["capsLayer"]?.values["mappings"]
    guard case .array(let capsList)? = capsMappings else {
        assertTrue(false, "capsLayer.values.mappings 应为数组")
        return
    }
    assertTrue(capsList.count == 1, "Caps 层应迁入 1 条")

    let hotkeyMappings = result.config.features["hotkeyLayer"]?.values["mappings"]
    guard case .array(let hotkeyList)? = hotkeyMappings else {
        assertTrue(false, "hotkeyLayer.values.mappings 应为数组")
        return
    }
    assertTrue(hotkeyList.count == 1, "全局快捷键应迁入 1 条")

    print("testMigratorImportsMappingFiles passed")
}

func testMigratorImportsInputAliases() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-migrate-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // 真实结构：没有 mappings，是 4 个独立字典
    let aliasesJSON = """
    {"version":1,"keyboard_keys":{"a":{"key_code":0}},"modifiers":{"command":{"flag":"command"}},
    "mouse_inputs":{"left_click":{"kind":"button","button_number":0}},
    "actions":{"volume_scroll":{"kind":"volume_scroll"}}}
    """
    try! aliasesJSON.write(
        to: tempDir.appendingPathComponent("input-aliases.json"),
        atomically: true, encoding: .utf8)

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let migrator = ConfigMigrator(directory: tempDir, store: store)
    let result = try! migrator.migrateIfNeeded()

    let values = result.config.features["inputAliases"]?.values
    assertTrue(values != nil, "应生成 inputAliases 节点")
    assertTrue(values?["keyboardKeys"] != nil, "应迁入 keyboardKeys")
    assertTrue(values?["modifiers"] != nil, "应迁入 modifiers")
    assertTrue(values?["mouseInputs"] != nil, "应迁入 mouseInputs")
    assertTrue(values?["actions"] != nil, "应迁入 actions")
    print("testMigratorImportsInputAliases passed")
}

func testMigratorPreservesActivationButton() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-migrate-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let mouseJSON = """
    {"version":1,"activation_button":"button5",
    "mappings":[{"from":{"input":"scroll_wheel"},"to":{"action":"volume_scroll"}}]}
    """
    try! mouseJSON.write(
        to: tempDir.appendingPathComponent("mouse-layer.json"),
        atomically: true, encoding: .utf8)

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let migrator = ConfigMigrator(directory: tempDir, store: store)
    let result = try! migrator.migrateIfNeeded()

    let values = result.config.features["mouseLayer"]?.values
    assertTrue(
        values?["activationButton"] == .string("button5"),
        "应保留 activation_button，否则鼠标侧键层功能失效")
    print("testMigratorPreservesActivationButton passed")
}

func testMigratorRenamesLegacyFilesAndIsIdempotent() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-migrate-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let capsURL = tempDir.appendingPathComponent("caps-mappings.json")
    try! #"{"version":1,"mappings":[{"from":"e","to":{"key":"up_arrow"}}]}"#.write(
        to: capsURL, atomically: true, encoding: .utf8)

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let migrator = ConfigMigrator(directory: tempDir, store: store)

    let first = try! migrator.migrateIfNeeded()
    assertTrue(first.didMigrate, "首次应执行迁移")

    // 旧文件应重命名为 .migrated
    assertTrue(
        !FileManager.default.fileExists(atPath: capsURL.path),
        "旧文件应被移走")
    assertTrue(
        FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("caps-mappings.json.migrated").path),
        "旧文件应保留为 .migrated")

    // 第二次调用不应改变任何东西
    let configAfterFirst = try! store.load()
    let second = try! migrator.migrateIfNeeded()
    let configAfterSecond = try! store.load()

    assertTrue(second.didMigrate == false, "重复迁移应返回 didMigrate = false")
    assertTrue(
        second.migratedFeatureCount == 0,
        "重复迁移不应再计数，实际: \(second.migratedFeatureCount)")
    assertTrue(configAfterFirst == configAfterSecond, "重复迁移应幂等")
    print("testMigratorRenamesLegacyFilesAndIsIdempotent passed")
}

func testUpdateFeatureNotifiesAndPersists() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("config.json")
    let store = ConfigStore(fileURL: fileURL)

    // 先放一个无关字段，验证 updateFeature 不会整份覆盖
    var initial = TonyToyConfig.default
    initial.general.showMenuBarIcon = false
    try! store.save(initial)

    var received: TonyToyConfig?
    var diskStateDuringCallback: TonyToyConfig?
    store.onChange = { config in
        received = config
        // 在回调内部读盘：如果实现是「先通知后落盘」，这里读到的还是旧值
        diskStateDuringCallback = try? store.load()
    }

    try! store.updateFeature(FeatureID.gamepad) { feature in
        feature.isEnabled = false
    }

    assertTrue(received != nil, "onChange 应被触发")
    assertTrue(received?.isEnabled(FeatureID.gamepad) == false, "回调应带新值")
    assertTrue(
        received?.general.showMenuBarIcon == false,
        "未触碰的字段应保留，不能被整份覆盖")
    assertTrue(
        diskStateDuringCallback?.isEnabled(FeatureID.gamepad) == false,
        "回调触发时磁盘应已是新值（验证 save 在 onChange 之前）")
    print("testUpdateFeatureNotifiesAndPersists passed")
}

func testMigratorImportsUserDefaults() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-migrate-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // 用独立 suite，不污染真实 UserDefaults
    let suiteName = "tonytoy-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    // 显式设置三个：两个旧默认关闭的 + 一个旧默认开启的
    defaults.set(false, forKey: "menu.isCmdTabEnabled")
    defaults.set(true, forKey: "menu.isCapsEnabled")
    defaults.set(true, forKey: "menu.isMouseFollowEnabled")
    // menu.isVolumeEnabled 不设，验证「未设置不创建节点」

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let migrator = ConfigMigrator(directory: tempDir, store: store, defaults: defaults)
    let result = try! migrator.migrateIfNeeded()

    assertTrue(
        result.config.isEnabled(FeatureID.switcher) == false,
        "⌘Tab 接管的旧默认是关闭")
    assertTrue(
        result.config.isEnabled(FeatureID.capsLayer) == true,
        "Caps 层旧默认是开启")
    assertTrue(
        result.config.features[FeatureID.switcher]?.values["mouseFollow"] == .bool(true),
        "鼠标跟随应迁到 switcher.values.mouseFollow")
    assertTrue(
        result.config.features[FeatureID.mouseLayer] == nil,
        "未设置的 menu.isVolumeEnabled 不应创建节点")
    print("testMigratorImportsUserDefaults passed")
}

func testMigratorKeepsLegacyFilesWhenSaveFails() {
    // 回归测试：save 失败时不能把旧文件改名。
    // 如果先改名后落盘，save 抛错就会「迁移出空配置」——
    // 旧文件全在 .migrated、config.json 不存在，下次启动迁移出空配置且永不再迁。
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-migrate-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let capsURL = tempDir.appendingPathComponent("caps-mappings.json")
    try! #"{"version":1,"mappings":[{"from":"e","to":{"key":"up_arrow"}}]}"#.write(
        to: capsURL, atomically: true, encoding: .utf8)

    // 让 save 必然失败：/dev/null 下面无法建目录
    let brokenStore = ConfigStore(fileURL: URL(fileURLWithPath: "/dev/null/config.json"))
    let migrator = ConfigMigrator(directory: tempDir, store: brokenStore)

    var threw = false
    do {
        _ = try migrator.migrateIfNeeded()
    } catch {
        threw = true
    }

    assertTrue(threw, "save 失败时 migrateIfNeeded 应抛错")
    assertTrue(
        FileManager.default.fileExists(atPath: capsURL.path),
        "save 失败时旧文件必须留在原路径，否则下次启动迁移出空配置")
    assertTrue(
        !FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("caps-mappings.json.migrated").path),
        "save 失败时不应产生 .migrated 文件")
    print("testMigratorKeepsLegacyFilesWhenSaveFails passed")
}

func testFeatureDefaultEnabledDeclaredByFeature() {
    // 未配置过的功能应使用 Feature 自己声明的默认值，
    // 而不是硬编码 true——switcher 和 mouseFollow 的旧默认是 false。
    let config = TonyToyConfig.default

    assertTrue(
        config.isEnabled("switcher", defaultEnabled: false) == false,
        "⌘Tab 接管旧默认关闭，未配置时应为 false")
    assertTrue(
        config.isEnabled("capsLayer", defaultEnabled: true) == true,
        "Caps 层旧默认开启")

    // 已配置过的功能，配置值优先
    var configured = config
    configured.features["switcher"] = FeatureConfig(isEnabled: true, values: [:])
    assertTrue(
        configured.isEnabled("switcher", defaultEnabled: false) == true,
        "配置值应优先于默认值")
    print("testFeatureDefaultEnabledDeclaredByFeature passed")
}

func testFeatureProtocolDefaults() {
    // 一个最小的 Feature 实现，验证协议默认实现
    final class StubFeature: Feature {
        let id = "stub"
        let title = "桩"
        let icon = "questionmark"
        var settings: [SettingItem] { [] }
        var defaultEnabled: Bool { false }
        private(set) var started = false
        private(set) var stopped = false
        private(set) var appliedValues: [FeatureConfig] = []

        func start() { started = true }
        func stop() { stopped = true }
        func applyValues(_ config: FeatureConfig) { appliedValues.append(config) }
    }

    let feature = StubFeature()

    // 开关打开：先启动，再应用 values
    feature.apply(FeatureConfig(isEnabled: true, values: ["pageSize": .int(8)]))
    assertTrue(feature.started, "isEnabled = true 应调用 start()")
    assertTrue(feature.appliedValues.count == 1, "开启时应调用 applyValues 一次")
    assertTrue(
        feature.appliedValues.first?.values["pageSize"] == .int(8),
        "applyValues 应收到完整配置")

    // 开关关闭：只停止，不应用 values
    feature.apply(FeatureConfig(isEnabled: false, values: ["pageSize": .int(4)]))
    assertTrue(feature.stopped, "isEnabled = false 应调用 stop()")
    assertTrue(
        feature.appliedValues.count == 1,
        "关闭时不应调用 applyValues（停止后再应用配置没有意义）")
    print("testFeatureProtocolDefaults passed")
}

func testTemplateApplyCannotBeBypassed() {
    // 即使某个 Feature 错误地覆盖了 apply，通过协议调用仍走模板方法。
    // 这是模板方法模式的核心保护——调用方只持有 Feature 协议类型。
    final class RogueFeature: Feature {
        let id = "rogue"
        let title = "越权"
        let icon = "exclamationmark"
        var settings: [SettingItem] { [] }
        var defaultEnabled: Bool { true }
        private(set) var started = false

        func start() { started = true }
        func stop() {}

        /// 故意覆盖 apply 但不做启停（模拟「忘记调默认实现」）
        func apply(_ config: FeatureConfig) {
            // 什么都不做
        }
    }

    let rogue = RogueFeature()
    let asProtocol: Feature = rogue

    // 通过协议调用：扩展的模板方法优先（静态派发到扩展）
    asProtocol.apply(FeatureConfig(isEnabled: true))
    assertTrue(
        rogue.started,
        "通过协议调用应走扩展的模板方法，即使具体类型覆盖了 apply")

    print("testTemplateApplyCannotBeBypassed passed")
}

func testConfigStoreRejectsFutureVersion() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("config.json")
    // 写一个未来版本的配置
    let futureJSON = #"{"version":999,"general":{},"features":{}}"#
    try! futureJSON.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = ConfigStore(fileURL: fileURL)

    var thrown: ConfigError?
    do {
        _ = try store.load()
    } catch let error as ConfigError {
        thrown = error
    } catch {
        assertTrue(false, "应抛 ConfigError，实际: \(error)")
    }

    guard case .futureVersion(let version)? = thrown else {
        assertTrue(false, "应抛 futureVersion，实际: \(String(describing: thrown))")
        return
    }
    assertTrue(version == 999, "应带出实际版本号")

    // 重要：不能备份也不能删除文件——用户的数据必须原样保留
    assertTrue(
        FileManager.default.fileExists(atPath: fileURL.path),
        "版本过高时不能动用户文件")
    print("testConfigStoreRejectsFutureVersion passed")
}

func testConfigStoreAcceptsCurrentVersion() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("config.json")
    let store = ConfigStore(fileURL: fileURL)
    try! store.save(.default)

    // 当前版本必须能正常读
    let config = try! store.load()
    assertTrue(config.version == TonyToyConfig.currentVersion, "当前版本应可读")
    print("testConfigStoreAcceptsCurrentVersion passed")
}

func testRegistryRegistersAndDeduplicates() {
    final class StubFeature: Feature {
        let id: String
        let title: String
        let icon = "questionmark"
        var settings: [SettingItem] { [] }
        var defaultEnabled: Bool
        private(set) var appliedConfigs: [FeatureConfig] = []

        init(id: String, defaultEnabled: Bool = true) {
            self.id = id
            self.title = id
            self.defaultEnabled = defaultEnabled
        }

        func start() {}
        func stop() {}
        func applyValues(_ config: FeatureConfig) { appliedConfigs.append(config) }
    }

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let registry = FeatureRegistry(store: store)

    let a = StubFeature(id: "alpha")
    registry.register(a)
    registry.register(StubFeature(id: "alpha"))  // 重复
    registry.register(StubFeature(id: "beta"))

    assertTrue(registry.allFeatures.count == 2, "重复 id 应被忽略")
    print("testRegistryRegistersAndDeduplicates passed")
}

func testRegistryFillsDefaultEnabled() {
    // 损坏回退后 features 为空，每个 Feature 应拿到自己声明的 defaultEnabled
    final class StubFeature: Feature {
        let id: String
        let title: String
        let icon = "questionmark"
        var settings: [SettingItem] { [] }
        let defaultEnabled: Bool

        init(id: String, defaultEnabled: Bool) {
            self.id = id
            self.title = id
            self.defaultEnabled = defaultEnabled
        }

        func start() {}
        func stop() {}
    }

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let registry = FeatureRegistry(store: store)

    // 旧默认关闭的功能（switcher 类比）
    registry.register(StubFeature(id: "switcher", defaultEnabled: false))
    // 旧默认开启的功能（capsLayer 类比）
    registry.register(StubFeature(id: "capsLayer", defaultEnabled: true))

    // 空配置（模拟损坏回退）
    let normalized = registry.normalizedConfig(TonyToyConfig.default)

    assertTrue(
        normalized.isEnabled("switcher", defaultEnabled: false) == false,
        "旧默认关闭的功能补齐后仍为关闭")
    assertTrue(
        normalized.isEnabled("capsLayer", defaultEnabled: true) == true,
        "旧默认开启的功能补齐后为开启")
    assertTrue(normalized.features.count == 2, "应补齐 2 个功能节点")
    print("testRegistryFillsDefaultEnabled passed")
}

func testRegistryKeepsExistingConfig() {
    // 已有配置不能被默认值覆盖
    final class StubFeature: Feature {
        let id = "switcher"
        let title = "切换器"
        let icon = "questionmark"
        var settings: [SettingItem] { [] }
        let defaultEnabled = false
        func start() {}
        func stop() {}
    }

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let registry = FeatureRegistry(store: store)
    registry.register(StubFeature())

    var config = TonyToyConfig.default
    config.features["switcher"] = FeatureConfig(isEnabled: true, values: ["k": .int(1)])

    let normalized = registry.normalizedConfig(config)
    assertTrue(
        normalized.isEnabled("switcher", defaultEnabled: false) == true,
        "已有配置优先于默认值，不能被覆盖")
    assertTrue(
        normalized.features["switcher"]?.values["k"] == .int(1),
        "已有 values 应保留")
    print("testRegistryKeepsExistingConfig passed")
}

@main
struct ConfigStoreTests {
    static func main() {
        testConfigDefaults()
        testConfigRoundTrip()
        testFeatureEnabledLookup()
        testConfigToleratesMissingFields()
        testFeatureConfigToleratesMissingFields()
        testConfigEmptyFeaturesByDefault()
        testConfigStoreSaveAndLoad()
        testConfigStoreCreatesDirectory()
        testConfigStoreCorruptedFile()
        testMigratorImportsMappingFiles()
        testMigratorImportsInputAliases()
        testMigratorPreservesActivationButton()
        testMigratorRenamesLegacyFilesAndIsIdempotent()
        testUpdateFeatureNotifiesAndPersists()
        testMigratorImportsUserDefaults()
        testMigratorKeepsLegacyFilesWhenSaveFails()
        testFeatureDefaultEnabledDeclaredByFeature()
        testFeatureProtocolDefaults()
        testTemplateApplyCannotBeBypassed()
        testConfigStoreRejectsFutureVersion()
        testConfigStoreAcceptsCurrentVersion()
        testRegistryRegistersAndDeduplicates()
        testRegistryFillsDefaultEnabled()
        testRegistryKeepsExistingConfig()
        print("ConfigStoreTests all passed")
    }
}

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        print("❌ \(message)")
        exit(1)
    }
}
