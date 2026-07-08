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
