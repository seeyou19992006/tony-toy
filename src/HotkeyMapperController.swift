import Foundation
import Cocoa

final class HotkeyMapperController {
    private var eventTap: CFMachPort?
    private let configStore = HotkeyMappingConfigStore()
    private let actionExecutor = AppActionExecutor()
    private var mappings: [HotkeyResolvedMapping] = []
    private var retryCount = 0

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    private func start() {
        stop()
        do {
            mappings = try configStore.loadMappings()
            fputs("Loaded \(mappings.count) hotkey mappings from \(configStore.configURL.path).\n", stderr)
        } catch {
            fputs("Failed to load hotkey mappings from \(configStore.configURL.path): \(error)\n", stderr)
            mappings = []
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                let controller = Unmanaged<HotkeyMapperController>.fromOpaque(refcon!).takeUnretainedValue()
                return controller.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            retryCount += 1
            if retryCount <= 10 {
                fputs("HotkeyMapper tapCreate failed, retry \(retryCount)\n", stderr)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.start()
                }
            }
            return
        }
        retryCount = 0

        eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        mappings = []
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // 裸 Esc 直接放行：它不属于热键层（配置里只有 ⌘Esc），
        // 让面板/输入法立即拿到，避免在 tap 里走匹配链路
        let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        if keyCode == 53, event.flags.intersection(modifiers).isEmpty {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        guard let mapping = mappings.first(where: { $0.matches(keyCode: keyCode, flags: flags) }) else {
            logModifierMismatchIfNeeded(keyCode: keyCode, flags: flags, type: type)
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, let line = Self.hotkeyMatchedLogLine(keyCode: keyCode, flags: mapping.sourceModifiers) {
            fputs(line, stderr)
        }
        if type == .keyDown {
            actionExecutor.dispatch(mapping.action, phase: .keyDown)
        } else if type == .keyUp {
            actionExecutor.dispatch(mapping.action, phase: .keyUp)
        }
        return nil
    }

    static func hotkeyMatchedLogLine(keyCode: Int64, flags: CGEventFlags) -> String? {
        nil
    }

    private func logModifierMismatchIfNeeded(keyCode: Int64, flags: CGEventFlags, type: CGEventType) {
        guard type == .keyDown else {
            return
        }
        let candidates = mappings.filter { $0.sourceCode == keyCode }
        guard !candidates.isEmpty else {
            return
        }
        let normalized = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn])
        let expectedFlags = candidates.map(\.sourceModifiers.rawValue).map(String.init).joined(separator: ", ")
        fputs(
            "Hotkey pass-through: keyCode=\(keyCode) actualFlags=\(normalized.rawValue) expectedFlags=[\(expectedFlags)].\n",
            stderr
        )
    }
}
