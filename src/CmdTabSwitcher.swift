import Foundation
import Cocoa

/// 接管 ⌘Tab：按下时呼出启动器，按住 ⌘ 期间循环选择，松开 ⌘ 执行选中项
final class CmdTabSwitcher {
    private var isActive = false

    /// 创建/重试/禁用恢复/录制放行都由 `EventTap` 统一处理
    private lazy var tap = EventTap(
        name: "cmdTabSwitcher",
        events: .make([.keyDown, .flagsChanged])
    ) { [weak self] type, event in
        self?.handleEvent(type: type, event: event)
    }

    private let tabKeyCode: Int64 = 48
    private let escKeyCode: Int64 = 53
    private let returnKeyCode: Int64 = 36
    private let leftKeyCode: Int64 = 123
    private let rightKeyCode: Int64 = 124
    private let downKeyCode: Int64 = 125
    private let upKeyCode: Int64 = 126
    // 字母导航：E 上、D 下、S 左、F 右
    private let eKeyCode: Int64 = 14
    private let dKeyCode: Int64 = 2
    private let sKeyCode: Int64 = 1
    private let fKeyCode: Int64 = 3
    private let wKeyCode: Int64 = 13

    func start() {
        tap.start()
    }

    func stop() {
        tap.stop()
        isActive = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // ⌘Tab：第一次呼出，之后在列表里循环
        if type == .keyDown, keyCode == tabKeyCode, flags.contains(.maskCommand) {
            let backward = flags.contains(.maskShift)
            if !isActive {
                if Thread.isMainThread {
                    isActive = SwitcherController.shared.show()
                } else {
                    isActive = true
                    DispatchQueue.main.async { [weak self] in
                        let shown = SwitcherController.shared.show()
                        if !shown {
                            self?.isActive = false
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    SwitcherController.shared.moveSequential(by: backward ? -1 : 1)
                }
            }
            return nil
        }

        // 兜底：⌘ 已经松开但 isActive 还挂着。
        //
        // 事件流中断（切到别的应用、tap 被系统临时禁用）会丢 flagsChanged，
        // isActive 永远停在 true，之后每次按 Esc / 方向键都会被上面的
        // 导航分支吞掉——这是「快捷键时而失灵」的根源。
        if isActive, type == .keyDown, !flags.contains(.maskCommand) {
            isActive = false
            DispatchQueue.main.async { SwitcherController.shared.cancel() }
        }

        // 松开 ⌘：执行选中项
        if type == .flagsChanged, isActive, !flags.contains(.maskCommand) {
            isActive = false
            DispatchQueue.main.async {
                SwitcherController.shared.commit()
            }
            return event
        }

        // 按住 ⌘ 期间：方向键或 E/D/S/F 导航，全部吞掉避免提示音
        if type == .keyDown, isActive {
            switch keyCode {
            case escKeyCode:
                isActive = false
                DispatchQueue.main.async { SwitcherController.shared.cancel() }
                return nil
            case returnKeyCode:
                isActive = false
                DispatchQueue.main.async { SwitcherController.shared.commit() }
                return nil
            case leftKeyCode, sKeyCode:
                DispatchQueue.main.async { SwitcherController.shared.moveHorizontal(by: -1) }
                return nil
            case rightKeyCode, fKeyCode:
                DispatchQueue.main.async { SwitcherController.shared.moveHorizontal(by: 1) }
                return nil
            case upKeyCode, eKeyCode:
                DispatchQueue.main.async { SwitcherController.shared.moveVertical(by: -1) }
                return nil
            case downKeyCode, dKeyCode:
                DispatchQueue.main.async { SwitcherController.shared.moveVertical(by: 1) }
                return nil
            case wKeyCode:
                // 有窗口时按 W 关闭窗口；无窗口应用按 W 退出应用
                DispatchQueue.main.async { SwitcherController.shared.closeOrQuitSelected() }
                return nil
            default:
                // 其它按键放行，交给 Caps 层映射（Caps+E/D/S/F → 方向键）
                break
            }
        }

        return event
    }
}
