# 配置重构第一阶段：Core 层与窗口骨架

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立统一配置模型（`config.json`）、`Feature` 抽象，以及可打开的空配置窗口，为后续 6 个阶段打地基。

**Architecture:** 新建 `src/Core/`（配置模型 + 存储 + 迁移 + 协议）与 `src/UI/Settings/`（窗口 + 侧边栏 + 空 Pane）。**不改动任何现有 Controller**——本阶段结束后应用行为与现在完全一致，只是多了一个能打开的空窗口。

**Tech Stack:** Swift 6（`swiftc` 直接编译，无 Xcode 工程）、AppKit、`Codable`、`XCTest` 替代方案（项目用 `assert` 手写断言，见 `tests/MenuStateStoreTests.swift`）。

**关键前提（已确认）：**
- `scripts/build.sh` 用 `find src -type f -name '*.swift'` 收集源文件，**新建子目录无需改构建脚本**。
- 测试用 `swiftc` 手动列文件编译后直接运行，新测试文件**必须**加到 `tests/run_all.sh`。
- **测试文件不能用顶层语句**：`swiftc` 多文件编译只允许 `main.swift` 有顶层代码。所有测试入口必须写成 `@main struct XXXTests { static func main() { ... } }`，与 `tests/MenuStateStoreTests.swift` 一致。
- **JSONValue 的已知限制**：`init(from:)` 按 Bool → Int → Double 顺序探测，所以整数值的 double（如 `1.0`）编码后解码回来会变成 `.int(1)`。**测试里不要用整数值的 double 做往返断言**，用 `3.14` 这类真小数。若将来某个 Feature 需要严格区分 int/double，需要改探测策略（用 `NSNumber` 判断），本阶段不处理。
- 项目没有第三方依赖，不要引入 SPM。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `src/Core/JSONValue.swift` | 通用 JSON 值（异构配置的载体） |
| `src/Core/TonyToyConfig.swift` | 统一配置模型（`TonyToyConfig` / `GeneralConfig` / `FeatureConfig` / `ThemePreference`） |
| `src/Core/ConfigStore.swift` | 读写 `~/.config/tony-toy/config.json`，变更通知 |
| `src/Core/ConfigMigrator.swift` | 从 5 个旧文件迁移到统一配置 |
| `src/Core/Feature.swift` | `Feature` 协议 + `SettingItem` 描述 |
| `src/Core/FeatureRegistry.swift` | 功能注册表 |
| `src/UI/Settings/SettingsWindowController.swift` | 配置窗口（侧边栏 + 内容区） |
| `src/UI/Settings/SettingsPaneViewController.swift` | Pane 基类 |
| `src/UI/Settings/Panes/*.swift` | 9 个空分区视图 |
| `tests/JSONValueTests.swift` | JSONValue 编解码测试 |
| `tests/ConfigStoreTests.swift` | 配置读写 + 迁移测试 |

---

## 审查遗留项（各任务的验收附加条件）

代码质量审查在各阶段提出的跟进项，必须在该任务完成时兑现，否则会成为永久技术债。

| 来源 | 事项 | 兑现位置 |
|---|---|---|
| Task 3 审查 | 补 `updateFeature` + `onChange` 测试：回调触发时磁盘已是新值、未触碰字段被保留 | Task 4 测试步骤 |
| Task 3 审查 | 兑现 `load() throws` 决策：引入真实抛错场景（版本不兼容/迁移失败），或降级为不抛 | Task 6 验收 |
| Task 3 审查 | **语义一致性**：设计文档写「`save()` → 落盘 → 通知 Feature」，但实现只有 `updateFeature` 触发 `onChange`。配置窗口保存必须走 `updateFeature`，或在 save 后显式广播，否则热更新静默失效 | Task 7-8 前拍板 |
| Task 2 审查 | 默认值归属：`isEnabled` 的 `?? true` 对 `switcher`/`mouseFollow` 与旧默认相反（旧为 `false`）。应由 Feature 自己声明默认值 | Task 5 设计协议时裁决 |

---

### Task 1: JSONValue 类型

**Files:**
- Create: `src/Core/JSONValue.swift`
- Create: `tests/JSONValueTests.swift`
- Modify: `tests/run_all.sh`（新增编译与运行块）

- [ ] **Step 1: 写失败的测试**

创建 `tests/JSONValueTests.swift`：

