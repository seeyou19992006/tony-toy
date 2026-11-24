import Foundation
import Cocoa

final class CapsMapperController {
    private var isLayerActive = false

    /// 创建/重试/禁用恢复/录制放行都由 `EventTap` 统一处理
    private lazy var tap = EventTap(
        name: "capsLayer",
        events: .make([.keyDown, .keyUp, .flagsChanged])
    ) { [weak self] type, event in
        self?.handleEvent(type: type, event: event)
    }

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
        guard tap.isRunning else { return }
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
        tap.start()
    }

    private func stop() {
        tap.stop()
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

    private func handleEvent(type: CGEventType, event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

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
        return event
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
