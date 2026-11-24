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
