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
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        guard let mapping = mappings.first(where: { $0.matches(keyCode: keyCode, flags: flags) }) else {
            return event
        }

        if type == .keyDown {
            actionExecutor.dispatch(mapping.action, phase: .keyDown)
        } else if type == .keyUp {
            actionExecutor.dispatch(mapping.action, phase: .keyUp)
        }
        return nil
    }


}
