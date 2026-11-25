import Foundation

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message)\n  actual:   \(actual)\n  expected: \(expected)\n", stderr)
        exit(1)
    }
}

private func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func testSwitcherGridRules() {
    assertEqual(SwitcherController.grid(for: 0).rows, 1, "0 项应回退 1 行")
    assertEqual(SwitcherController.grid(for: 1).rows, 1, "1 项应为 1 行")
    assertEqual(SwitcherController.grid(for: 4).rows, 1, "4 项应为 1 行")
    assertEqual(SwitcherController.grid(for: 4).cols, 4, "4 项应为 1x4")

    assertEqual(SwitcherController.grid(for: 5).rows, 2, "5 项应为 2 行")
    assertEqual(SwitcherController.grid(for: 5).cols, 3, "5 项应为 2x3")
    assertEqual(SwitcherController.grid(for: 9).rows, 2, "9 项应为 2 行")
    assertEqual(SwitcherController.grid(for: 9).cols, 5, "9 项应为 2x5")
    assertEqual(SwitcherController.grid(for: 10).rows, 2, "10 项应为 2 行")
    assertEqual(SwitcherController.grid(for: 10).cols, 5, "10 项应为 2x5")

    assertEqual(SwitcherController.grid(for: 11).rows, 3, "11 项应为 3 行")
    assertEqual(SwitcherController.grid(for: 11).cols, 4, "11 项应为 3x4")
    assertEqual(SwitcherController.grid(for: 19).rows, 3, "19 项应为 3 行")
    assertEqual(SwitcherController.grid(for: 19).cols, 7, "19 项应为 3x7")

    assertEqual(SwitcherController.grid(for: 20).rows, 4, "20 项应为 4 行")
    assertEqual(SwitcherController.grid(for: 20).cols, 5, "20 项应为 4x5")

    print("testSwitcherGridRules passed")
}

private func testPinyinConvertAndExtraReadings() {
    let ascii = Pinyin.convert("T3-Code")
    assertTrue(ascii.fulls.contains("t3code"), "英文应保留完整字母数字")
    assertTrue(ascii.initials.contains("tc"), "英文词组应提取首字母")

    let extra: [Character: String] = ["微": "wei", "信": "xin"]
    let wechat = Pinyin.convert("微信", extraReadings: extra)
    assertTrue(wechat.fulls.contains("weixin"), "extraReadings 应产出全拼")
    assertTrue(wechat.initials.contains("wx"), "extraReadings 应产出首字母")

    let poly = Pinyin.convert("音乐")
    assertTrue(poly.fulls.contains("yinle") && poly.fulls.contains("yinyue"), "多音字应保留多读音变体")

    print("testPinyinConvertAndExtraReadings passed")
}

@main
struct SwitcherAndPinyinTestsMain {
    static func main() {
        testSwitcherGridRules()
        testPinyinConvertAndExtraReadings()
        print("SwitcherAndPinyinTests all passed")
    }
}
