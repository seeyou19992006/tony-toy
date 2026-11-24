import Foundation
import Cocoa

final class CapsMapperController {
    private var eventTap: CFMachPort?
    private var isLayerActive = false
    private var retryCount = 0
    private let capsSrc: Int64 = 0x700000039
    private let f19Dst: Int64 = 0x70000006E
    private let configStore = CapsMappingConfigStore()
    private let actionExecutor = AppActionExecutor()
    private var mappings: [Int64: CapsResolvedMapping] = [:]

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    /// 重新加载映射表（配置窗口改了映射后调用）。
    ///
    /// 不重建 event tap——`setEnabled(true)` 会先 stop() 再 start()，
    /// 短暂丢事件，而且 `start()` 里会重复跑一次 `hidutil property --set`。
    func reload() {
        guard eventTap != nil else { return }
        do {
            mappings = try configStore.loadMappings()
        } catch {
            fputs("Failed to reload caps mappings: \(error)\n", stderr)
            mappings = [:]
        }
        applyMapping(remap: true)
    }

    private func start() {
        stop()
        do {
            mappings = try configStore.loadMappings()
        } catch {
            fputs("Failed to load caps mappings from \(configStore.configURL.path): \(error)\n", stderr)
            mappings = [:]
        }
        applyMapping(remap: true)
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask), callback: { _, type, event, refcon in
            let controller = Unmanaged<CapsMapperController>.fromOpaque(refcon!).takeUnretainedValue()
            return controller.handleEvent(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            // 辅助功能权限可能还没生效，稍后重试，否则 Caps 层会永久失效
            retryCount += 1
            if retryCount <= 10 {
                fputs("CapsMapper tapCreate failed, retry \(retryCount)\n", stderr)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.start()
                }
            }
            return
        }
        retryCount = 0
        dbg("caps tap created")
        eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        isLayerActive = false
        mappings = [:]
        applyMapping(remap: false)
    }

    private func applyMapping(remap: Bool) {
        let mappings: [[String: Any]] = remap
            ? [[
                "HIDKeyboardModifierMappingSrc": capsSrc,
                "HIDKeyboardModifierMappingDst": f19Dst
            ]]
            : []
        _ = setUserKeyMappings(mappings)
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
            dbg("caps sees esc: layerActive=\(isLayerActive)")
        }

        if keyCode == 80 { // F19
            if type == .keyDown { isLayerActive = true; dbg("F19 down") }
            else if type == .keyUp { isLayerActive = false; dbg("F19 up") }
            return nil
        }
        if isLayerActive {
            if let mapping = mappings[keyCode] {
                dbg("caps map keyCode=\(keyCode)")
                if type == .keyDown { actionExecutor.dispatch(mapping.action) }
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func setUserKeyMappings(_ mappings: [[String: Any]]) -> Bool {
        let payload: [String: Any] = ["UserKeyMapping": mappings]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8),
              let output = runHidutil(arguments: ["property", "--set", json]) else {
            return false
        }
        return output.status == 0
    }

    private func runHidutil(arguments: [String]) -> (status: Int32, stdout: String, stderr: String)? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
