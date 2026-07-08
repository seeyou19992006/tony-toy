# 密码管理器 JSONL 改造实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将密码管理器从单文件全量加密改造为 JSON(meta)+JSONL(entries) 双文件格式，只有 password 字段密文，每条独立 nonce，全量验证，git diff 友好。

**Architecture:** 原地改造 `VaultService`（对外接口签名不变，UI 层零改动）。新增 `EncryptedEntry` 结构表示 JSONL 每行；`VaultContainer` 退化为 `VaultMeta`；`VaultCryptoService` 改造为 per-entry encrypt/decrypt（接收独立 nonce）。JSONL 全量重写采用原子写策略。

**Tech Stack:** Swift 5 / macOS 11+ / CryptoKit (AES-GCM) / CommonCrypto (PBKDF2-SHA256) / 原生 JSONEncoder/JSONDecoder

**Spec:** `docs/superpowers/specs/2026-07-08-vault-jsonl-redesign-design.md`

---

## 文件结构

| 文件 | 职责 | 改动类型 |
|---|---|---|
| `src/PasswordEntry.swift` | 定义 `PasswordEntry`（内存明文，不变）+ 新增 `EncryptedEntry`（JSONL 行存储）+ `VaultMeta`（vault.json） | 修改 |
| `src/VaultCryptoService.swift` | AES-GCM per-entry 加解密，encrypt 返回 ciphertext+tag，decrypt 接收独立 nonce | 改造 |
| `src/VaultService.swift` | 双文件 I/O、全量验证、CRUD 编排 | 重写 |
| `tests/VaultServiceTests.swift` | 单元测试，覆盖创建/解锁/CRUD/nonce/全量验证 | 新建 |
| `tests/run_all.sh` | 注册新测试二进制 | 修改 |
| `src/PasswordManagerWindow.swift` | 不改动 | — |
| `src/PasswordPaster.swift` | 不改动 | — |
| `src/PBKDF2.swift` | 不改动 | — |
| `src/main.swift` | 不改动 | — |

---

### Task 1: 定义新数据模型（VaultMeta + EncryptedEntry）

**Files:**
- Modify: `src/PasswordEntry.swift`

- [ ] **Step 1: 写完整的 PasswordEntry.swift**

将 `VaultMeta` 和 `EncryptedEntry` 追加到 `PasswordEntry.swift`，`PasswordEntry` 本身不变。

```swift
import Foundation

struct PasswordEntry: Identifiable, Codable {
    let id: UUID
    var name: String        // 网站/服务名
    var username: String
    var password: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}

// vault.json 的元信息格式
struct VaultMeta: Codable {
    var version: Int
    var salt: Data
    var pbkdf2Rounds: Int
}

// vault.jsonl 每行的存储格式：只有 password 是密文
struct EncryptedEntry: Codable {
    let id: UUID
    var name: String
    var username: String
    var nonce: Data         // 12 字节随机，每条独立
    var password: Data      // AES-GCM ciphertext + tag
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}
```

- [ ] **Step 2: 验证编译通过**

Run: `swiftc -parse src/PasswordEntry.swift`
Expected: 无输出（解析成功）

- [ ] **Step 3: Commit**

```bash
git add src/PasswordEntry.swift
git commit -m "feat(vault): 新增 VaultMeta 和 EncryptedEntry 数据模型"
```

---

### Task 2: 改造 VaultCryptoService 为 per-entry 加解密

**Files:**
- Modify: `src/VaultCryptoService.swift`

- [ ] **Step 1: 写完整的 VaultCryptoService.swift**

改造为：encrypt 接收明文 Data + keyData + nonce，返回 ciphertext+tag（不含 nonce）；decrypt 接收 ciphertext+tag + keyData + nonce，返回明文。原方法签名随之变化，但只有 VaultService 调用它（Task 3 会同步更新）。

