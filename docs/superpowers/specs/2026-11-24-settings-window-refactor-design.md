# 配置窗口与架构重构设计

## 背景

TonyToy 目前有 8 个功能开关、5 个配置文件，全部通过**手写 JSON** 编辑，界面只有托盘菜单里的一排勾选项。

现状的具体问题（以「新增手柄 Home 开关」为标尺实测）：

| 问题 | 证据 |
|---|---|
| 新增一个功能要改 9 处 | `main.swift` 7 处 + `MenuStateStore` 1 处 + 配置窗口 1 处，漏一处表现为「开关点了没反应」 |
| 配置分散在 5 个文件 | `hotkeys.json` / `caps-mappings.json` / `mouse-layer.json` / `input-aliases.json` / `vault.jsonl` |
| 格式不统一 | 有的有 `version` 字段，有的没有；同一概念（按键）在三处各写一遍 |
| 改映射必须离开应用 | 打开编辑器改 JSON，还得记住键名（`escape` / `grave_accent_and_tilde`） |
| 大文件职责混乱 | `PasswordManagerWindow.swift` 1053 行、`AppActionExecutor.swift` 670 行 |
| 无任何可视化 | 深色模式、每页项数、自动锁定时间等只能改代码 |

## 目标

1. **统一配置模型**：所有功能配置收敛到单一 `config.json`，带版本号与自动迁移。
2. **可视化配置窗口**：侧边栏导航，可增删改快捷键映射（录制按键 + 选动作 + 冲突检测），无需手写 JSON。
3. **Feature 化架构**：新增功能从改 9 处降到 2 处（一个 `Feature` 文件 + 一行注册）。
4. **主题系统**：全部 UI 支持跟随系统 / 浅色 / 深色三档切换。
5. **保持默认行为不变**：现有用户升级后功能完全一致，配置自动迁移。

## 非目标

- **不改密码库格式**：`vault.jsonl` 保持独立（安全边界，且已有独立设计文档）。
- **不做自动 UI 生成**：设置项描述只用于数据绑定，界面布局手写。自动布局生成在本项目规模是负担。
- **不做多套配置方案 / 导入导出**：单人使用，YAGNI。
- **不引入 SPM 或第三方库**：保持 `swiftc` 直接编译，无 Xcode 工程。
- **不改构建系统**：`scripts/build.sh` 与 `justfile` 保持现状（仅新增源文件自动纳入通配）。
- **不做滚轮反向**：已验证 macOS 26 忽略事件 tap 对滚动增量的修改，非本项目可解决。

## 核心决策

| 决策点 | 结论 | 理由 |
|---|---|---|
| 界面形态 | **侧边栏导航** | 9 个分区，只有侧边栏能容纳增长；与 macOS 26 系统设置一致 |
| 编辑深度 | **可视化增删改** | 录制按键 + 动作选择器 + 冲突检测，改映射不碰文件 |
| 配置模型 | **统一 `config.json`** | 单一数据源，消除「这个开关存在哪」的歧义 |
| 主题范围 | **全部 UI + 三档切换** | 四个 UI 面统一，避免「设置深色、弹窗还是浅色」 |
| 分区划分 | **9 个分区**（Caps 层与全局快捷键分开） | 两个映射表语义独立，合并会让用户困惑 |

## 架构

### 目录结构

```
src/
├── Core/                        配置与抽象
│   ├── TonyToyConfig.swift      统一配置模型
│   ├── ConfigStore.swift        读写 + 版本迁移 + 变更通知
│   ├── Feature.swift            Feature 协议 + SettingItem 描述
│   └── FeatureRegistry.swift    功能注册表
├── Features/                    每个功能一个目录
│   ├── CapsLayer/
│   ├── HotkeyLayer/
│   ├── MouseLayer/
│   ├── Launcher/
│   ├── Switcher/
│   ├── PasswordVault/
│   └── Gamepad/
├── UI/
│   ├── Settings/
│   │   ├── SettingsWindowController.swift
│   │   └── Panes/               9 个分区视图
│   └── Components/
│       ├── MappingTableEditor.swift    映射表编辑器
│       ├── HotkeyRecorder.swift       按键录制器
│       └── SettingsRowView.swift      统一的「标题 + 控件」行
└── Infra/
    ├── EventTap/                事件拦截（现有 tap 归拢）
    ├── Accessibility/           AX 封装
    └── Permissions/             权限检查
```

