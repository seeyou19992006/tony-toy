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