```swift
import Foundation
import CryptoKit

// MARK: - 加密服务
class VaultCryptoService {
    /// 加密：返回 ciphertext + tag（不含 nonce，nonce 由调用方单独存储）
    func encrypt(_ data: Data, keyData: Data, nonce: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let aesNonce = try AES.GCM.Nonce(data: nonce)
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: aesNonce)
        // sealedBox.ciphertext + sealedBox.tag，不含 nonce
        return sealedBox.ciphertext + sealedBox.tag
    }

    /// 解密：接收 ciphertext + tag，配合独立 nonce 还原明文
    func decrypt(_ data: Data, keyData: Data, nonce: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let aesNonce = try AES.GCM.Nonce(data: nonce)
        // 从 data 拆出 ciphertext 和 tag（tag 固定 16 字节，在末尾）
        let tagLength = 16
        guard data.count > tagLength else {
            throw VaultError.encryptionFailed
        }
        let ciphertext = data.prefix(data.count - tagLength)
        let tag = data.suffix(tagLength)
        let sealedBox = try AES.GCM.SealedBox(nonce: aesNonce,
                                              ciphertext: ciphertext,
                                              tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }
}
```

- [ ] **Step 2: 验证编译通过（需要 VaultError 定义，从 VaultService.swift）**

Run: `swiftc -parse src/VaultCryptoService.swift src/VaultService.swift src/PasswordEntry.swift`
Expected: 可能报 `VaultService` 旧代码调用了不存在的 encrypt 签名——这是预期的，Task 3 会修复。此处只确认 `VaultCryptoService.swift` 自身语法正确。

Run: `swiftc -parse src/VaultCryptoService.swift`（单独解析，VaultError 未定义会报错，忽略 VaultError 相关错误，只看语法）
Expected: 语法正确（VaultError 引用错误可忽略，Task 3 修复）

- [ ] **Step 3: Commit**

```bash
git add src/VaultCryptoService.swift
git commit -m "feat(vault): 改造 VaultCryptoService 为 per-entry 加解密，支持独立 nonce"
```

---

### Task 3: 重写 VaultService 双文件 I/O 与全量验证

**Files:**
- Modify: `src/VaultService.swift`

- [ ] **Step 1: 写完整的 VaultService.swift**

重写为双文件格式。对外接口签名完全不变（`createVault`/`unlock`/`lock`/`addEntry`/`updateEntry`/`deleteEntry`/`search`/`isUnlocked`/`vaultExists`/`entries`）。

