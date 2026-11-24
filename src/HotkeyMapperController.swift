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

    /// 重新加载映射表（配置窗口改了映射后调用）。
    /// 不重建 event tap，避免短暂丢事件。
    func reload() {
        guard eventTap != nil else { return }
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
        // 配置窗口正在录制快捷键：放行所有按键，否则录制器收不到。
        // 必须在任何 consume/改写之前判断。
        if HotkeyRecorder.isRecording { return Unmanaged.passUnretained(event) }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if keyCode == 53 {
            dbg("hotkey sees esc: flags=\(event.flags.rawValue)")
        }

        // Esc 一律放行。Cmd 修饰键状态可能残留（本程序接管 ⌘Tab 后更容易出现），
        // 一旦残留，Esc 会被误判成 ⌘Esc 并命中 hotkeys.json 的映射而遭吞掉。
        // 代价是配置文件里的 escape+command 映射不再生效，Esc 优先交给当前窗口。
        let blockers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate]
        if keyCode == 53, event.flags.intersection(blockers).isEmpty {
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
