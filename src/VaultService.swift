import Foundation

// MARK: - Vault 存储

struct VaultContainer: Codable {
    var encryptedData: Data
    var salt: Data
    var nonce: Data
}

// MARK: - Vault 服务

class VaultService {
    private let crypto = VaultCryptoService()
    private let vaultURL: URL
    private var masterKeyData: Data?  // 存储派生的密钥数据
    
    var isUnlocked: Bool { masterKeyData != nil }
    public var vaultExists: Bool { FileManager.default.fileExists(atPath: vaultURL.path) }
    var entries: [PasswordEntry] = []
    
    init() {
        // 使用 ~/.config/tony-toy 目录
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("tony-toy")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        vaultURL = configDir.appendingPathComponent("vault.json")
    }
    
    /// 首次创建 vault
    func createVault(masterPassword: String) throws {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let nonce = Data((0..<12).map { _ in UInt8.random(in: 0...255) })

        masterKeyData = pbkdf2(password: masterPassword, salt: salt)
        entries = []

        // 使用新生成的 salt 和 nonce 保存 vault
        let entriesData = try JSONEncoder().encode(entries)
        let encrypted = try crypto.encrypt(entriesData, keyData: masterKeyData!, nonce: nonce)

        let container = VaultContainer(encryptedData: encrypted, salt: salt, nonce: nonce)
        let finalData = try JSONEncoder().encode(container)
        try finalData.write(to: vaultURL)
    }
    
    /// 解锁 vault
    func unlock(masterPassword: String) throws {
        guard vaultExists else {
            throw VaultError.vaultNotFound
        }

        let data = try Data(contentsOf: vaultURL)
        let container = try JSONDecoder().decode(VaultContainer.self, from: data)

        let keyData = pbkdf2(password: masterPassword, salt: container.salt)
        let decrypted = try crypto.decrypt(container.encryptedData, keyData: keyData)

        masterKeyData = keyData
        entries = try JSONDecoder().decode([PasswordEntry].self, from: decrypted)
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
    
    // MARK: - 私有
    
    private func save() throws {
        guard let keyData = masterKeyData else { throw VaultError.notUnlocked }
        
        // 读取已有的 salt/nonce
        var salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        var nonce = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        
        if vaultExists {
            let stored = try Data(contentsOf: vaultURL)
            let container = try JSONDecoder().decode(VaultContainer.self, from: stored)
            salt = container.salt
            nonce = container.nonce
        }
        
        let entriesData = try JSONEncoder().encode(entries)
        let encrypted = try crypto.encrypt(entriesData, keyData: keyData, nonce: nonce)
        
        let container = VaultContainer(encryptedData: encrypted, salt: salt, nonce: nonce)
        let finalData = try JSONEncoder().encode(container)
        try finalData.write(to: vaultURL)
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