### Feature 协议

```swift
protocol Feature: AnyObject {
    /// 唯一标识，同时作为配置 key 前缀
    var id: String { get }
    /// 侧边栏标题
    var title: String { get }
    /// SF Symbols 图标名
    var icon: String { get }
    /// 设置项声明（用于界面数据绑定，不生成布局）
    var settings: [SettingItem] { get }

    /// 从未配置过时的默认开关状态。
    ///
    /// **不是所有功能都默认开启**：`switcher`（⌘Tab 接管）和 `mouseFollow`
    /// 在旧 `UserDefaults` 里默认关闭，硬编码 `true` 会改变既有行为。
    var defaultEnabled: Bool { get }

    /// 启动：注册事件 tap、建立 AX 连接等
    func start()
    /// 停止：注销 tap、释放资源
    func stop()
    /// 应用功能自己的配置值（映射表、每页项数等）。默认空实现。
    func applyValues(_ config: FeatureConfig)
}

extension Feature {
    /// 模板方法：先按开关启停，再应用具体配置。
    ///
    /// **不要做成协议需求**——协议扩展没有 `super`，一旦某个 Feature
    /// 覆盖了 `apply` 就再也调不回默认实现，「忘记启停」会变成静默 bug。
    /// 实现方只覆盖 `applyValues(_:)`。
    func apply(_ config: FeatureConfig) {
        if config.isEnabled {
            start()
            applyValues(config)
        } else {
            stop()
        }
    }
}

enum SettingItem {
    case toggle(key: String, title: String, defaultValue: Bool)
    case hotkey(key: String, title: String, defaultValue: HotkeyKeySpec)
    case number(key: String, title: String, defaultValue: Int, range: ClosedRange<Int>)
    case picker(key: String, title: String, options: [(value: String, label: String)], defaultValue: String)
    /// 映射表：界面用 MappingTableEditor 渲染
    case table(key: String, title: String)
}
```

**关键约束**：`settings` 只描述「有哪些配置项、类型、默认值」，**不描述布局**。分区视图仍然手写 `NSStackView` 组装，用 `SettingsRowView` 统一行高与间距。

### 数据流

```
config.json ──→ ConfigStore.load() ──→ TonyToyConfig
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    ↓                     ↓                     ↓
              FeatureRegistry        SettingsWindow        Feature.apply()
              （遍历 features）      （读 settings 渲染）    （热更新映射）
```

配置写入是**单向**的：界面改值 → `ConfigStore.save()` → 落盘 → 通知所有 Feature `apply()`。

## 配置模型

### config.json

路径：`~/.config/tony-toy/config.json`（与现有配置文件同目录）。

```json
{
  "version": 1,
  "general": {
    "launchAtLogin": false,
    "theme": "system",
    "showMenuBarIcon": true
  },
  "features": {
    "capsLayer": {
      "isEnabled": true,
      "values": {
        "mappings": [
          { "from": "e", "to": { "key": "up_arrow" } }
        ]
      }
    },
    "hotkeyLayer": {
      "isEnabled": true,
      "values": {
        "mappings": [
          {
            "from": { "key": "escape", "modifiers": ["command"] },
            "to": { "key": "grave_accent_and_tilde", "modifiers": ["command"] }
          }
        ]
      }
    },
    "gamepad": {
      "isEnabled": true,
      "values": { "homeWake": true }
    }
  }
}
```

**设计要点**：

- `version` 在顶层，用于迁移。
- 每个 Feature 的配置是 `{ isEnabled, values: [String: ConfigValue] }`。`isEnabled` 单独提出来，因为所有功能都有，且托盘菜单要读它。
- **`values` 用通用 `JSONValue` 承载**，不用泛型枚举。原因：`capsLayer` / `hotkeyLayer` / `mouseLayer` 三个映射表结构各不相同（Caps 层来源是单个字符，全局快捷键来源是组合键，鼠标层来源是侧键），强行统一成一个枚举会引入大量 `switch` 和可选字段，比异构字典更难维护。

  ```swift
  struct FeatureConfig: Codable {
      var isEnabled: Bool
      var values: [String: JSONValue]
  }

  /// 通用 JSON 值：null / bool / int / double / string / array / object
  enum JSONValue: Codable { ... }
  ```

  各 Feature 在 `apply(_:)` 里把 `values` 解码成自己的强类型结构（复用现有的 `CapsMappingEntry` / `HotkeyMappingEntry` / `MouseLayerMappingEntry`）。解码失败时保留上一次有效配置并记录日志，不让整个配置加载失败。

