import Foundation

/// 把旧配置文件迁移到统一的 config.json。
///
/// 策略：
/// - `config.json` 已存在 → 不动，直接返回。
/// - 旧文件保留（重命名为 `.migrated`），迁移出错时用户能恢复。
/// - 迁移幂等：第二次调用时旧文件已不存在，直接返回。
///
/// **注意 4 个旧文件格式不同**：`hotkeys` / `caps-mappings` / `mouse-layer`
/// 都有 `mappings` 数组，但 `input-aliases` 是 4 个独立字典。
/// 统一按 `mappings` 处理会让别名静默丢失。
final class ConfigMigrator {
    struct Result {
        let config: TonyToyConfig
        let didMigrate: Bool
        /// 迁移成功的功能节点数（供测试断言）
        let migratedFeatureCount: Int
    }

    private let directory: URL
    private let store: ConfigStore

    /// 有 `mappings` 数组的文件 → 对应的 feature id
    private static let mappingFiles: [(fileName: String, featureID: String)] = [
        ("caps-mappings.json", FeatureID.capsLayer),
        ("hotkeys.json", FeatureID.hotkeyLayer),
        ("mouse-layer.json", FeatureID.mouseLayer),
    ]

    /// `input-aliases.json` 的 4 个字典：JSON 键名 → 配置键名
    private static let aliasSections: [(jsonKey: String, configKey: String)] = [
        ("keyboard_keys", "keyboardKeys"),
        ("modifiers", "modifiers"),
        ("mouse_inputs", "mouseInputs"),
        ("actions", "actions"),
    ]

    init(directory: URL, store: ConfigStore) {
        self.directory = directory
        self.store = store
    }

    func migrateIfNeeded() throws -> Result {
        let configURL = directory.appendingPathComponent("config.json")

        // 已经有统一配置，直接返回。
        // migratedFeatureCount 是「本次迁移了几个节点」，早退时必然是 0，
        // 不能返回 features.count——那会把「已有配置」误报成「刚迁移完」。
        if FileManager.default.fileExists(atPath: configURL.path) {
            let config = try store.load()
            return Result(
                config: config, didMigrate: false,
                migratedFeatureCount: 0)
        }

        var config = TonyToyConfig.default
        var migratedCount = 0

        // 1. 有 mappings 数组的三个文件
        for (fileName, featureID) in Self.mappingFiles {
            let fileURL = directory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            guard let data = try? Data(contentsOf: fileURL),
                let root = try? JSONDecoder().decode(JSONValue.self, from: data),
                let mappings = root.array("mappings")
            else {
                dbg("迁移跳过 \(fileName)：无法解析 mappings")
                continue
            }

            var values: [String: JSONValue] = ["mappings": .array(mappings)]

            // mouse-layer 的激活键：不迁过去侧键层功能就失效了
            if let activationButton = root.string("activation_button") {
                values["activationButton"] = .string(activationButton)
            }

            config.features[featureID] = FeatureConfig(isEnabled: true, values: values)
            migratedCount += 1
            moveToMigrated(fileURL)
            dbg("已迁移 \(fileName) → features.\(featureID)（\(mappings.count) 条）")
        }

        // 2. input-aliases.json：4 个独立字典，不是 mappings
        let aliasesURL = directory.appendingPathComponent("input-aliases.json")
        if FileManager.default.fileExists(atPath: aliasesURL.path),
            let data = try? Data(contentsOf: aliasesURL),
            let root = try? JSONDecoder().decode(JSONValue.self, from: data)
        {
            var values: [String: JSONValue] = [:]
            for (jsonKey, configKey) in Self.aliasSections {
                if let section = root.object(jsonKey) {
                    values[configKey] = .object(section)
                }
            }

            if !values.isEmpty {
                config.features[FeatureID.inputAliases] = FeatureConfig(
                    isEnabled: true, values: values)
                migratedCount += 1
                moveToMigrated(aliasesURL)
                dbg("已迁移 input-aliases.json（\(values.count) 个分组）")
            }
        }

        // 3. UserDefaults 里的旧布尔开关
        config = Self.migrateUserDefaults(into: config)

        try store.save(config)

        return Result(
            config: config, didMigrate: true, migratedFeatureCount: migratedCount)
    }

    // MARK: - 私有

    /// 保留旧文件为 `.migrated`，不删除——迁移出错时用户能恢复
    private func moveToMigrated(_ fileURL: URL) {
        let migratedURL = fileURL.appendingPathExtension("migrated")
        try? FileManager.default.removeItem(at: migratedURL)
        do {
            try FileManager.default.moveItem(at: fileURL, to: migratedURL)
        } catch {
            dbg("重命名 \(fileURL.lastPathComponent) 失败: \(error)")
        }
    }

    /// 把 MenuStateStore 的旧 UserDefaults key 迁到 features[*].isEnabled。
    ///
    /// 注意 `switcher` 和 `mouseFollow` 的旧默认是 **false**（不是 true），
    /// 这里只迁移「用户显式设置过」的值，未设置的交给 Feature 自己声明默认值。
    private static func migrateUserDefaults(into config: TonyToyConfig) -> TonyToyConfig {
        var config = config
        let defaults = UserDefaults.standard

        let mapping: [(legacyKey: String, featureID: String)] = [
            ("menu.isVolumeEnabled", FeatureID.mouseLayer),
            ("menu.isCapsEnabled", FeatureID.capsLayer),
            ("menu.isHotkeyEnabled", FeatureID.hotkeyLayer),
            ("menu.isCmdTabEnabled", FeatureID.switcher),
            ("menu.isGamepadHomeEnabled", FeatureID.gamepad),
        ]

        for (legacyKey, featureID) in mapping {
            guard defaults.object(forKey: legacyKey) != nil else { continue }
            var feature = config.features[featureID] ?? FeatureConfig()
            feature.isEnabled = defaults.bool(forKey: legacyKey)
            config.features[featureID] = feature
        }

        // 鼠标跟随是「窗口」分区的设置项，不是独立功能
        if defaults.object(forKey: "menu.isMouseFollowEnabled") != nil {
            var feature = config.features[FeatureID.switcher] ?? FeatureConfig()
            feature.values["mouseFollow"] = .bool(
                defaults.bool(forKey: "menu.isMouseFollowEnabled"))
            config.features[FeatureID.switcher] = feature
        }

        return config
    }
}
