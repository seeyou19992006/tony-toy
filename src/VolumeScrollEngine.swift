import Cocoa
import CoreAudio
import Foundation

/// 极简音量滚动引擎
/// 核心规则：滚轮每滚动一格，音量调整 n/64
final class VolumeScrollEngine {

    // MARK: - 配置

    /// 每格滚动调整的音量步进（以 1/64 为单位）
    /// 例如：step = 1 表示每格 1/64；step = 2 表示每格 2/64 = 1/32
    var step: Int = 1

    /// 触发 HUD 显示的最小间隔（秒）
    var hudInterval: TimeInterval = 0.033

    /// 加速度系数重置时间（无事件后多久重置，秒）
    var accelerationResetInterval: TimeInterval = 0.1

    // MARK: - 内部状态

    /// 当前音量值（以 1/64 为单位，范围 0-64）
    private var currentVolume: Int = 32

    /// 默认输出设备 ID
    private var deviceID: AudioObjectID = 0

    /// 累积的滚动值（用于处理高精度滚轮）
    private var accumulatedScroll: Double = 0.0

    /// 上次显示 HUD 的时间
    private var lastHudTime: Date = .distantPast

    /// 上次滚动事件的时间
    private var lastScrollTime: Date = .distantPast

    /// 连续滚动计数（用于计算加速度系数）
    private var consecutiveScrollCount: Int = 0

    /// 上一次滚动的方向（用于检测方向切换）
    private var lastScrollDirection: Int = 0

    /// 加速度系数（连续滚动时增加）
    private var accelerationFactor: Double = 1.0

    /// 上次滚动时间（用于检测连续滚动）
    private var lastScrollTimestamp: Date = .distantPast

    /// 连续滚动重置间隔（100ms）
    private let scrollResetInterval: TimeInterval = 0.1

    /// 加速度增长系数（0.6）
    private let accelerationIncrement: Double = 0.6

    /// 音量变化回调
    var onVolumeChanged: ((Float32) -> Void)?

    // MARK: - 初始化

    init() {
        refreshDevice()
        currentVolume = getVolume()
    }

    // MARK: - 公共方法

    /// 启动引擎（初始化音量状态）
    func start() {
        refreshDevice()
        currentVolume = getVolume()
        accumulatedScroll = 0.0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onVolumeChanged?(Float32(self.currentVolume) / 64.0)
        }
    }

    func stop() {
        // 无需清理
    }

    func beginInteraction() {
        refreshDevice()
        accumulatedScroll = 0.0
    }

    func endInteraction() {
        // 无需处理
    }

    /// 处理滚轮滚动
    /// - Parameter delta: 滚动方向和格数（正=增加，负=减少），忽略具体数值，每次事件算一格
    func handleScroll(delta: Double) {
        let now = Date()

        // 只看方向，不看数值，每次事件算一格
        let direction = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
        guard direction != 0 else { return }

        // 检查是否需要重置连续滚动计数
        let timeSinceLastScroll = now.timeIntervalSince(lastScrollTime)
        let shouldReset =
            timeSinceLastScroll > accelerationResetInterval  // 超过100ms无事件
            || direction != lastScrollDirection  // 或方向切换

        if shouldReset {
            consecutiveScrollCount = 0
        }

        // 增加连续滚动计数
        consecutiveScrollCount += 1
        lastScrollTime = now
        lastScrollDirection = direction

        // 计算加速度系数: count * accelerationIncrement + 1
        let accelerationFactor = Double(consecutiveScrollCount) * accelerationIncrement + 1.0

        // 计算实际移动的格数（考虑加速度）
        let actualTicks = Int(Double(direction) * accelerationFactor)

        // 计算新音量
        let newVolume = currentVolume + (actualTicks * step)

        // 限制在 0-64 范围
        let clamped = max(0, min(64, newVolume))

        // 如果触及边界且尝试继续向边界滚动，重置加速度
        if (currentVolume == 64 && direction > 0) || (currentVolume == 0 && direction < 0) {
            consecutiveScrollCount = 0
        }

        // 如果音量变化了，应用它
        if clamped != currentVolume {
            // 确定方向（用于HUD）
            let volumeDirection = clamped > currentVolume ? 1 : -1

            // 应用音量
            setVolume(steps: clamped)
            currentVolume = clamped

            // 触发系统 HUD 显示
            if now.timeIntervalSince(lastHudTime) >= hudInterval {
                postFineVolumeKey(increase: volumeDirection > 0)
                lastHudTime = now
            }

            // 通知外部
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onVolumeChanged?(Float32(self.currentVolume) / 64.0)
            }
        }
    }

    /// 获取当前音量百分比 (0.0-1.0)
    func getCurrentVolume() -> Float32 {
        return Float32(currentVolume) / 64.0
    }

    /// 设置步进值
    func setStep(_ newStep: Int) {
        step = max(1, newStep)
    }

    // MARK: - 私有方法

    /// 刷新默认音频设备
    private func refreshDevice() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &id
        )

        if err == noErr {
            deviceID = id
        }
    }

    /// 获取当前音量 (0-64)
    private func getVolume() -> Int {
        guard deviceID != 0 else { return 32 }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var vol: Float32 = 0.0
        var size = UInt32(MemoryLayout<Float32>.size)

        let err = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)

        if err == noErr {
            return Int(vol * 64.0)
        }

        return 32  // 默认值
    }

    /// 设置音量 (0-64)
    private func setVolume(steps: Int) {
        guard deviceID != 0 else { return }

        let vol = Float32(steps) / 64.0

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var value = vol
        _ = AudioObjectSetPropertyData(
            deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value
        )
    }

    /// 触发系统音量 HUD 显示
    private func postFineVolumeKey(increase: Bool) {
        let keyType: Int32 = increase ? 0 : 1
        let flags = NSEvent.ModifierFlags(rawValue: 0xA0000)
        let dataDown = Int((keyType << 16) | (0xA << 8))
        let dataUp = Int((keyType << 16) | (0xB << 8))

        func post(_ data: Int) {
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }

        post(dataDown)
        post(dataUp)
    }
}
