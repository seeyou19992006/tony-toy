import Foundation
import Cocoa

/// 让鼠标滚轮与触摸板反向。
///
/// macOS 的「自然滚动」由窗口服务端在事件 tap 之后统一应用，且鼠标和触摸板共用一个
/// 全局开关，所以无法只改鼠标事件的 delta 来反转（进程内能看到修改，应用看不到）。
/// 业界通行做法是反过来的：
///   1. 把全局 com.apple.swipescrolldirection 关掉 → 鼠标变成传统方向
///   2. 在 tap 里反转触摸板（isContinuous = 1）的连续滚动 → 触摸板保持自然方向
final class ScrollInverter {
    private static let globalKey = "com.apple.swipescrolldirection" as CFString
    private static let savedOriginalKey = "scrollInverter.originalNaturalScroll"

    private var eventTap: CFMachPort?
    private var retryCount = 0
    private var enabled = false

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled { start() } else { stop() }
    }

    private func start() {
        disableTap()
        applyTraditionalScrolling()

        let mask = (1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let inverter = Unmanaged<ScrollInverter>.fromOpaque(refcon!).takeUnretainedValue()
                return inverter.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            retryCount += 1
            if retryCount <= 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self, self.enabled else { return }
                    self.start()
                }
            }
            return
        }
        retryCount = 0
        eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0),
                           .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        disableTap()
        restoreNaturalScrolling()
    }

    private func disableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // 全局已改为传统方向，这里只反转触摸板（连续滚动），让它保持自然
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard isContinuous else { return Unmanaged.passUnretained(event) }

        event.setIntegerValueField(.scrollWheelEventDeltaAxis1,
                                   value: -event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2,
                                   value: -event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1,
                                  value: -event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2,
                                  value: -event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1,
                                  value: -event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2,
                                  value: -event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))

        return Unmanaged.passUnretained(event)
    }

    // MARK: - 全局自然滚动

    private func applyTraditionalScrolling() {
        let defaults = UserDefaults.standard

        // 首次开启时记录原值；崩溃后重启也能还原
        if defaults.object(forKey: Self.savedOriginalKey) == nil {
            let original = currentGlobalValue() ?? true
            defaults.set(original, forKey: Self.savedOriginalKey)
        }

        guard currentGlobalValue() != false else { return }
        setGlobalValue(false)
    }

    private func restoreNaturalScrolling() {
        let defaults = UserDefaults.standard
        guard let original = defaults.object(forKey: Self.savedOriginalKey) as? Bool else { return }
        if currentGlobalValue() != original {
            setGlobalValue(original)
        }
        defaults.removeObject(forKey: Self.savedOriginalKey)
    }

    private func currentGlobalValue() -> Bool? {
        CFPreferencesCopyValue(Self.globalKey,
                               kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser,
                               kCFPreferencesAnyHost) as? Bool
    }

    private func setGlobalValue(_ value: Bool) {
        CFPreferencesSetValue(Self.globalKey,
                              value as CFBoolean,
                              kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                 kCFPreferencesCurrentUser,
                                 kCFPreferencesAnyHost)

        // 通知系统该偏好已变化，避免要重新登录才生效
        CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(),
                                             CFNotificationName("com.apple.swipescrolldirection" as CFString),
                                             nil, nil, true)
    }
}