```swift
import Foundation

func testJSONValueRoundTrip() {
    let original: JSONValue = .object([
        "bool": .bool(true),
        "int": .int(42),
        "double": .double(3.14),
        "string": .string("你好"),
        "array": .array([.int(1), .int(2)]),
        "null": .null,
    ])

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try! encoder.encode(original)

    let decoded = try! JSONDecoder().decode(JSONValue.self, from: data)
    assertTrue(decoded == original, "往返编解码应保持不变")
    print("testJSONValueRoundTrip passed")
}

func testJSONValueFromBareJSON() {
    // 原始 JSON 里没有类型包裹，应自动推断
    let json = #"{"a": 1, "b": "x", "c": [true], "d": null}"#.data(using: .utf8)!
    let decoded = try! JSONDecoder().decode(JSONValue.self, from: json)

    guard case .object(let dict) = decoded else {
        assertionFailure("顶层应为 object")
        return
    }
    assertTrue(dict["a"] == .int(1), "整数应解析为 .int")
    assertTrue(dict["b"] == .string("x"), "字符串应解析为 .string")
    assertTrue(dict["c"] == .array([.bool(true)]), "数组应解析为 .array")
    assertTrue(dict["d"] == .null, "null 应解析为 .null")
    print("testJSONValueFromBareJSON passed")
}

func testJSONValueAccessors() {
    let object: JSONValue = .object([
        "enabled": .bool(false),
        "count": .int(8),
        "name": .string("启动器"),
    ])

    assertTrue(object.bool("enabled") == false, "bool 取值")
    assertTrue(object.int("count") == 8, "int 取值")
    assertTrue(object.string("name") == "启动器", "string 取值")
    assertTrue(object.bool("missing") == nil, "缺失 key 返回 nil")
    assertTrue(object.bool("name") == nil, "类型不匹配返回 nil")
    print("testJSONValueAccessors passed")
}

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        print("❌ \(message)")
        exit(1)
    }
}

@main
struct JSONValueTests {
    static func main() {
        testJSONValueRoundTrip()
        testJSONValueFromBareJSON()
        testJSONValueAccessors()
        print("JSONValueTests all passed")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swiftc src/Core/JSONValue.swift tests/JSONValueTests.swift -o /tmp/jsonvalue-tests 2>&1 | head -5`
Expected: FAIL，报错 `cannot find type 'JSONValue' in scope`

- [ ] **Step 3: 实现 JSONValue**

创建 `src/Core/JSONValue.swift`：

```swift
import Foundation

/// 通用 JSON 值，用于承载各 Feature 的异构配置。
///
/// 为什么不用泛型枚举：Caps 层、全局快捷键层、鼠标层三个映射表结构各不相同
/// （来源分别是单字符、组合键、侧键），统一成一个枚举会引入大量 switch 和
/// 可选字段，比异构字典更难维护。各 Feature 在 apply 时自己解码成强类型。
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "无法识别的 JSON 值")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - 便捷取值

extension JSONValue {
    func bool(_ key: String) -> Bool? {
        guard case .object(let dict) = self, case .bool(let value)? = dict[key] else { return nil }
        return value
    }

    func int(_ key: String) -> Int? {
        guard case .object(let dict) = self, case .int(let value)? = dict[key] else { return nil }
        return value
    }

    func double(_ key: String) -> Double? {
        guard case .object(let dict) = self else { return nil }
        switch dict[key] {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    func string(_ key: String) -> String? {
        guard case .object(let dict) = self, case .string(let value)? = dict[key] else { return nil }
        return value
    }

    func array(_ key: String) -> [JSONValue]? {
        guard case .object(let dict) = self, case .array(let value)? = dict[key] else { return nil }
        return value
    }

    func object(_ key: String) -> [String: JSONValue]? {
        guard case .object(let dict) = self, case .object(let value)? = dict[key] else { return nil }
        return value
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swiftc src/Core/JSONValue.swift tests/JSONValueTests.swift -o /tmp/jsonvalue-tests && /tmp/jsonvalue-tests`
Expected: 输出 `JSONValueTests all passed`

- [ ] **Step 5: 加入 run_all.sh**

修改 `tests/run_all.sh`，在 `swiftc "$REPO_ROOT/src/PasswordEntry.swift" \` 那一段**之前**插入：

```bash
swiftc "$REPO_ROOT/src/Core/JSONValue.swift" \
       "$REPO_ROOT/tests/JSONValueTests.swift" \
       -o /tmp/jsonvalue-tests
/tmp/jsonvalue-tests

```

- [ ] **Step 6: 运行全量测试**

Run: `just test 2>&1 | tail -5`
Expected: 最后一行 `all tests passed`

- [ ] **Step 7: 提交**

```bash
git add src/Core/JSONValue.swift tests/JSONValueTests.swift tests/run_all.sh
git commit -m "feat(core): 新增 JSONValue 通用 JSON 值类型"
```

---

### Task 2: 统一配置模型

**Files:**
- Create: `src/Core/TonyToyConfig.swift`
- Modify: `tests/ConfigStoreTests.swift`（新建，本任务只测模型）

- [ ] **Step 1: 写失败的测试**

创建 `tests/ConfigStoreTests.swift`：

```swift
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

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        print("❌ \(message)")
        exit(1)
    }
}