```swift
import Foundation

// MARK: - Vault 服务
class VaultService {
    private let crypto = VaultCryptoService()
    private let configDir: URL
    private let vaultMetaURL: URL
    private let vaultJSONLURL: URL
    private var masterKeyData: Data?  // 存储派生的密钥数据

    var isUnlocked: Bool { masterKeyData != nil }
    var vaultExists: Bool { FileManager.default.fileExists(atPath: vaultMetaURL.path) }
    var entries: [PasswordEntry] = []

    init() {
        configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("tony-toy")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        vaultMetaURL = configDir.appendingPathComponent("vault.json")
        vaultJSONLURL = configDir.appendingPathComponent("vault.jsonl")
    }

    // 测试用：注入 configDir
    init(configDir: URL) {
        self.configDir = configDir
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        vaultMetaURL = configDir.appendingPathComponent("vault.json")
        vaultJSONLURL = configDir.appendingPathComponent("vault.jsonl")
    }

    /// 首次创建 vault
    func createVault(masterPassword: String) throws {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let meta = VaultMeta(version: 2, salt: salt, pbkdf2Rounds: 100000)

        masterKeyData = pbkdf2(password: masterPassword, salt: salt,
                               keyByteCount: 32, rounds: meta.pbkdf2Rounds)
        entries = []

        // 写 meta
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: vaultMetaURL, atomically: true)

        // 写空 JSONL
        try Data().write(to: vaultJSONLURL, atomically: true)
    }

    /// 解锁 vault（全量验证：逐条解密，任一失败则抛 wrongPassword）
    func unlock(masterPassword: String) throws {
        guard vaultExists else {
            throw VaultError.vaultNotFound
        }

        let metaData = try Data(contentsOf: vaultMetaURL)
        let meta = try JSONDecoder().decode(VaultMeta.self, from: metaData)

        let keyData = pbkdf2(password: masterPassword, salt: meta.salt,
                             keyByteCount: 32, rounds: meta.pbkdf2Rounds)

        // 逐行读 JSONL，全量验证
        var loaded: [PasswordEntry] = []
        if FileManager.default.fileExists(atPath: vaultJSONLURL.path) {
            let jsonlData = try Data(contentsOf: vaultJSONLURL)
            guard let text = String(data: jsonlData, encoding: .utf8) else {
                throw VaultError.wrongPassword
            }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            for line in lines {
                guard let lineData = line.data(using: .utf8) else {
                    throw VaultError.wrongPassword
                }
                let encEntry: EncryptedEntry
                do {
                    encEntry = try JSONDecoder().decode(EncryptedEntry.self, from: lineData)
                } catch {
                    throw VaultError.wrongPassword
                }
                let plainData: Data
                do {
                    plainData = try crypto.decrypt(encEntry.password,
                                                   keyData: keyData,
                                                   nonce: encEntry.nonce)
                } catch {
                    throw VaultError.wrongPassword
                }
                guard let plain = String(data: plainData, encoding: .utf8) else {
                    throw VaultError.wrongPassword
                }
                loaded.append(PasswordEntry(
                    id: encEntry.id,
                    name: encEntry.name,
                    username: encEntry.username,
                    password: plain,
                    notes: encEntry.notes,
                    createdAt: encEntry.createdAt,
                    updatedAt: encEntry.updatedAt
                ))
            }
        }

        masterKeyData = keyData
        entries = loaded
    }

    /// 锁定
    func lock() {
        masterKeyData = nil
        entries = []
    }

    // MARK: - CRUD

    func addEntry(name: String, username: String, password: String, notes: String = "") throws {
        guard isUnlocked else { throw VaultError.notUnlocked }

        let entry = PasswordEntry(
            id: UUID(),
            name: name,
            username: username,
            password: password,
            notes: notes,
            createdAt: Date(),
            updatedAt: Date()
        )
        entries.append(entry)
        try save()
    }

    func updateEntry(_ entry: PasswordEntry) throws {
        guard isUnlocked else { throw VaultError.notUnlocked }
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
            try save()
        }
    }

    func deleteEntry(id: UUID) throws {
        guard isUnlocked else { throw VaultError.notUnlocked }
        entries.removeAll { $0.id == id }
        try save()
    }

    func search(_ query: String) -> [PasswordEntry] {
        if query.isEmpty { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - 私有：全量重写 JSONL（原子写）

    private func save() throws {
        guard let keyData = masterKeyData else { throw VaultError.notUnlocked }

        var encEntries: [EncryptedEntry] = []
        for entry in entries {
            let plainData = Data(entry.password.utf8)
            let nonce = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
            let cipher = try crypto.encrypt(plainData, keyData: keyData, nonce: nonce)
            encEntries.append(EncryptedEntry(
                id: entry.id,
                name: entry.name,
                username: entry.username,
                nonce: nonce,
                password: cipher,
                notes: entry.notes,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            ))
        }

        try writeJSONL(encEntries)
    }

    private func writeJSONL(_ lines: [EncryptedEntry]) throws {
        let jsonStrings: [String] = try lines.map { entry in
            let data = try JSONEncoder().encode(entry)
            return String(data: data, encoding: .utf8) ?? ""
        }
        let content = jsonStrings.joined(separator: "\n") + (jsonStrings.isEmpty ? "" : "\n")
        let tmpURL = vaultJSONLURL.appendingPathExtension("tmp")
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(vaultJSONLURL, withItemAt: tmpURL)
    }
}

// MARK: - 错误
enum VaultError: LocalizedError {
    case vaultNotFound
    case notUnlocked
    case encryptionFailed
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .vaultNotFound: return "Vault 文件不存在"
        case .notUnlocked: return "Vault 未解锁"
        case .encryptionFailed: return "加密失败"
        case .wrongPassword: return "主密码错误"
        }
    }
}
```

- [ ] **Step 2: 验证全部源码编译通过**

Run: `swiftc -parse src/PasswordEntry.swift src/VaultCryptoService.swift src/VaultService.swift src/PBKDF2.swift`
Expected: 无错误输出（语法解析通过）

- [ ] **Step 3: 全量构建验证**

Run: `just build`
Expected: 构建成功，无错误

- [ ] **Step 4: Commit**

```bash
git add src/VaultService.swift
git commit -m "feat(vault): 重写 VaultService 为双文件 JSONL 格式，全量验证 + per-entry nonce"
```

---

### Task 4: 编写 VaultService 单元测试

**Files:**
- Create: `tests/VaultServiceTests.swift`

- [ ] **Step 1: 确认 VaultService 已包含测试用 init**

