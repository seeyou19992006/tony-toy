# 密码管理器 JSONL 改造设计

## 背景

当前密码管理器（`VaultService`）使用单个 `vault.json` 文件，存储格式为 `VaultContainer { encryptedData, salt, nonce }`。整个 entries 数组序列化后一次性 AES-GCM 加密成一个 blob。

用户已通过符号链接将 `~/.config/tony-toy/vault.json` 指向 `~/dotfiles/tony-toy/vault.json`（gitee 仓库），用 git 跨机器同步密码库。但当前格式存在两个问题：

1. **git diff 不可读**：每次 CRUD 全量重写密文 blob，diff 看不出改了哪条密码，合并冲突无法处理。
2. **nonce 重用**：每次 `save()` 复用同一 nonce（`VaultService.swift:119-124`），AES-GCM 在同密钥下重用 nonce 违反密码学最佳实践。

## 目标

- 改为 **JSON（meta）+ JSONL（entries）双文件**格式，每行一个 entry，只有 `password` 字段密文，其余明文。
- git diff 友好：增删改密码只影响对应行；跨机器 git merge 可行。
- 修复 nonce 重用：每条密码独立随机 nonce。
- 零依赖：用 Swift 原生 `JSONDecoder`/`JSONEncoder`，不引入第三方库。
- UI 层零改动：`VaultService` 对外接口签名不变。

## 非目标

- 不写自动迁移代码：旧格式 `vault.json` 的迁移在代码完成后手动执行。
- 不改 UI 层（`PasswordManagerWindow`）、不改构建系统。
- 不引入 SPM 或第三方 YAML/加密库。

## 文件格式

两个文件共存于 `~/.config/tony-toy/`（用户可通过符号链接指向 dotfiles 仓库）。

### vault.json（meta）

全局元信息，只在首次创建或换主密码时变化。

```json
{
  "version": 2,
  "salt": "<base64 16 字节>",
  "pbkdf2Rounds": 100000
}
```

### vault.jsonl（entries）

每行一个 entry，独立 JSON 对象。明文字段：`id`/`name`/`username`/`notes`/`createdAt`/`updatedAt`。密文字段：`password`（含独立 `nonce`）。

```jsonl
{"id":"<uuid>","name":"GitHub","username":"loki","nonce":"<base64 12 字节>","password":"<base64 密文>","notes":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z"}
{"id":"<uuid>","name":"Gitee","username":"loki","nonce":"<base64 12 字节>","password":"<base64 密文>","notes":"备用","createdAt":"...","updatedAt":"..."}
```

## 数据模型

```swift
// vault.json (meta) — 替换原 VaultContainer
struct VaultMeta: Codable {
    var version: Int = 2
    var salt: Data
    var pbkdf2Rounds: Int = 100000
}

// vault.jsonl 每行的存储格式
struct EncryptedEntry: Codable {
    let id: UUID
    var name: String        // 明文
    var username: String    // 明文
    var nonce: Data         // 每条独立，12 字节随机
    var password: Data      // AES-GCM 密文（ciphertext + tag）
    var notes: String       // 明文
    var createdAt: Date
    var updatedAt: Date
}

// 解锁后内存中的明文条目（UI 层继续用，签名不变）
struct PasswordEntry: Identifiable, Codable {  // 不变
    let id: UUID
    var name: String
    var username: String
    var password: String    // 内存中是明文
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}
```

## 加密细节

- 算法不变：AES-GCM（`CryptoKit`）+ PBKDF2-SHA256（`CommonCrypto`）。
- 密钥派生：`pbkdf2(password, salt, rounds=100000)` → 32 字节 `SymmetricKey`。
- **修复 nonce 重用**：每条 `password` 加密时生成新的 12 字节随机 nonce，嵌入该行 JSONL。
- 密文格式：`AES.GCM.seal` 返回 `SealedBox`，其 `combined` 含 nonce+ciphertext+tag。因为 nonce 单独存储，改造 `VaultCryptoService` 让 encrypt 只返回 ciphertext+tag，decrypt 接收独立 nonce 参数来重建 `SealedBox`。

## VaultService 接口（签名不变）

```swift
class VaultService {
    var isUnlocked: Bool { get }
    var vaultExists: Bool { get }           // vault.json 存在即算
    var entries: [PasswordEntry] { get }    // 内存明文

    func createVault(masterPassword: String) throws
    func unlock(masterPassword: String) throws
    func lock()

    func addEntry(name: String, username: String, password: String, notes: String = "") throws
    func updateEntry(_ entry: PasswordEntry) throws
    func deleteEntry(id: UUID) throws
    func search(_ query: String) -> [PasswordEntry]
}
```

## 核心流程

### createVault（首次创建）

1. 生成 16 字节随机 salt。
2. `pbkdf2(password, salt)` → masterKey，存入内存。
3. 写 `vault.json`（含 version/salt/rounds）。
4. 写空 `vault.jsonl`（0 行）。
5. 内存 `entries = []`。

