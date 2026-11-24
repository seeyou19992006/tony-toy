import Carbon.HIToolbox
import Cocoa

/// Carbon 全局热键的统一封装。
///
/// `RegisterEventHotKey` 的回调是 C 函数指针 + 全局分发目标，
/// 多个热键共用同一个 handler，只能靠 `EventHotKeyID.signature` 区分。
/// 之前 `LauncherHotkeyManager` 和 `main.swift` 各写了一套这逻辑，
/// 且都有「忘记校验 signature 就会重复响应」的坑，这里收进一处。
///
/// 为什么用 Carbon 而不是 CGEvent tap：`RegisterEventHotKey` 不抢按键，
/// 只在系统层面注册组合键，触发时其它应用收不到——正是全局热键要的语义。
final class CarbonHotkey {
    /// 触发回调（主线程）
    var onTrigger: (() -> Void)?

    /// 日志与注册表用的标识
    let name: String

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// signature 用于在共享的分发目标里认出自己的事件。
    ///
    /// 四字符码（如 'TnyT'），同进程内必须唯一——两个热键用同一个
    /// signature 会导致两者都响应。
    private let signature: OSType
    private let hotkeyID: UInt32

    var isRegistered: Bool { hotKeyRef != nil }

    /// - Parameters:
    ///   - name: 日志标识，如 "启动器"
    ///   - signature: 四字符码，同进程内唯一
    ///   - hotkeyID: 同 signature 下的序号
    init(name: String, signature: OSType, hotkeyID: UInt32 = 1) {
        self.name = name
        self.signature = signature
        self.hotkeyID = hotkeyID
    }

    deinit {
        unregister()
    }

    // MARK: - 注册

    /// 注册（会先注销旧的，重复调用安全）
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: hotkeyID)
        let status = RegisterEventHotKey(
            keyCode, modifiers, id, GetEventDispatcherTarget(), 0, &ref)

        guard status == noErr, ref != nil else {
            dbg("热键[\(name)] 注册失败 status=\(status)")
            return false
        }
        hotKeyRef = ref

        // handler 只会被装一次：卸载旧的后重装，避免同一 signature 上堆叠多个
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let ptr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let hotkey = Unmanaged<CarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
                return hotkey.handle(event: event)
            },
            1, &spec, ptr, &eventHandler)

        InputRegistry.shared.note(name: "hotkey:\(name)", kind: .carbonHotkey)
        dbg("热键[\(name)] 已注册 keyCode=\(keyCode) modifiers=\(modifiers)")
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        InputRegistry.shared.remove(name: "hotkey:\(name)")
    }

    // MARK: - 分发

    private func handle(event: EventRef) -> OSStatus {
        // 分发目标是共享的，必须确认是自己的 ID，否则会响应别人的热键
        var received = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &received
        )
        guard status == noErr,
            received.signature == signature,
            received.id == hotkeyID
        else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?()
        }
        return noErr
    }
}

// MARK: - 四字符码

extension OSType {
    /// 把 "TnyL" 这样的四字符码转成 OSType，方便调用处写名字而不是魔数
    static func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        for (index, char) in string.utf8.prefix(4).enumerated() {
            result |= OSType(char) << (8 * (3 - index))
        }
        return result
    }
}
