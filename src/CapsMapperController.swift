import Foundation
import Cocoa

final class CapsMapperController {
    private var eventTap: CFMachPort?
    private var isLayerActive = false
    private let capsSrc: Int64 = 0x700000039
    private let f19Dst: Int64 = 0x70000006E
    private let configStore = CapsMappingConfigStore()
    private let actionExecutor = AppActionExecutor()
    private var mappings: [Int64: CapsResolvedMapping] = [:]

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
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
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 80 { // F19
            if type == .keyDown { isLayerActive = true }
            else if type == .keyUp { isLayerActive = false }
            return nil
        }
        if isLayerActive {
            if let mapping = mappings[keyCode] {
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
