import Cocoa

/// CGEvent tap 的统一封装。
///
/// 为什么要封装：之前 5 个 controller 各自复制同一套样板——
/// 创建 tap、权限失败重试、挂 run loop、被系统禁用后恢复、录制态放行、
/// 清理。其中「录制态放行」这一句在 5 处各写一遍，
/// `CmdTabSwitcher` 漏了，导致录制快捷键时 Esc/Enter/方向键被吞，
/// 排查花了很久。收进封装后不可能再漏。
///
/// 生命周期：`start()` 幂等，重复调用不会建第二个 tap；
/// `stop()` 会注销并释放。tap 被系统临时禁用（超时/用户输入）时自动重新启用。
final class EventTap {
    /// 处理函数。返回 nil 表示消费掉事件，返回 event 表示放行。
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    /// 日志与注册表用的标识（如 "hotkeyLayer"）
    let name: String

    /// 监听的事件掩码（注册表反解事件列表用）
    let events: CGEventMask
    private let handler: Handler

    private var tap: CFMachPort?
    /// 必须自己持有：stop() 时要显式移除，否则 RunLoop 拿着 source 不放，
    /// 而 source 的 refcon 指向本对象——本对象一释放，下一个事件就是野指针。
    private var runLoopSource: CFRunLoopSource?
    private var retryCount = 0
    private static let maxRetries = 10
    private static let retryDelay: TimeInterval = 1.0

    /// 是否在运行（已创建且未被 stop）
    var isRunning: Bool { tap != nil }

    /// 是否被系统临时禁用（诊断用）
    var isEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    init(name: String, events: CGEventMask, handler: @escaping Handler) {
        self.name = name
        self.events = events
        self.handler = handler
    }

    deinit {
        teardown()
    }

    // MARK: - 生命周期

    func start() {
        guard tap == nil else { return }
        retryCount = 0
        createTap()
    }

    func stop() {
        teardown()
        retryCount = 0
        InputRegistry.shared.unregister(self)
    }

    /// 彻底拆掉这个 tap。
    ///
    /// 只 `tapEnable(false)` 是不够的：RunLoop 那边还挂着 source，
    /// 系统事件队列里也可能还有一个在途事件。此时如果本对象被释放，
    /// 回调里的 `takeUnretainedValue()` 就会拿到野指针。
    /// 实测崩溃点在 `dispatch` 里拼 `name` 的字符串时（SIGSEGV @ 0x18）。
    ///
    /// 顺序要严格：先停 tap → 摘 source → invalidate port → 最后清空引用。
    private func teardown() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap {
            CFMachPortInvalidate(tap)
        }
        tap = nil
    }

    // MARK: - 内部

    private func createTap() {
        let mask = events
        let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let wrapper = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return wrapper.dispatch(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let created else {
            scheduleRetry()
            return
        }

        tap = created
        retryCount = 0

        // 保存 source 引用，teardown 时才能摘掉（见 teardown 的说明）
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source

        CGEvent.tapEnable(tap: created, enable: true)

        InputRegistry.shared.register(self)
        dbg("tap[\(name)] 已创建")
    }

    /// 权限还没生效时 tapCreate 会失败，隔一秒重试，最多 10 次。
    ///
    /// 启动早期（尤其登录后立刻启动）辅助功能授权可能尚未就绪，
    /// 不重试的话该功能会永久失效，用户只能重启应用。
    private func scheduleRetry() {
        guard retryCount < Self.maxRetries else {
            dbg("tap[\(name)] 创建失败，已达最大重试次数 \(Self.maxRetries)")
            return
        }
        retryCount += 1
        dbg("tap[\(name)] 创建失败，第 \(retryCount) 次重试")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
            guard let self, self.tap == nil else { return }
            self.createTap()
        }
    }

    private func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 被系统临时禁用（超时或用户输入触发）时重新启用，否则该 tap 永久失效
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            dbg("tap[\(name)] 被系统禁用（\(type == .tapDisabledByTimeout ? "超时" : "用户输入")），已重新启用")
            return Unmanaged.passUnretained(event)
        }

        // 配置窗口正在录制快捷键：放行所有按键。
        //
        // 这一句必须在所有 tap 里保持一致——之前 5 处各写一遍漏了一处，
        // 表现为「录制时某些键收不到」，且很难定位。现在收进封装，不可能漏。
        if HotkeyRecorder.isRecording {
            return Unmanaged.passUnretained(event)
        }

        guard let result = handler(type, event) else { return nil }
        return Unmanaged.passUnretained(result)
    }
}

// MARK: - 事件掩码便捷构造

extension CGEventMask {
    /// 用一组事件类型构造掩码
    static func make(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }
}
