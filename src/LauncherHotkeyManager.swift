import Carbon.HIToolbox
import Cocoa

/// 用 Carbon 注册系统级热键，不依赖辅助功能权限
final class LauncherHotkeyManager {
    static let signature: OSType = 0x4C4E4348 // 'LNCH'
    static let hotKeyID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var trigger: (() -> Void)?

    deinit {
        unregister()
    }

    @discardableResult
    func register(_ spec: HotkeySpec, onTrigger: @escaping () -> Void) -> Bool {
        unregister()
        trigger = onTrigger

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr, hotKeyRef != nil else {
            NSLog("热键注册失败: \(status)")
            return false
        }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }

            // 事件分发目标会被多个热键共享，必须确认是自己的那个才处理
            var identifier = EventHotKeyID()
            let readStatus = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard readStatus == noErr,
                  identifier.signature == LauncherHotkeyManager.signature,
                  identifier.id == LauncherHotkeyManager.hotKeyID else {
                return OSStatus(eventNotHandledErr)
            }

            let manager = Unmanaged<LauncherHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.trigger?()
            }
            return noErr
        }

        let installStatus = InstallEventHandler(GetEventDispatcherTarget(), handler, 1,
                                                &eventSpec, selfPointer, &eventHandler)
        if installStatus != noErr {
            NSLog("热键事件处理器安装失败: \(installStatus)")
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
