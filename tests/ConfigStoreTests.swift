import Foundation

func testConfigDefaults() {
    let config = TonyToyConfig.default

    assertTrue(config.version == 1, "版本号应为 1")
    assertTrue(config.general.theme == .system, "主题默认跟随系统")
    assertTrue(config.general.showMenuBarIcon, "菜单栏图标默认显示")
    assertTrue(config.general.launchAtLogin == false, "开机自启默认关闭")
    print("testConfigDefaults passed")
}

func testConfigRoundTrip() {
    var config = TonyToyConfig.default
    config.general.theme = .dark
    config.features["capsLayer"] = FeatureConfig(
        isEnabled: true,
        values: ["mappings": .array([
            .object(["from": .string("e"), "to": .object(["key": .string("up_arrow")])])
        ])]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let data = try! encoder.encode(config)
    let decoded = try! JSONDecoder().decode(TonyToyConfig.self, from: data)

    assertTrue(decoded == config, "配置往返应保持不变")
    assertTrue(decoded.general.theme == .dark, "主题应持久化")
    print("testConfigRoundTrip passed")
}

func testFeatureEnabledLookup() {
    var config = TonyToyConfig.default
    config.features["gamepad"] = FeatureConfig(isEnabled: false, values: [:])

    assertTrue(config.isEnabled("gamepad") == false, "已配置的功能应返回其开关值")
    assertTrue(config.isEnabled("unknown") == true, "未知功能默认启用")
    print("testFeatureEnabledLookup passed")
}

func testConfigToleratesMissingFields() {
    // 只写了 theme，其他字段全缺失
    let json = #"{"general":{"theme":"dark"}}"#.data(using: .utf8)!
    let config = try! JSONDecoder().decode(TonyToyConfig.self, from: json)

    assertTrue(config.version == 1, "缺失 version 应用当前版本")
    assertTrue(config.general.theme == .dark, "已写字段应保留")
    assertTrue(config.general.launchAtLogin == false, "缺失 launchAtLogin 用默认值")
    assertTrue(config.general.showMenuBarIcon == true, "缺失 showMenuBarIcon 用默认值")
    assertTrue(config.features.isEmpty, "缺失 features 应为空")
    print("testConfigToleratesMissingFields passed")
}

func testFeatureConfigToleratesMissingFields() {
    let json = #"{"features":{"gamepad":{}}}"#.data(using: .utf8)!
    let config = try! JSONDecoder().decode(TonyToyConfig.self, from: json)

    assertTrue(config.features["gamepad"]?.isEnabled == true, "缺失 isEnabled 默认启用")
    assertTrue(config.features["gamepad"]?.values.isEmpty == true, "缺失 values 应为空")
    print("testFeatureConfigToleratesMissingFields passed")
}

func testConfigEmptyFeaturesByDefault() {
    let config = TonyToyConfig.default
    assertTrue(config.features.isEmpty, "默认配置的 features 应为空")
    assertTrue(TonyToyConfig.currentVersion == 1, "当前版本号应为 1")
    print("testConfigEmptyFeaturesByDefault passed")
}

@main
struct ConfigStoreTests {
    static func main() {
        testConfigDefaults()
        testConfigRoundTrip()
        testFeatureEnabledLookup()
        testConfigToleratesMissingFields()
        testFeatureConfigToleratesMissingFields()
        testConfigEmptyFeaturesByDefault()
        print("ConfigStoreTests all passed")
    }
}

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        print("❌ \(message)")
        exit(1)
    }
}
