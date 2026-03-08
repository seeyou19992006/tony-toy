import Foundation
import Cocoa

final class MouseLayerController {
    private let configStore = MouseLayerConfigStore()
    private let volumeEngine = VolumeScrollEngine()
    private let actionExecutor = AppActionExecutor()
    private var eventTap: CFMachPort?
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

        let eventMask = (1 << CGEventType.scrollWheel.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.leftMouseUp.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseUp.rawValue) |
                        (1 << CGEventType.otherMouseDown.rawValue) |
                        (1 << CGEventType.otherMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                let controller = Unmanaged<MouseLayerController>.fromOpaque(refcon!).takeUnretainedValue()
                return controller.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        volumeEngine.stop()
        isLayerActive = false
        suppressedMouseButtons.removeAll()
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        switch type {
        case _ where isMouseDown(type) && buttonNumber == layerConfig.activationButton:
            reloadLayerConfig()
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

        if isLayerActive, isMouseUp(type), suppressedMouseButtons.contains(buttonNumber) {
            suppressedMouseButtons.remove(buttonNumber)
            return nil
        }

        return Unmanaged.passUnretained(event)
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