### 迁移策略

启动时按顺序尝试：

1. `config.json` 存在 → 直接读。`version` 小于当前版本 → 跑迁移链。
2. `config.json` 不存在 → 从 5 个旧文件读取，合成 `TonyToyConfig`，写 `config.json`。
3. 旧文件**保留不删**，重命名为 `*.json.migrated`。

**为什么保留**：迁移可能出错，保留旧文件能用 `git checkout` 或手工恢复。用户确认无问题后可自行删除。

**迁移幂等**：迁移完成后写 `config.json` 的 `version`，重复启动不会重复迁移。

### 与 UserDefaults 的关系

现有 `MenuStateStore` 用 `UserDefaults` 存 8 个布尔开关。迁移后这些开关进入 `config.json` 的 `features[*].isEnabled`。

**保留 `UserDefaults` 读取作为兜底**：首次迁移时若 `config.json` 里某功能没有 `isEnabled`，回退读 `UserDefaults` 的旧 key，避免用户升级后开关状态丢失。

## 配置窗口

### 侧边栏分区（9 个）

| 分区 | 图标 | 设置项 |
|---|---|---|
| 通用 | `gear` | 开机自启、主题（跟随系统/浅色/深色）、菜单栏图标 |
| Caps 键层 | `capslock` | 启用、映射表（Caps + 字母 → 动作） |
| 全局快捷键 | `command` | 启用、映射表（组合键 → 动作） |
| 鼠标 | `computermouse` | 启用、侧键层映射 |
| 窗口 | `macwindow` | ⌘Tab 接管、切换时鼠标居中、切换器行列数、窗口平铺快捷键 |
| 启动器 | `magnifyingglass` | 启用、呼出快捷键、每页项数、拼音匹配、显示无窗口应用 |
| 密码管理器 | `lock` | 呼出快捷键、自动锁定时间、剪贴板清除延迟 |
| 手柄 | `gamepad` | 启用、Switch Home 拉起 MacDeck |
| 关于 | `info.circle` | 版本号、权限状态、打开配置文件夹、导出调试日志 |

### 窗口规格

- 尺寸：`720 × 520`，可调整（最小 `620 × 440`）
- 侧边栏宽 `180`，`NSOutlineView` 单选
- 内容区 `NSStackView` 纵向排列，`SettingsRowView` 统一样式：左侧标题（13pt），右侧控件
- 分区之间用 `NSBox` 分隔线 + 12pt 间距

### 核心组件

**HotkeyRecorder**（按键录制器）

- 点击进入录制态，背景变强调色
- 监听 `NSEvent` 的 `keyDown` / `flagsChanged`
- 显示如 `⌘⇧A`，按 Esc 取消，按 Delete 清空
- 录制时禁用其他 tap（避免被 Caps 层等拦截）

**MappingTableEditor**（映射表编辑器）

- `NSTableView`，两列：来源（按键）、目标（动作）
- 底部 `＋` / `－` 按钮
- 新增行弹出 `NSAlert` 式的动作选择器：
  - 动作类型下拉（`sendHotkey` / `activateApplication` / `moveWindowToAdjacentDisplay` / `maximizeWindow` / `missionControl` / `switchToLast`）
  - 按类型显示参数（快捷键录制器 / 应用选择器 / 方向选择器）
- **冲突检测**：新增时检查来源是否已存在，重复则高亮该行并提示
- **未知按键提示**：解析失败的行标红，显示原始 key 字符串

## 主题系统

```swift
enum ThemePreference: String, Codable {
    case system, light, dark

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
```

**应用方式**：`NSApp.appearance = preference.appearance`。

**为什么这样够**：所有 UI 面（配置窗口、启动器、切换器、密码管理器）都是普通 `NSWindow` / `NSPanel`，继承 `NSApp.appearance`。`NSVisualEffectView` 会自动跟随 appearance 切换材质明暗。

