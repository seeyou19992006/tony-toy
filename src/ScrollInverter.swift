import Foundation
import Cocoa

/// 只反转鼠标滚轮方向，触摸板保持系统自然滚动。
/// 依靠 kCGScrollWheelEventIsContinuous 区分两者：触摸板为 1，鼠标滚轮为 0。
final class ScrollInverter {
    private var eventTap: CFMachPort?
    private var retryCount = 0
    private var enabled = false

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled { start() } else { stop() }
    }

    private func start() {
        stop()
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

        // 触摸板是连续滚动，保持系统方向不动
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !isContinuous else { return Unmanaged.passUnretained(event) }

        // 鼠标滚轮：三套增量都要取反，否则不同应用表现不一致
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