@main
struct ConfigStoreTests {
    static func main() {
        testConfigDefaults()
        testConfigRoundTrip()
        testFeatureEnabledLookup()
        print("ConfigStoreTests all passed")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swiftc src/Core/TonyToyConfig.swift tests/ConfigStoreTests.swift -o /tmp/config-tests 2>&1 | head -5`
Expected: FAIL，报错 `cannot find type 'TonyToyConfig' in scope`

- [ ] **Step 3: 实现配置模型**

创建 `src/Core/TonyToyConfig.swift`：

```swift
import Foundation

/// 全应用统一配置。
///
/// 所有功能配置收敛到这一个结构，序列化为 `~/.config/tony-toy/config.json`。
/// 密码库（vault.jsonl）不在此列——它是独立的安全边界。
struct TonyToyConfig: Codable, Equatable {
    /// 配置格式版本，用于迁移。新增不兼容字段时 +1。
    var version: Int

    var general: GeneralConfig

    /// key 是 Feature.id，例如 "capsLayer" / "gamepad"
    var features: [String: FeatureConfig]

    static let `default` = TonyToyConfig(
        version: 1,
        general: GeneralConfig(),
        features: [:]
    )

    /// 读取某功能的开关状态。未配置过的功能默认启用（保持升级前后行为一致）。
    func isEnabled(_ featureID: String) -> Bool {
        features[featureID]?.isEnabled ?? true
    }
}

struct GeneralConfig: Codable, Equatable {
    var launchAtLogin: Bool
    var theme: ThemePreference
    var showMenuBarIcon: Bool

    init(
        launchAtLogin: Bool = false,
        theme: ThemePreference = .system,
        showMenuBarIcon: Bool = true
    ) {
        self.launchAtLogin = launchAtLogin
        self.theme = theme
        self.showMenuBarIcon = showMenuBarIcon
    }
}

/// 单个功能的配置：开关 + 任意键值对。
///
/// `values` 用 JSONValue 承载而不是泛型，因为各功能的配置结构差异很大
/// （映射表 vs 单个数字 vs 快捷键）。Feature 在 apply 时自己解码。
struct FeatureConfig: Codable, Equatable {
    var isEnabled: Bool
    var values: [String: JSONValue]

    init(isEnabled: Bool = true, values: [String: JSONValue] = [:]) {
        self.isEnabled = isEnabled
        self.values = values
    }
}

/// 主题偏好。system 表示跟随系统外观。
enum ThemePreference: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swiftc src/Core/JSONValue.swift src/Core/TonyToyConfig.swift tests/ConfigStoreTests.swift -o /tmp/config-tests && /tmp/config-tests`
Expected: 输出 `ConfigStoreTests all passed`

- [ ] **Step 5: 加入 run_all.sh**

在 Task 1 插入的块**之后**追加：

```bash
swiftc "$REPO_ROOT/src/Core/JSONValue.swift" \
       "$REPO_ROOT/src/Core/TonyToyConfig.swift" \
       "$REPO_ROOT/tests/ConfigStoreTests.swift" \
       -o /tmp/config-tests
/tmp/config-tests

```

- [ ] **Step 6: 提交**

```bash
git add src/Core/TonyToyConfig.swift tests/ConfigStoreTests.swift tests/run_all.sh
git commit -m "feat(core): 新增统一配置模型 TonyToyConfig"
```

---

### Task 3: ConfigStore 读写

**Files:**
- Create: `src/Core/ConfigStore.swift`
- Modify: `tests/ConfigStoreTests.swift`

- [ ] **Step 1: 写失败的测试**

在 `tests/ConfigStoreTests.swift` 的 `assertTrue` 函数**之前**插入：

```swift
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
    print("testConfigStoreCorruptedFile passed")
}

```

在 `ConfigStoreTests.main()` 里追加调用：

```swift
        testConfigStoreSaveAndLoad()
        testConfigStoreCreatesDirectory()
        testConfigStoreCorruptedFile()
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swiftc src/Core/JSONValue.swift src/Core/TonyToyConfig.swift tests/ConfigStoreTests.swift -o /tmp/config-tests 2>&1 | head -5`
Expected: FAIL，报错 `cannot find type 'ConfigStore' in scope`

- [ ] **Step 3: 实现 ConfigStore**

创建 `src/Core/ConfigStore.swift`：

```swift
import Foundation

/// 统一配置的读写入口。
///
/// 设计要点：
/// - 文件损坏时**备份**而不是静默丢弃，用户能找回配置。
/// - 写入用原子替换（`.atomic`），避免断电写坏文件。
/// - 变更通过 `onChange` 通知，各 Feature 收到后热更新，无需重启。
final class ConfigStore {
    static let shared = ConfigStore()

    /// 默认路径：~/.config/tony-toy/config.json
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tony-toy/config.json")
    }

    private let fileURL: URL

    /// 配置变更回调（主线程）
    var onChange: ((TonyToyConfig) -> Void)?

    init(fileURL: URL = ConfigStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// 读取配置。文件不存在或损坏时返回默认值（不抛错，保证启动不失败）。
    func load() throws -> TonyToyConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            dbg("配置读取失败，使用默认值: \(error)")
            return .default
        }

