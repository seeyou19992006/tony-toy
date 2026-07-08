import Foundation

// MARK: - Vault 服务
class VaultService {
    private let crypto = VaultCryptoService()
    private let configDir: URL
    private let vaultJSONLURL: URL
    private var masterKeyData: Data?  // 存储派生的密钥数据

    // 固定 salt + PBKDF2 参数，不同机器共享，安全性靠主密码强度 + 迭代次数
    private static let salt = Data([
        0x4a, 0x7c, 0x91, 0x23, 0xd6, 0x58, 0xb4, 0x1f,
        0xe0, 0xa2, 0x37, 0x9c, 0x6b, 0x50, 0x8d, 0x3f
    ])
    private static let pbkdf2Rounds = 100000

    var isUnlocked: Bool { masterKeyData != nil }
    var vaultExists: Bool { FileManager.default.fileExists(atPath: vaultJSONLURL.path) }
    var entries: [PasswordEntry] = []

    init() {
        configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("tony-toy")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        vaultJSONLURL = configDir.appendingPathComponent("vault.jsonl")
    }

    // 测试用：注入 configDir
    init(configDir: URL) {
        self.configDir = configDir
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        vaultJSONLURL = configDir.appendingPathComponent("vault.jsonl")
    }

    /// 首次创建 vault（写空 JSONL）
    func createVault(masterPassword: String) throws {
        masterKeyData = pbkdf2(password: masterPassword, salt: Self.salt,
                               keyByteCount: 32, rounds: Self.pbkdf2Rounds)
        entries = []
        try Data().write(to: vaultJSONLURL, options: .atomic)
    }

    /// 解锁 vault（全量验证：逐条解密，任一失败则抛 wrongPassword）
    func unlock(masterPassword: String) throws {
        guard vaultExists else {
            throw VaultError.vaultNotFound
        }

        let keyData = pbkdf2(password: masterPassword, salt: Self.salt,
                             keyByteCount: 32, rounds: Self.pbkdf2Rounds)

        // 逐行读 JSONL，全量验证
        var loaded: [PasswordEntry] = []
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
