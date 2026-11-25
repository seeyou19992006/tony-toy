import Foundation
import Cocoa

final class MouseLayerController {
    private let configStore = MouseLayerConfigStore()
    private let volumeEngine = VolumeScrollEngine()
    private let actionExecutor = AppActionExecutor()
    /// 创建/禁用恢复/录制放行都由 `EventTap` 统一处理
    private lazy var tap = EventTap(
        name: "mouseLayer",
        events: .make([
            .scrollWheel,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ])
    ) { [weak self] type, event in
        self?.handleEvent(type: type, event: event)
    }

    private var layerConfig = MouseLayerResolvedConfig.fallback
    private var isLayerActive = false
    private var suppressedMouseButtons: Set<Int64> = []

    var onVolumeChanged: ((Float32) -> Void)? {
        get { volumeEngine.onVolumeChanged }
        set { volumeEngine.onVolumeChanged = newValue }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    private func start() {
        stop()
        reloadLayerConfig()
        volumeEngine.start()

        tap.start()
    }

    private func stop() {
        tap.stop()
        volumeEngine.stop()
        isLayerActive = false
        suppressedMouseButtons.removeAll()
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> CGEvent? {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        switch type {
        case _ where isMouseDown(type) && buttonNumber == layerConfig.activationButton:
            isLayerActive = true
            volumeEngine.beginInteraction()
            return nil
        case _ where isMouseUp(type) && buttonNumber == layerConfig.activationButton:
            isLayerActive = false
            volumeEngine.endInteraction()
            return nil
        case .scrollWheel:
            if isLayerActive, let action = layerConfig.action(for: type, buttonNumber: nil) {
                handleLayerAction(action, event: event)
                return nil
            }
        default:
            break
        }

        if isLayerActive, isMouseDown(type), let action = layerConfig.action(for: type, buttonNumber: buttonNumber) {
            if buttonNumber != layerConfig.activationButton {
                execute(action)
                suppressedMouseButtons.insert(buttonNumber)
                return nil
            }
        }

        if isMouseUp(type), suppressedMouseButtons.contains(buttonNumber) {
            suppressedMouseButtons.remove(buttonNumber)
            return nil
        }

        return event
    }

    /// 重新加载层配置（配置窗口改了映射后调用）。
    func reload() {
        reloadLayerConfig()
    }

    private func reloadLayerConfig() {
        do {
            layerConfig = try configStore.loadConfig()
        } catch {
            fputs("Failed to load mouse layer config from \(configStore.configURL.path): \(error)\n", stderr)
            layerConfig = .fallback
        }
    }

    private func handleLayerAction(_ action: MouseLayerAction, event: CGEvent) {
        switch action {
        case .volumeScroll:
            let delta = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            volumeEngine.handleScroll(delta: delta)
        case .appAction:
            execute(action)
        }
    }

    private func execute(_ action: MouseLayerAction) {
        switch action {
        case .volumeScroll:
            break
        case .appAction(let appAction):
            actionExecutor.dispatch(appAction)
        }
    }

    static func shortcutEventPlan(keyCode: CGKeyCode, modifiers: CGEventFlags) -> [KeyboardShortcutEvent] {
        AppActionExecutor.shortcutEventPlan(keyCode: keyCode, modifiers: modifiers)
    }

    private func isMouseDown(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    private func isMouseUp(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }
}