        do {
            return try JSONDecoder().decode(TonyToyConfig.self, from: data)
        } catch {
            dbg("配置解析失败，已备份并回退默认值: \(error)")
            backupCorruptedFile()
            return .default
        }
    }

    /// 写入配置。调用方负责保证 config 合法。
    func save(_ config: TonyToyConfig) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)

        dbg("配置已保存到 \(fileURL.path)")
    }

    /// 更新单项功能配置并落盘 + 通知
    func updateFeature(_ featureID: String, _ mutate: (inout FeatureConfig) -> Void) throws {
        var config = try load()
        var feature = config.features[featureID] ?? FeatureConfig()
        mutate(&feature)
        config.features[featureID] = feature
        try save(config)
        onChange?(config)
    }

    // MARK: - 私有

    private func backupCorruptedFile() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("config.json.corrupted.\(timestamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swiftc src/Core/JSONValue.swift src/Core/TonyToyConfig.swift src/Core/ConfigStore.swift src/DebugLog.swift tests/ConfigStoreTests.swift -o /tmp/config-tests && /tmp/config-tests`
Expected: 输出 `ConfigStoreTests all passed`

> 注意：编译需要 `DebugLog.swift`（`dbg()` 定义）。`run_all.sh` 里也要加。

- [ ] **Step 5: 更新 run_all.sh**

把 Task 2 插入的编译块改为：

```bash
swiftc "$REPO_ROOT/src/Core/JSONValue.swift" \
       "$REPO_ROOT/src/Core/TonyToyConfig.swift" \
       "$REPO_ROOT/src/Core/ConfigStore.swift" \
       "$REPO_ROOT/src/DebugLog.swift" \
       "$REPO_ROOT/tests/ConfigStoreTests.swift" \
       -o /tmp/config-tests
/tmp/config-tests

```

- [ ] **Step 6: 提交**

```bash
git add src/Core/ConfigStore.swift tests/ConfigStoreTests.swift tests/run_all.sh
git commit -m "feat(core): 新增 ConfigStore 读写与损坏备份"
```

---

### Task 4: 配置迁移

**Files:**
- Create: `src/Core/ConfigMigrator.swift`
- Modify: `tests/ConfigStoreTests.swift`

- [ ] **Step 1: 写失败的测试**

在 `tests/ConfigStoreTests.swift` 的 `assertTrue` 之前插入：

```swift
func testMigratorImportsLegacyFiles() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-migrate-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // 造三个旧格式文件
    let capsJSON = """
    {"version":1,"mappings":[{"from":"e","to":{"key":"up_arrow"}}]}
    """
    try! capsJSON.write(
        to: tempDir.appendingPathComponent("caps-mappings.json"),
        atomically: true, encoding: .utf8)

    let hotkeysJSON = """
    {"version":1,"mappings":[{"from":{"key":"escape","modifiers":["command"]},
    "to":{"key":"grave_accent_and_tilde","modifiers":["command"]}}]}
    """
    try! hotkeysJSON.write(
        to: tempDir.appendingPathComponent("hotkeys.json"),
        atomically: true, encoding: .utf8)

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let migrator = ConfigMigrator(directory: tempDir, store: store)

    let migrated = try! migrator.migrateIfNeeded()

    assertTrue(migrated.capitalLayerMappingCount == 1, "Caps 层应迁入 1 条")
    assertTrue(migrated.config.features["capsLayer"] != nil, "应生成 capsLayer 节点")
    assertTrue(migrated.config.features["hotkeyLayer"] != nil, "应生成 hotkeyLayer 节点")

    // 旧文件应重命名，不再存在原路径
    assertTrue(
        !FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("caps-mappings.json").path),
        "旧文件应被重命名")
    assertTrue(
        FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("caps-mappings.json.migrated").path),
        "旧文件应保留为 .migrated")
    print("testMigratorImportsLegacyFiles passed")
}

func testMigratorIsIdempotent() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tonytoy-migrate-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = ConfigStore(fileURL: tempDir.appendingPathComponent("config.json"))
    let migrator = ConfigMigrator(directory: tempDir, store: store)

    _ = try! migrator.migrateIfNeeded()
    let configAfterFirst = try! store.load()

    // 第二次调用不应改变任何东西
    _ = try! migrator.migrateIfNeeded()
    let configAfterSecond = try! store.load()

    assertTrue(configAfterFirst == configAfterSecond, "重复迁移应幂等")
    print("testMigratorIsIdempotent passed")
}

```

在 `ConfigStoreTests.main()` 里追加调用：

```swift
        testMigratorImportsLegacyFiles()
        testMigratorIsIdempotent()
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swiftc ... 2>&1 | head -5`（用 Step 5 的完整命令）
Expected: FAIL，报错 `cannot find type 'ConfigMigrator' in scope`

- [ ] **Step 3: 实现 ConfigMigrator**

创建 `src/Core/ConfigMigrator.swift`：

```swift
import Foundation

/// 把 5 个旧配置文件迁移到统一的 config.json。
///
/// 策略：
/// - config.json 已存在 → 不动，直接返回。
/// - 旧文件保留（重命名为 .migrated），迁移出错时用户能恢复。
/// - 迁移幂等：第二次调用时旧文件已不存在，直接返回。
final class ConfigMigrator {
    struct Result {
        let config: TonyToyConfig
        let didMigrate: Bool
        /// 迁移成功的 Caps 映射条数（供测试断言）
        let capitalLayerMappingCount: Int
    }

    private let directory: URL
    private let store: ConfigStore

    /// 旧文件名 → 在新配置里的 feature id
    private static let legacyFiles: [(fileName: String, featureID: String)] = [
        ("caps-mappings.json", "capsLayer"),
        ("hotkeys.json", "hotkeyLayer"),
        ("mouse-layer.json", "mouseLayer"),
        ("input-aliases.json", "inputAliases"),
    ]

    init(directory: URL, store: ConfigStore) {
        self.directory = directory
        self.store = store
    }

    func migrateIfNeeded() throws -> Result {
        let configURL = directory.appendingPathComponent("config.json")

        // 已经有统一配置，直接返回
        if FileManager.default.fileExists(atPath: configURL.path) {
            let config = try store.load()
            return Result(
                config: config, didMigrate: false,
                capitalLayerMappingCount: Self.mappingCount(in: config, featureID: "capsLayer"))
        }

        var config = TonyToyConfig.default
        var capsMappingCount = 0

        for (fileName, featureID) in Self.legacyFiles {
            let fileURL = directory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            guard let data = try? Data(contentsOf: fileURL),
                let root = try? JSONDecoder().decode(JSONValue.self, from: data),
                let mappings = root.array("mappings")
            else {
                dbg("迁移跳过 \(fileName)：无法解析 mappings")
                continue
            }

            config.features[featureID] = FeatureConfig(
                isEnabled: true,
                values: ["mappings": .array(mappings)]
            )

            if featureID == "capsLayer" {
                capsMappingCount = mappings.count
            }

            // 保留旧文件为 .migrated，不删除
            let migratedURL = fileURL.appendingPathExtension("migrated")
            try? FileManager.default.removeItem(at: migratedURL)
            try? FileManager.default.moveItem(at: fileURL, to: migratedURL)

            dbg("已迁移 \(fileName) → features.\(featureID)（\(mappings.count) 条）")
        }

        // 迁移 UserDefaults 里的 8 个布尔开关
        config = Self.migrateUserDefaults(into: config)

        try store.save(config)

        return Result(
            config: config, didMigrate: true,
            capitalLayerMappingCount: capsMappingCount)
    }

    // MARK: - 私有

    /// 把 MenuStateStore 的旧 UserDefaults key 迁到 features[*].isEnabled。
    /// 保留读取作为兜底，避免升级后开关状态丢失。
    private static func migrateUserDefaults(into config: TonyToyConfig) -> TonyToyConfig {
        var config = config
        let defaults = UserDefaults.standard

        let mapping: [(legacyKey: String, featureID: String)] = [
            ("menu.isVolumeEnabled", "mouseLayer"),
            ("menu.isCapsEnabled", "capsLayer"),
            ("menu.isHotkeyEnabled", "hotkeyLayer"),
            ("menu.isCmdTabEnabled", "switcher"),
            ("menu.isGamepadHomeEnabled", "gamepad"),
        ]

        for (legacyKey, featureID) in mapping {
            guard defaults.object(forKey: legacyKey) != nil else { continue }
            let enabled = defaults.bool(forKey: legacyKey)
            var feature = config.features[featureID] ?? FeatureConfig()
            feature.isEnabled = enabled
            config.features[featureID] = feature
        }

        // 鼠标跟随是「窗口」分区的设置项，不是独立功能
        if defaults.object(forKey: "menu.isMouseFollowEnabled") != nil {
            var feature = config.features["switcher"] ?? FeatureConfig()
            feature.values["mouseFollow"] = .bool(defaults.bool(forKey: "menu.isMouseFollowEnabled"))
            config.features["switcher"] = feature
        }

        return config
    }

    private static func mappingCount(in config: TonyToyConfig, featureID: String) -> Int {
        guard let value = config.features[featureID]?.values["mappings"],
            case .array(let mappings) = value
        else { return 0 }
        return mappings.count
    }
}

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
swiftc src/Core/JSONValue.swift src/Core/TonyToyConfig.swift \
       src/Core/ConfigStore.swift src/Core/ConfigMigrator.swift \
       src/DebugLog.swift tests/ConfigStoreTests.swift \
       -o /tmp/config-tests && /tmp/config-tests
```
Expected: 输出 `ConfigStoreTests all passed`

- [ ] **Step 5: 更新 run_all.sh**

在 Task 3 的 swiftc 调用里加上 `"$REPO_ROOT/src/Core/ConfigMigrator.swift" \`。

- [ ] **Step 6: 提交**

```bash
git add src/Core/ConfigMigrator.swift tests/ConfigStoreTests.swift tests/run_all.sh
git commit -m "feat(core): 新增配置迁移，自动导入 5 个旧文件"
```

---

### Task 5: Feature 协议

**Files:**
- Create: `src/Core/Feature.swift`

- [ ] **Step 1: 实现协议**

创建 `src/Core/Feature.swift`：

```swift
import Foundation

/// 一个可配置的功能单元。
///
/// 新增功能只需实现这个协议 + 在 FeatureRegistry 注册一行，
/// 配置窗口自动获得侧边栏条目和设置项绑定。
protocol Feature: AnyObject {
    /// 唯一标识，同时作为 config.json 里 features 的 key
    var id: String { get }

    /// 侧边栏显示名
    var title: String { get }

    /// SF Symbols 图标名
    var icon: String { get }

    /// 设置项声明。界面据此渲染控件，不描述布局。
    var settings: [SettingItem] { get }

    /// 启动：注册事件 tap、建立 AX 连接等
    func start()

    /// 停止：注销 tap、释放资源
    func stop()

    /// 配置变更后热更新。默认实现按 isEnabled 启停。
    func apply(_ config: FeatureConfig)
}

extension Feature {
    /// 默认实现：开关切换时启停，子类可覆盖以处理更细的配置
    func apply(_ config: FeatureConfig) {
        if config.isEnabled {
            start()
        } else {
            stop()
        }
    }
}

/// 设置项类型描述。只声明「有什么配置、什么类型、默认多少」，不管怎么摆。
enum SettingItem {
    case toggle(key: String, title: String, defaultValue: Bool)
    /// 组合键。复用 HotkeyMappingConfig.swift 里已有的 HotkeyKeySpec，
    /// 不重复定义——现有类型就是 { key: String, modifiers: [String]? }。
    case hotkey(key: String, title: String, defaultValue: HotkeyKeySpec)
    case number(key: String, title: String, defaultValue: Int, range: ClosedRange<Int>)
    case picker(
        key: String, title: String,
        options: [(value: String, label: String)], defaultValue: String)
    /// 映射表：界面用 MappingTableEditor 渲染（第三阶段实现）
    case table(key: String, title: String)
}
```

- [ ] **Step 2: 编译验证**

Run: `swiftc src/Core/JSONValue.swift src/Core/TonyToyConfig.swift src/Core/Feature.swift -o /tmp/feature-test 2>&1 | head -5`
Expected: 无错误（`-o` 需要 main，用 `swiftc -parse` 代替）

实际命令：
```bash
swiftc -parse src/Core/JSONValue.swift src/Core/TonyToyConfig.swift src/Core/Feature.swift && echo "语法 OK"
```
Expected: 输出 `语法 OK`

- [ ] **Step 3: 确认没有重复定义**

Run: `grep -rn "struct HotkeySpec\|struct HotkeyKeySpec" src/`
Expected: 只有 `src/LauncherSettings.swift`（HotkeySpec）和 `src/HotkeyMappingConfig.swift`（HotkeyKeySpec）两处。
本任务**不新增**任何按键类型定义——直接复用 `HotkeyKeySpec`。

- [ ] **Step 4: 提交**

```bash
git add src/Core/Feature.swift
git commit -m "feat(core): 新增 Feature 协议与设置项描述"
```

---

### Task 6: FeatureRegistry

**Files:**
- Create: `src/Core/FeatureRegistry.swift`

- [ ] **Step 1: 实现注册表**

创建 `src/Core/FeatureRegistry.swift`：

```swift
import Foundation

/// 功能注册表。应用启动时注册所有 Feature，
/// 配置窗口和菜单都从这里读，避免各处硬编码。
final class FeatureRegistry {
    static let shared = FeatureRegistry()

    private var features: [Feature] = []
    private let store = ConfigStore.shared

    private init() {}

    /// 注册一个功能。按注册顺序显示在侧边栏。
    func register(_ feature: Feature) {
        guard !features.contains(where: { $0.id == feature.id }) else {
            dbg("功能 \(feature.id) 重复注册，已忽略")
            return
        }
        features.append(feature)
    }

    var allFeatures: [Feature] { features }

    func feature(withID id: String) -> Feature? {
        features.first { $0.id == id }
    }

    /// 应用启动时调用：加载配置并启动所有启用的功能
    func startAll() {
        let config = (try? store.load()) ?? .default
        for feature in features {
            feature.apply(config.features[feature.id] ?? FeatureConfig())
        }

        // 配置外部变更时热更新
        store.onChange = { [weak self] newConfig in
            guard let self else { return }
            for feature in self.features {
                feature.apply(newConfig.features[feature.id] ?? FeatureConfig())
            }
        }
    }

    /// 应用退出时调用
    func stopAll() {
        for feature in features {
            feature.stop()
        }
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `swiftc -parse src/Core/*.swift src/DebugLog.swift && echo "语法 OK"`
Expected: 输出 `语法 OK`

- [ ] **Step 3: 提交**

```bash
git add src/Core/FeatureRegistry.swift
git commit -m "feat(core): 新增 FeatureRegistry 功能注册表"
```

---

### Task 7: 配置窗口骨架

**Files:**
- Create: `src/UI/Settings/SettingsPaneViewController.swift`
- Create: `src/UI/Settings/SettingsWindowController.swift`

- [ ] **Step 1: 实现 Pane 基类**

创建 `src/UI/Settings/SettingsPaneViewController.swift`：

```swift
import AppKit

/// 配置窗口右侧分区的基类。
///
/// 子类在 `viewDidLoad` 里往 `contentStack` 添加行。
/// 行统一用 `makeRow(title:control:)` 构造，保证全窗口样式一致。
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

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)
        scrollView.documentView = documentView

        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])

        view = container
    }

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
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
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
```

- [ ] **Step 2: 实现窗口控制器**

创建 `src/UI/Settings/SettingsWindowController.swift`：

```swift
import AppKit

/// 配置窗口：左侧侧边栏 + 右侧内容区。
///
/// 用 NSTableView 而不是 NSOutlineView——当前是扁平列表，
/// 将来要分组再加 OutlineView 不迟。
final class SettingsWindowController: NSWindowController {
    /// 侧边栏条目
    struct SidebarItem {
        let id: String
        let title: String
        let icon: String
        let makePane: () -> SettingsPaneViewController
    }

    private let items: [SidebarItem]
    private let sidebarTableView = NSTableView()
    private let contentContainer = NSView()
    private var currentPane: SettingsPaneViewController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TonyToy 设置"
        window.minSize = NSSize(width: 620, height: 440)
        window.center()
        window.setFrameAutosaveName("TonyToySettingsWindow")

        self.init(window: window)
        setupUI()
    }

    override init(window: NSWindow?) {
        self.items = Self.makeSidebarItems()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    // MARK: - 侧边栏条目

    private static func makeSidebarItems() -> [SidebarItem] {
        [
            SidebarItem(id: "general", title: "通用", icon: "gearshape") {
                GeneralPaneViewController()
            },
            SidebarItem(id: "capsLayer", title: "Caps 键层", icon: "capslock") {
                CapsLayerPaneViewController()
            },
            SidebarItem(id: "hotkeyLayer", title: "全局快捷键", icon: "command") {
                HotkeyLayerPaneViewController()
            },
            SidebarItem(id: "mouse", title: "鼠标", icon: "computermouse") {
                MousePaneViewController()
            },
            SidebarItem(id: "window", title: "窗口", icon: "macwindow") {
                WindowPaneViewController()
            },
            SidebarItem(id: "launcher", title: "启动器", icon: "magnifyingglass") {
                LauncherPaneViewController()
            },
            SidebarItem(id: "password", title: "密码管理器", icon: "lock") {
                PasswordPaneViewController()
            },
            SidebarItem(id: "gamepad", title: "手柄", icon: "gamecontroller") {
                GamepadPaneViewController()
            },
            SidebarItem(id: "about", title: "关于", icon: "info.circle") {
                AboutPaneViewController()
            },
        ]
    }

    // MARK: - UI

    private func setupUI() {
        guard let window, let contentView = window.contentView else { return }

        // 侧边栏
        let sidebarScroll = NSScrollView()
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.drawsBackground = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        column.width = 180
        sidebarTableView.addTableColumn(column)
        sidebarTableView.headerView = nil
        sidebarTableView.rowHeight = 32
        sidebarTableView.style = .sourceList
        sidebarTableView.selectionHighlightStyle = .regular
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self
        sidebarScroll.documentView = sidebarTableView

        // 内容容器
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(sidebarScroll)
        contentView.addSubview(separator)
        contentView.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            sidebarScroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebarScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebarScroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebarScroll.widthAnchor.constraint(equalToConstant: 180),

            separator.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor),
            separator.topAnchor.constraint(equalTo: contentView.topAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            contentContainer.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        sidebarTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showPane(at: 0)
    }

    private func showPane(at index: Int) {
        guard items.indices.contains(index) else { return }

        currentPane?.view.removeFromSuperview()
        currentPane?.removeFromParent()

        let pane = items[index].makePane()
        addChild(pane)
        pane.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(pane.view)

        NSLayoutConstraint.activate([
            pane.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            pane.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            pane.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            pane.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        currentPane = pane
    }
}

// MARK: - 表格数据源

extension SettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let item = items[row]

        let cell = NSTableCellView()

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: item.icon, accessibilityDescription: item.title)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: item.title)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        showPane(at: sidebarTableView.selectedRow)
    }
}
```

- [ ] **Step 3: 编译验证**

Run: `./scripts/build.sh 2>&1 | grep -E "✅|error" | head -5`
Expected: FAIL，因为 9 个 Pane 还没创建（`GeneralPaneViewController` 等未定义）

- [ ] **Step 4: 提交（先不编译通过，等 Task 8 补全 Pane）**

跳过提交，直接进 Task 8。

---

### Task 8: 九个空 Pane

**Files:**
- Create: `src/UI/Settings/Panes/GeneralPaneViewController.swift`
- Create: `src/UI/Settings/Panes/CapsLayerPaneViewController.swift`
- Create: `src/UI/Settings/Panes/HotkeyLayerPaneViewController.swift`
- Create: `src/UI/Settings/Panes/MousePaneViewController.swift`
- Create: `src/UI/Settings/Panes/WindowPaneViewController.swift`
- Create: `src/UI/Settings/Panes/LauncherPaneViewController.swift`
- Create: `src/UI/Settings/Panes/PasswordPaneViewController.swift`
- Create: `src/UI/Settings/Panes/GamepadPaneViewController.swift`
- Create: `src/UI/Settings/Panes/AboutPaneViewController.swift`

- [ ] **Step 1: 创建九个 Pane 文件**

每个文件结构相同，只有类名、标题、图标、占位文案不同。以下是 `GeneralPaneViewController.swift`：

```swift
import AppKit

final class GeneralPaneViewController: SettingsPaneViewController {
    init() {
        super.init(title: "通用", icon: "gearshape")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(makeSectionTitle("全局行为"))
        contentStack.addArrangedSubview(
            makePlaceholder("开机自启、主题、菜单栏图标将在第二阶段实现。"))
    }
}
```

其余 8 个文件按同样模式创建，替换下表的值：

| 文件名 | 类名 | title 参数 | icon 参数 | 占位文案 |
|---|---|---|---|---|
| `CapsLayerPaneViewController.swift` | `CapsLayerPaneViewController` | `"Caps 键层"` | `"capslock"` | `"Caps 层映射表将在第四阶段实现。"` |
| `HotkeyLayerPaneViewController.swift` | `HotkeyLayerPaneViewController` | `"全局快捷键"` | `"command"` | `"全局快捷键映射表将在第四阶段实现。"` |
| `MousePaneViewController.swift` | `MousePaneViewController` | `"鼠标"` | `"computermouse"` | `"鼠标侧键层配置将在第四阶段实现。"` |
| `WindowPaneViewController.swift` | `WindowPaneViewController` | `"窗口"` | `"macwindow"` | `"⌘Tab 接管与窗口平铺配置将在第二阶段实现。"` |
| `LauncherPaneViewController.swift` | `LauncherPaneViewController` | `"启动器"` | `"magnifyingglass"` | `"启动器设置将在第二阶段实现。"` |
| `PasswordPaneViewController.swift` | `PasswordPaneViewController` | `"密码管理器"` | `"lock"` | `"密码管理器设置将在第二阶段实现。"` |
| `GamepadPaneViewController.swift` | `GamepadPaneViewController` | `"手柄"` | `"gamecontroller"` | `"手柄 Home 键配置将在第五阶段实现。"` |
| `AboutPaneViewController.swift` | `AboutPaneViewController` | `"关于"` | `"info.circle"` | `"版本信息与诊断工具将在第三阶段实现。"` |

- [ ] **Step 2: 编译验证**

Run: `./scripts/build.sh 2>&1 | grep -E "✅|error" | head -10`
Expected: 输出 `✅ 构建成功:`

- [ ] **Step 3: 手工验证窗口能打开**

临时在 `main.swift` 的 `applicationDidFinishLaunching` 里加一行（**验证后删除**）：

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    let controller = SettingsWindowController()
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

Run: `./scripts/build.sh && open dist/build/TonyToy.app`
Expected: 1 秒后弹出配置窗口，左侧 9 个分区，点击能切换右侧内容（显示占位文案）

- [ ] **Step 4: 删除临时验证代码**

删掉 Step 3 加的 `DispatchQueue.main.asyncAfter` 块。

- [ ] **Step 5: 提交**

```bash
git add src/UI/Settings/
git commit -m "feat(ui): 新增配置窗口骨架与 9 个空分区"
```

---

### Task 9: 接入托盘菜单

**Files:**
- Modify: `src/main.swift`

- [ ] **Step 1: 查看现有菜单构建位置**

Run: `grep -n "buildMenu\|statusItem.menu\|NSMenu()" src/main.swift | head -10`
Expected: 找到菜单构建方法（约在 `main.swift:160-220`）

- [ ] **Step 2: 添加「设置…」菜单项**

在 `src/main.swift` 的 AppDelegate 里新增属性：

```swift
    private lazy var settingsWindowController = SettingsWindowController()
```

在 `buildMenu()` 里，把「设置…」放在**版本号之后、第一个开关之前**：

```swift
        let settingsItem = NSMenuItem(
            title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
```

新增方法：

```swift
    @objc private func showSettings() {
        settingsWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 3: 编译验证**

Run: `./scripts/build.sh 2>&1 | grep -E "✅|error" | head -5`
Expected: 输出 `✅ 构建成功:`

- [ ] **Step 4: 手工验证**

Run: 安装后点托盘菜单 → 「设置…」（或按 `⌘,`）
Expected: 弹出配置窗口，9 个分区可切换

- [ ] **Step 5: 提交**

```bash
git add src/main.swift
git commit -m "feat: 托盘菜单新增「设置…」入口"
```

---

### Task 10: 阶段验收

- [ ] **Step 1: 跑全量测试**

Run: `just test 2>&1 | tail -3`
Expected: 输出 `all tests passed`

- [ ] **Step 2: 完整构建并安装**

```bash
./scripts/build.sh
osascript -e 'quit app "TonyToy"'; sleep 2
sudo rm -rf /Applications/TonyToy.app
sudo ditto dist/build/TonyToy.app /Applications/TonyToy.app
sudo chown -R "$(id -u):$(id -g)" /Applications/TonyToy.app
open /Applications/TonyToy.app
```

- [ ] **Step 3: 人工回归清单**

逐项确认**现有功能未被破坏**：

- [ ] 托盘菜单的 8 个开关状态与重构前一致
- [ ] `⌥D` 启动器正常呼出
- [ ] `⌘Tab` 切换器正常（如果之前开启）
- [ ] Caps 层映射正常（按 Caps+E 应触发上方向键）
- [ ] 密码管理器 `⌘⇧V` 正常
- [ ] 鼠标侧键层正常
- [ ] 点「设置…」能打开配置窗口，9 个分区都能切换

- [ ] **Step 4: 打标签**

```bash
git tag -a v1.2.0-core -m "配置重构第一阶段：Core 层与窗口骨架"
```

---

## 后续计划（本文件未覆盖）

| 计划 | 范围 | 前置条件 |
|---|---|---|
| 第二阶段 | 通用 Pane、关于 Pane、主题系统（三档实时切换） | 本阶段完成 |
| 第三阶段 | 映射表编辑器（`HotkeyRecorder` + `MappingTableEditor` + 冲突检测） | 第二阶段完成 |
| 第四阶段 | 7 个 Feature 迁移 + 托盘菜单精简 + 删除 `MenuStateStore` | 第三阶段完成 |

**为什么拆开**：每个阶段都能独立编译、独立安装、独立回滚。第二阶段开始改现有代码（主题要动 `NSApp.appearance`），风险高于本阶段，值得单独评审。