Task 3 的 `VaultService` 代码已包含 `init(configDir:)`（用于注入临时目录）。确认 `src/VaultService.swift` 中存在该 init，无需额外改动。

```swift
import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message) — expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertFalse(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        fputs("Assertion failed: \(message) — expected false\n", stderr)
        exit(1)
    }
}

@main
struct VaultServiceTests {
    static func main() {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tony-toy-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: testDir) }

        // --- testCreateVault ---
        do {
            let svc = VaultService(configDir: testDir)
            try svc.createVault(masterPassword: "secret123")
            assertTrue(svc.isUnlocked, "createVault 后应已解锁")
            assertTrue(FileManager.default.fileExists(atPath: testDir.appendingPathComponent("vault.json").path),
                       "vault.json 应存在")
            assertTrue(FileManager.default.fileExists(atPath: testDir.appendingPathComponent("vault.jsonl").path),
                       "vault.jsonl 应存在")
            assertEqual(svc.entries.count, 0, "新库应为空")
            print("testCreateVault passed")
        } catch {
            fputs("testCreateVault failed: \(error)\n", stderr); exit(1)
        }

        // --- testAddEntry ---
        do {
            let svc = VaultService(configDir: testDir)
            try svc.createVault(masterPassword: "secret123")
            try svc.addEntry(name: "GitHub", username: "loki", password: "p@ss", notes: "note1")
            assertEqual(svc.entries.count, 1, "添加后应有 1 条")

            // 读 JSONL 确认 password 是密文
            let jsonlData = try Data(contentsOf: testDir.appendingPathComponent("vault.jsonl"))
            let text = String(data: jsonlData, encoding: .utf8) ?? ""
            assertFalse(text.contains("\"password\":\"p@ss\""), "JSONL 中不应含明文密码")
            assertTrue(text.contains("\"name\":\"GitHub\""), "JSONL 中应有明文 name")
            print("testAddEntry passed")
        } catch {
            fputs("testAddEntry failed: \(error)\n", stderr); exit(1)
        }

        // --- testUnlockCorrectPassword ---
        do {
            let svc1 = VaultService(configDir: testDir)
            try svc1.createVault(masterPassword: "secret123")
            try svc1.addEntry(name: "GitHub", username: "loki", password: "p@ss", notes: "")
            svc1.lock()

            let svc2 = VaultService(configDir: testDir)
            try svc2.unlock(masterPassword: "secret123")
            assertTrue(svc2.isUnlocked, "正确密码应解锁")
            assertEqual(svc2.entries.count, 1, "解锁后应载入 1 条")
            assertEqual(svc2.entries[0].password, "p@ss", "解密后密码应为明文")
            print("testUnlockCorrectPassword passed")
        } catch {
            fputs("testUnlockCorrectPassword failed: \(error)\n", stderr); exit(1)
        }

        // --- testUnlockWrongPassword ---
        do {
            let svc1 = VaultService(configDir: testDir)
            try svc1.createVault(masterPassword: "secret123")
            try svc1.addEntry(name: "GitHub", username: "loki", password: "p@ss", notes: "")
            svc1.lock()

            let svc2 = VaultService(configDir: testDir)
            do {
                try svc2.unlock(masterPassword: "WRONG")
                fputs("testUnlockWrongPassword: 应抛错但未抛\n", stderr); exit(1)
            } catch {
                // 期望抛错
                assertFalse(svc2.isUnlocked, "错误密码后不应解锁")
            }
            print("testUnlockWrongPassword passed")
        } catch {
            fputs("testUnlockWrongPassword failed: \(error)\n", stderr); exit(1)
        }

        // --- testUpdateEntry ---
        do {
            let svc = VaultService(configDir: testDir)
            try svc.createVault(masterPassword: "secret123")
            try svc.addEntry(name: "GitHub", username: "loki", password: "old", notes: "")
            let id = svc.entries[0].id
            var updated = svc.entries[0]
            updated.password = "new"
            try svc.updateEntry(updated)
            assertEqual(svc.entries[0].password, "new", "更新后密码应变")

            // 重启验证
            svc.lock()
            try svc.unlock(masterPassword: "secret123")
            assertEqual(svc.entries[0].password, "new", "重启后密码应保持更新")
            print("testUpdateEntry passed")
        } catch {
            fputs("testUpdateEntry failed: \(error)\n", stderr); exit(1)
        }

        // --- testDeleteEntry ---
        do {
            let svc = VaultService(configDir: testDir)
            try svc.createVault(masterPassword: "secret123")
            try svc.addEntry(name: "A", username: "u", password: "1", notes: "")
            try svc.addEntry(name: "B", username: "u", password: "2", notes: "")
            let id = svc.entries[0].id
            try svc.deleteEntry(id: id)
            assertEqual(svc.entries.count, 1, "删除后应剩 1 条")
            assertEqual(svc.entries[0].name, "B", "应剩 B")
            print("testDeleteEntry passed")
        } catch {
            fputs("testDeleteEntry failed: \(error)\n", stderr); exit(1)
        }

        // --- testPerEntryNonce ---
        do {
            let svc = VaultService(configDir: testDir)
            try svc.createVault(masterPassword: "secret123")
            try svc.addEntry(name: "A", username: "u", password: "same", notes: "")
            try svc.addEntry(name: "B", username: "u", password: "same", notes: "")

            // 读 JSONL 两条的 nonce 应不同
            let jsonlData = try Data(contentsOf: testDir.appendingPathComponent("vault.jsonl"))
            let text = String(data: jsonlData, encoding: .utf8) ?? ""
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            assertEqual(lines.count, 2, "应有 2 行 JSONL")
            let entry1 = try! JSONDecoder().decode(EncryptedEntry.self, from: lines[0].data(using: .utf8)!)
            let entry2 = try! JSONDecoder().decode(EncryptedEntry.self, from: lines[1].data(using: .utf8)!)
            assertFalse(entry1.nonce == entry2.nonce, "两条同密码的 nonce 应不同")
            assertFalse(entry1.password == entry2.password, "两条同密码的密文应不同")
            print("testPerEntryNonce passed")
        } catch {
            fputs("testPerEntryNonce failed: \(error)\n", stderr); exit(1)
        }

        // --- testFullValidationOnUnlock ---
        do {
            let svc1 = VaultService(configDir: testDir)
            try svc1.createVault(masterPassword: "secret123")
            try svc1.addEntry(name: "A", username: "u", password: "1", notes: "")
            svc1.lock()

            // 篡改 JSONL 中的密文
            let url = testDir.appendingPathComponent("vault.jsonl")
            var text = try String(contentsOf: url, encoding: .utf8)
            // 把密文的第一个字符改掉
            if let range = text.range(of: "\"password\":\"") {
                let nextIdx = text.index(range.upperBound, offsetBy: 1)
                text.replaceSubrange(range.upperBound..<nextIdx, with: "X")
            }
            try text.write(to: url, atomically: true, encoding: .utf8)

            let svc2 = VaultService(configDir: testDir)
            do {
                try svc2.unlock(masterPassword: "secret123")
                fputs("testFullValidationOnUnlock: 篡改后应抛错但未抛\n", stderr); exit(1)
            } catch {
                assertFalse(svc2.isUnlocked, "篡改后不应解锁")
            }
            print("testFullValidationOnUnlock passed")
        } catch {
            fputs("testFullValidationOnUnlock failed: \(error)\n", stderr); exit(1)
        }

        print("VaultServiceTests all passed")
    }
}
```

