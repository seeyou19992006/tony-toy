import Foundation
import Cocoa

/// 只反转触摸板滚动方向，鼠标滚轮不动。
///
/// 用法：系统设置里关闭「自然滚动」（鼠标变成传统方向），再打开这个开关，
/// 触摸板被反转回来，于是鼠标传统、触摸板自然。
/// 依靠 kCGScrollWheelEventIsContinuous 区分两者：触摸板为 1，鼠标滚轮为 0。
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

        let mask = (1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
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

        // 只反转触摸板（连续滚动）；鼠标滚轮保持系统方向
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

}
