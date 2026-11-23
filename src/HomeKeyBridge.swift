import Foundation
import Cocoa
import IOKit
import IOKit.hid

/// 手柄 Home 键监听（Switch Pro / Stadia）。
///
/// 为什么不用 GameController：Home 键会被系统手势截走，后台进程拿不到
/// `pressedChangedHandler`。原始 HID 报告里这一位一直都在。
///
/// 报告格式（实测）：
///   Switch Pro  report 0x30，49 字节：[0]=reportID [1..2]=timer [3..5]=按钮组，Home 在 [4] bit4
///   Stadia      report 0x03，11 字节：[0]=reportID [1]=按钮组1 [2]=按钮组2，Home 在 [2] bit4
///
/// 三条必须遵守的约束（前两条都是踩过坑的）：
/// 1. **每台设备一块独立缓冲区**。共用一块时多手柄会互相覆盖。
/// 2. **每台设备独立的按键状态**。状态如果共享，两台手柄交替上报会让
///    "Home 是否按下"来回翻转，实测 0.6 秒内触发 4 次、每 200ms 一次，
///    表现为大屏自己反复开关。
/// 3. **偏移按设备查表，不能一套通吃**。Stadia 的 data[4] 是 0x79（摇杆中位），
///    拿 Switch 的 [4]bit4 去读会永远判成"按着"，所以未适配的型号直接跳过。
///
/// 某款手柄的 Home 键在原始 HID 报告里的确切位置。
///
/// 各家手柄的报告 ID、字节索引都不一样，不能共用一套偏移。
/// 下面这些值都是实测出来的（按一次键，看哪一位在 0x00 / 0x10 之间跳）：
///   - Switch Pro: report 0x30，data[4] 的 bit4
///   - Stadia:     report 0x03，data[2] 的 bit4
/// 巧合的是两者的值都是 0x10，但字节位置不同，套错就会误判。
struct HomeKeySpec {
    let reportID: UInt32
    let byteIndex: Int
    let bit: UInt8
    let label: String

    /// 按设备查表。返回 nil 表示这款手柄还没适配，此时不注册回调，
    /// 宁可不响应也不能拿错误偏移去猜——之前 Stadia 的 data[4]=0x79
    /// 被当成「一直按着 Home」，就是这么来的。
    static func resolve(vendorID: Int, productID: Int) -> HomeKeySpec? {
        // Nintendo（Pro Controller 的 Home 位在 0x30 报告里）
        if vendorID == 0x057e {
            return HomeKeySpec(reportID: 0x30, byteIndex: 4, bit: 4, label: "r0x30 b4.bit4")
        }
        // Google Stadia Controller
        if vendorID == 0x18d1, productID == 0x9400 {
            return HomeKeySpec(reportID: 0x03, byteIndex: 2, bit: 4, label: "r0x03 b2.bit4")
        }
        return nil
    }
}

/// 该通道不经过 TCC：辅助功能、输入监控都不需要授权。
final class HomeKeyBridge {
    static let shared = HomeKeyBridge()

    /// Home 按下沿回调（主线程）
    var onHomePressed: (() -> Void)?

    /// 每台设备一套上下文：独立缓冲区 + 独立按键状态
    private final class DeviceContext {
        let name: String
        let spec: HomeKeySpec
        let buffer: UnsafeMutablePointer<UInt8>
        var lastHomePressed = false
        var events = 0
        unowned let bridge: HomeKeyBridge

        init(name: String, spec: HomeKeySpec, bridge: HomeKeyBridge) {
            self.name = name
            self.spec = spec
            self.bridge = bridge
            buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: HomeKeyBridge.bufferSize)
            buffer.initialize(repeating: 0, count: HomeKeyBridge.bufferSize)
        }

        func handle(data: UnsafeMutablePointer<UInt8>) {
            let byte = data[spec.byteIndex]
            let pressed = ((byte >> spec.bit) & 1) == 1
            guard pressed != lastHomePressed else { return }
            lastHomePressed = pressed
            guard pressed else { return }
            events += 1
            dbg("手柄 Home 按下 ← \(name) [\(spec.label)] byte=0x\(String(byte, radix: 16))")
            bridge.emitHome()
        }
    }

    private let manager: IOHIDManager
    private static let bufferSize = 128

    private var contexts: [DeviceContext] = []
    private var enabled = true
    private(set) var isRunning = false

    private init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }

        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x05],
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x04],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager, HomeKeyBridge.deviceMatched,
            Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isRunning = result == kIOReturnSuccess
        NSLog("[TonyToy] 手柄 Home 监听\(isRunning ? "已启动" : "启动失败 code=\(result)")")
    }

    func stop() {
        guard isRunning else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isRunning = false
        contexts.removeAll()
    }

    /// 关闭后仍继续跟踪按键状态，只是不再回调，避免重新打开时误触发
    func setEnabled(_ value: Bool) {
        enabled = value
    }

    func emitHome() {
        guard enabled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onHomePressed?()
        }
    }

    // MARK: - 设备接入

    private static let deviceMatched: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let bridge = Unmanaged<HomeKeyBridge>.fromOpaque(context).takeUnretainedValue()
        bridge.attach(device)
    }

    private func attach(_ device: IOHIDDevice) {
        let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)
            ?? "未知手柄"
        let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0

        guard let spec = HomeKeySpec.resolve(vendorID: vendorID, productID: productID) else {
            NSLog(
                "[TonyToy] 手柄 \(name) vendor=0x\(String(vendorID, radix: 16)) product=0x\(String(productID, radix: 16)) 未适配 Home 位置，跳过"
            )
            return
        }

        let context = DeviceContext(name: name, spec: spec, bridge: self)
        contexts.append(context)

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceRegisterInputReportCallback(
            device,
            context.buffer,
            HomeKeyBridge.bufferSize,
            HomeKeyBridge.reportReceived,
            Unmanaged.passUnretained(context).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(
            device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        NSLog(
            "[TonyToy] 手柄接入 \(name) vendor=0x\(String(vendorID, radix: 16)) 解析=\(spec.label)：\(result == kIOReturnSuccess ? "成功" : "失败 code=\(result)")"
        )
    }

    // MARK: - 报告解析

    private static let reportReceived: IOHIDReportCallback = {
        context, _, _, _, reportID, data, length in
        guard let context else { return }
        let deviceContext = Unmanaged<DeviceContext>.fromOpaque(context).takeUnretainedValue()
        // 只认这台设备自己的 Home 报告，别的报告里同一个字节是别的东西
        guard reportID == deviceContext.spec.reportID,
            length > deviceContext.spec.byteIndex
        else { return }
        deviceContext.handle(data: data)
    }
}
