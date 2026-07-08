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
        fputs("Assertion failed: \(message)\n", stderr)
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
