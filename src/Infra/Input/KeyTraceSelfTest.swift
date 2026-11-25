import Cocoa

/// 按键追踪面板的自测：反复「打开 → 关闭并释放 → 灌事件」。
///
/// 存在的理由：关窗口崩溃过两次，每次都要人手动复现。这个自测把
/// 「EventTap 停掉后对象被释放、但事件还在流」那个竞态固定下来，
/// 用 `--keytrace-selftest` 跑十几秒就能验证，不用再麻烦人。
enum KeyTraceSelfTest {
    private static var panel: KeyTracePanel?
    private static var round = 0
    private static let totalRounds = 20

    static func run() {
        NSLog("[selftest] 开始：\(totalRounds) 轮 打开→关闭释放，每轮灌 50 个键盘事件")

        let timer = Timer(timeInterval: 0.6, repeats: true) { ticker in
            round += 1

            if round % 2 == 1 {
                let p = KeyTracePanel()
                p.show()
                panel = p
            } else {
                panel?.closeForTest()
                // 让 EventTap 真的被释放：InputRegistry 里只有 weak 引用，
                // 这里不放掉就是自测把对象续着，测不出悬垂
                panel = nil
            }

            // 关闭的瞬间到下一轮之间一直在发事件——正是崩溃发生的窗口
            let source = CGEventSource(stateID: .hidSystemState)
            for i in 0..<50 {
                let code = CGKeyCode(10 + (i % 40))
                CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?
                    .post(tap: .cgSessionEventTap)
                CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?
                    .post(tap: .cgSessionEventTap)
            }

            NSLog("[selftest] 第 \(round) 轮完成")

            if round >= totalRounds {
                ticker.invalidate()
                NSLog("[selftest] 全部 \(totalRounds) 轮跑完，未崩溃")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSApp.terminate(nil)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