- [ ] **Step 3: 验证测试编译并运行**

Run:
```bash
swiftc src/PasswordEntry.swift src/VaultCryptoService.swift src/VaultService.swift src/PBKDF2.swift tests/VaultServiceTests.swift -o /tmp/vault-tests && /tmp/vault-tests
```
Expected: 输出 7 个 `test... passed` + `VaultServiceTests all passed`

- [ ] **Step 4: Commit**

```bash
git add tests/VaultServiceTests.swift src/VaultService.swift
git commit -m "test(vault): 新增 VaultService 双文件格式单元测试 + 测试用 init(configDir:)"
```

---

### Task 5: 将新测试注册到 run_all.sh

**Files:**
- Modify: `tests/run_all.sh`

- [ ] **Step 1: 在 run_all.sh 中追加 vault 测试编译运行**

在 `run_all.sh` 的 `swiftc ... MenuStateStoreTests` 行之后、`bash test_developer_settings.sh` 之前，插入：

```bash
swiftc "$REPO_ROOT/src/PasswordEntry.swift" \
       "$REPO_ROOT/src/VaultCryptoService.swift" \
       "$REPO_ROOT/src/VaultService.swift" \
       "$REPO_ROOT/src/PBKDF2.swift" \
       "$REPO_ROOT/tests/VaultServiceTests.swift" \
       -o /tmp/vault-tests
/tmp/vault-tests
```

