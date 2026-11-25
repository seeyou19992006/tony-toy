import Foundation
import Cocoa

final class HotkeyMapperController {
    /// 创建/重试/禁用恢复/录制放行都由 `EventTap` 统一处理
    private lazy var tap = EventTap(
        name: "hotkeyLayer",
        events: .make([.keyDown, .keyUp])
    ) { [weak self] type, event in
        self?.handleEvent(type: type, event: event)
    }

    private let configStore = HotkeyMappingConfigStore()
    private let actionExecutor = AppActionExecutor()
    private var mappings: [HotkeyResolvedMapping] = []
    /// 记录按下的映射，避免用户先松开修饰键时 `.keyUp` 漏匹配导致按键卡住或泄露给前台应用
    private var activeMappings: [Int64: HotkeyResolvedMapping] = [:]

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    /// 重新加载映射表（配置窗口改了映射后调用）。
    /// 不重建 event tap，避免短暂丢事件。
    func reload() {
        guard tap.isRunning else { return }
        do {
            mappings = try configStore.loadMappings()
        } catch {
            fputs("Failed to reload hotkey mappings: \(error)\n", stderr)
            mappings = []
        }
    }

    private func start() {
        stop()
        do {
            mappings = try configStore.loadMappings()
            fputs("Loaded \(mappings.count) hotkey mappings.\n", stderr)
        } catch {
            fputs("Failed to load hotkey mappings from \(configStore.configURL.path): \(error)\n", stderr)
            mappings = []
        }

        tap.start()
    }

    private func stop() {
        tap.stop()
        mappings = []
        activeMappings.removeAll()
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, let active = activeMappings.removeValue(forKey: keyCode) {
            actionExecutor.dispatch(active.action, phase: .keyUp)
            return nil
        }

        let flags = event.flags
        guard let mapping = mappings.first(where: { $0.matches(keyCode: keyCode, flags: flags) }) else {
            return event
        }

        if type == .keyDown {
            activeMappings[keyCode] = mapping
            actionExecutor.dispatch(mapping.action, phase: .keyDown)
        }
        return nil
    }


}