### unlock（全量验证）

1. 读 `vault.json` → `VaultMeta`。
2. `pbkdf2(password, meta.salt)` → masterKey 候选。
3. 逐行读 `vault.jsonl`，每条用 masterKey 候选解密 `password`。
4. **任意一条解密失败 → 抛 `wrongPassword`**，masterKey 不保留在内存。
5. 全部成功 → masterKey 入内存，entries 载入明文。
6. 空库（0 行）→ 不报错，视为新库首次解锁（masterKey 入内存）。

### addEntry / updateEntry

1. 生成 12 字节随机 nonce。
2. AES-GCM 加密 password → 密文（ciphertext + tag）。
3. 构造 `EncryptedEntry`，更新内存 entries。
4. 全量重写 `vault.jsonl`（原子写：先写 .tmp 再 rename）。

### deleteEntry

1. 从内存 entries 过滤掉对应 id。
2. 全量重写 `vault.jsonl`（原子写）。

### 原子写策略

```swift
private func writeJSONL(_ lines: [EncryptedEntry]) throws {
    let tmpURL = vaultJSONLURL.appendingPathExtension("tmp")
    let jsonStrings = try lines.map { entry -> String in
        let data = try JSONEncoder().encode(entry)
        return String(data: data, encoding: .utf8) ?? ""
    }
    let content = jsonStrings.joined(separator: "\n") + "\n"
    try content.write(to: tmpURL, atomically: true, encoding: .utf8)
    _ = try FileManager.default.replaceItemAt(vaultJSONLURL, withItemAt: tmpURL)
}
```

- `atomically: true` 先写临时文件再 rename。
- `replaceItemAt` 保证原子替换，避免崩溃导致文件损坏。
- 全量重写而非追加：update/delete 需要改中间行，统一重写最简单；个人密码库规模小（百条内），性能无忧。

## 改动范围

| 文件 | 改动 | 说明 |
|---|---|---|
| `src/VaultService.swift` | 重写 | 双文件 I/O、全量验证、per-entry 加解密，约 150 → 200 行 |
| `src/VaultCryptoService.swift` | 改造现有方法 | encrypt 返回 ciphertext+tag（不含 nonce，因 nonce 单独存储）；decrypt 改为接收独立 nonce 参数。原方法仅 VaultService 调用，随其一起改造，+0 行净增 |
| `src/PasswordEntry.swift` | 新增结构 | `EncryptedEntry`，`PasswordEntry` 不变，+15 行 |
| `src/PasswordManagerWindow.swift` | 零改动 | 接口签名不变 |
| `src/PasswordPaster.swift` | 零改动 | — |
| `src/PBKDF2.swift` | 零改动 | — |
| `src/main.swift` | 零改动 | — |
| 构建/打包脚本 | 零改动 | 无新依赖 |

## 错误处理

```swift
enum VaultError: LocalizedError {
    case vaultNotFound        // vault.json 不存在
    case notUnlocked          // 未解锁就 CRUD
    case encryptionFailed     // AES-GCM 加密异常
    case wrongPassword        // 全量验证中某条解密失败
}
```

**全量验证的失败语义**：
- 解锁时任意一条 AES-GCM open 失败 → 抛 `wrongPassword`。
- 不区分"主密码错"和"数据损坏"，统一报"主密码错误"。
- 理由：对用户两者表现一样（解不开），且暴露具体哪条损坏会泄露信息。

## 测试

新增 `tests/VaultServiceTests.swift`，沿用现有 `run_all.sh` 驱动。

| 用例 | 验证点 |
|---|---|
| `testCreateVault` | 创建后 vault.json + vault.jsonl 都存在，jsonl 为空 |
| `testUnlockCorrectPassword` | 正确密码解锁成功，entries 可读 |
| `testUnlockWrongPassword` | 错误密码抛 wrongPassword，isUnlocked=false |
| `testAddEntry` | 新增后 jsonl 多一行，password 是密文（非明文） |
| `testUpdateEntry` | 更新后对应行变化，其他行不变 |
| `testDeleteEntry` | 删除后行数减少 |
| `testPerEntryNonce` | 两次加密同一密码，nonce 不同，密文不同 |
| `testFullValidationOnUnlock` | 手动篡改某行密文，解锁时抛错 |

手动验证：
1. `just build` 编译通过。
2. 运行应用，创建新库，增删改密码。
3. `cat vault.jsonl` 确认 password 字段是 base64 密文、其他字段明文。
4. `git diff vault.jsonl` 确认只改对应行。
5. `just test` 跑单元测试。

## 迁移（手动，代码完成后执行）

1. 用旧版本解锁，导出明文 entries。
2. 删除旧 `vault.json`。
3. 用新版本 `createVault` 创建新格式。
4. 逐条 `addEntry` 导回。
