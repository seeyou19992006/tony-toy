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