**切换时机**：配置改变时立即设置，无需重启。已打开的窗口会即时重绘。

## 实施阶段

每个阶段可独立编译、独立验证、可回滚。

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| **1. Core 层** | `TonyToyConfig` / `ConfigStore` / `Feature` 协议 / 迁移逻辑 | 单元测试：旧 5 文件能正确迁移；重复迁移幂等 |
| **2. 窗口骨架** | `SettingsWindowController` + 侧边栏 + 9 个空 Pane | 能打开、能切换分区、布局正确 |
| **3. 通用 + 关于** | 主题、开机自启、权限状态、打开配置文件夹 | 主题三档实时生效 |
| **4. 映射表编辑器** | `HotkeyRecorder` + `MappingTableEditor` + 冲突检测 | 能增删改 Caps 层映射并立即生效 |
| **5. 逐功能迁移** | 7 个 Feature 包装现有 Controller | 每个功能：托盘开关仍工作，配置窗口可编辑 |
| **6. 收尾** | 托盘菜单精简到 4 项、删除 `MenuStateStore`、更新 README | 全功能回归通过 |

**阶段 5 的顺序**（从简单到复杂，每步都能独立验证）：

1. Gamepad（最简单，只有一个开关）
2. MouseLayer（已有 ConfigStore，接口清晰）
3. HotkeyLayer
4. CapsLayer
5. Switcher（⌘Tab）
6. Launcher
7. PasswordVault（最复杂，1053 行）

## 测试策略

**单元测试**（`tests/`，`just test` 运行）：

- `ConfigStoreTests`：迁移正确性、幂等性、版本升级链
- `TonyToyConfigTests`：编解码往返、缺失字段的默认值、`ConfigValue` 类型安全
- `MappingResolverTests`：现有映射解析逻辑保持行为不变（回归）

**手工验证清单**（每个阶段结束时）：

- 8 个功能开关逐个切换，确认行为与重构前一致
- 配置文件被外部修改后，重启能正确加载
- 迁移后旧文件仍在（`.migrated` 后缀）
- 主题切换后四个 UI 面都变

**不做**：UI 自动化测试（成本高于收益，本项目单人维护）。

## 风险与取舍

| 风险 | 影响 | 缓解 |
|---|---|---|
| 迁移丢失用户配置 | 高 | 旧文件保留为 `.migrated`；迁移前先备份 `config.json.bak`；迁移逻辑有单元测试 |
| 阶段 5 改坏现有功能 | 高 | 每迁移一个功能就手工回归一次；Feature 包装只做转发，不改原有逻辑 |
| 重构周期长，中途不可用 | 中 | 每阶段结束都能编译安装；阶段 1-2 不碰现有代码 |
| `Feature` 抽象过度 | 中 | 协议只有 7 个成员；如果某个功能觉得别扭，允许它不实现 `settings`（退化为手写 Pane） |
| 映射表编辑器复杂度超预期 | 中 | 先做只读展示，编辑能力分两次迭代 |

**明确放弃的东西**：

- 自动布局生成（配置项描述 → 界面）——灵活性损失大于收益
- 多套配置方案切换——单人使用，YAGNI
- 配置云同步——`~/.config/tony-toy/` 已在 dotfiles 仓库里，git 就是同步方案
- 插件化动态加载——macOS 应用做这个收益极低

## 附录：现状问题清单

重构要解决的已知问题（按处理阶段归类）：

**阶段 1-2**
- [ ] 5 个配置文件格式不统一（有的有 `version`，有的没有）
- [ ] `MenuStateStore` 与各 `ConfigStore` 并存，语义重叠
- [ ] 配置项没有统一的默认值来源

**阶段 3-4**
- [ ] 改映射必须手写 JSON，键名靠记
- [ ] 无冲突检测：重复的 Caps 映射会被静默覆盖
- [ ] 无深色模式

**阶段 5-6**
- [ ] `main.swift` 378 行，混合了启动、菜单、开关、持久化
- [ ] `PasswordManagerWindow.swift` 1053 行
- [ ] `AppActionExecutor.swift` 670 行
- [ ] 托盘菜单 11 项，没有分组
- [ ] 排查问题要开终端看 `/tmp/launcher-debug.log`