完整修改后的 `run_all.sh`：

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$REPO_ROOT/README.md" ]; then
  echo "README.md is required"
  exit 1
fi

if [ ! -x "$REPO_ROOT/scripts/build.sh" ] || [ ! -x "$REPO_ROOT/scripts/package.sh" ]; then
  echo "scripts/build.sh/package.sh must all be executable"
  exit 1
fi

swiftc "$REPO_ROOT/src/MenuStateStore.swift" "$REPO_ROOT/tests/MenuStateStoreTests.swift" -o /tmp/menu-state-tests
/tmp/menu-state-tests

swiftc "$REPO_ROOT/src/PasswordEntry.swift" \
       "$REPO_ROOT/src/VaultCryptoService.swift" \
       "$REPO_ROOT/src/VaultService.swift" \
       "$REPO_ROOT/src/PBKDF2.swift" \
       "$REPO_ROOT/tests/VaultServiceTests.swift" \
       -o /tmp/vault-tests
/tmp/vault-tests

bash "$REPO_ROOT/tests/test_developer_settings.sh"
bash "$REPO_ROOT/tests/test_package_signing_keychain.sh"

echo "all tests passed"
```

- [ ] **Step 2: 运行全量测试**

Run: `just test`
Expected: `all tests passed`（含 `VaultServiceTests all passed`）

- [ ] **Step 3: Commit**

```bash
git add tests/run_all.sh
git commit -m "test(vault): 将 VaultServiceTests 注册到 run_all.sh"
```

---

### Task 6: 全量构建验证与手动验证

**Files:**
- 无文件改动，纯验证

- [ ] **Step 1: 全量构建**

Run: `just build`
Expected: 构建成功，无错误，输出 `✅ 构建成功`

- [ ] **Step 2: 运行全部测试**

Run: `just test`
Expected: `all tests passed`

- [ ] **Step 3: 手动验证应用启动**

Run: `dist/TonyToy`
Expected: 菜单栏图标出现，点击 → 显示菜单 → "密码管理器 (⌘⇧V)" 可点击 → 唤起窗口

- [ ] **Step 4: 手动验证密码管理器全流程**

1. ⌘⇧V 唤起密码管理器
2. 首次输入主密码 → 创建新库
3. 点 "+ 添加" → 添加一条密码（name/username/password/notes）
4. 在列表中看到该条
5. 搜索 → 能搜到
6. 右键 → 编辑 → 修改密码 → 保存
7. 右键 → 删除 → 确认删除
8. 关闭窗口再 ⌘⇧V → 输入主密码解锁 → 看到剩余条目

- [ ] **Step 5: 手动验证 JSONL 格式**

Run: `cat ~/.config/tony-toy/vault.jsonl`
Expected: 每行一个 JSON，`password` 字段是 base64 密文，`name`/`username`/`notes` 是明文

- [ ] **Step 6: 手动验证 git diff 友好性**

```bash
cd ~/.config/tony-toy  # 或指向 dotfiles 的符号链接目标
# 记录当前状态
git diff vault.jsonl  # 应无输出（未改动）
# 在应用中修改一条密码
git diff vault.jsonl  # 应只有对应行变化
```

- [ ] **Step 7: 手动验证 vault.json 稳定性**

```bash
# 在应用中增删改密码
cat ~/.config/tony-toy/vault.json  # salt/rounds 不变，只有首次创建时写过
git diff vault.json  # 应无变化
```

- [ ] **Step 8: 最终 commit（如有改动）**

```bash
git status  # 确认无未提交改动
```

---

## 迁移说明（代码完成后手动执行，不在本计划内）

代码完成并验证通过后，手动迁移旧 `vault.json`（旧格式全量加密）：
1. 用旧版本（迁移前的 git commit）解锁，记录所有明文 entries
2. 删除旧 `~/.config/tony-toy/vault.json`
3. 用新版本 `createVault` 创建新格式
4. 逐条 `addEntry` 导回
5. 确认 `vault.json` + `vault.jsonl` 都生成，git diff 正常
