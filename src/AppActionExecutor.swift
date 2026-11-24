import Cocoa
import Foundation

struct KeyboardShortcutEvent {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let keyDown: Bool
}

enum AppActionDispatchPhase {
    case instant
    case keyDown
    case keyUp
}

struct TrackedApplication: Equatable {
    let bundleIdentifier: String
    let runningApplication: NSRunningApplication?

    init(bundleIdentifier: String, runningApplication: NSRunningApplication? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.runningApplication = runningApplication
    }
}

enum ActivateApplicationDecision: Equatable {
    case activate(bundleIdentifier: String)
    case switchToPrevious(TrackedApplication)
}

enum WindowFrameUpdateStep: Equatable {
    case position
    case size
}

final class AppActionExecutor {
    private var activationObserver: NSObjectProtocol?
    private var currentFrontmost: TrackedApplication?
    private var previousFrontmost: TrackedApplication?
    private var windowRestoreCache: [WindowRestoreKey: [String: CGRect]] = [:]
    private var windowLastAutoFrames: [WindowRestoreKey: [String: [CGRect]]] = [:]
    private var pendingWindowFrames: [WindowRestoreKey: (displayID: String, frame: CGRect, generation: UInt64)] = [:]
    private var windowMoveGeneration: UInt64 = 0

    init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        if let app = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = app.bundleIdentifier
        {
            currentFrontmost = TrackedApplication(
                bundleIdentifier: bundleIdentifier, runningApplication: app)
        }

        activationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleActivatedApplicationNotification(notification)
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func dispatch(_ action: AppAction, phase: AppActionDispatchPhase = .instant) {
        switch action {
        case .sendHotkey(let keyCode, let modifiers):
            dispatchShortcut(keyCode: keyCode, modifiers: modifiers, phase: phase)
        case .missionControl:
            guard phase != .keyUp else { return }
            performUIAction { [self] in
                openMissionControl()
            }
        case .activateApplication:
            guard phase != .keyUp else { return }
            performUIAction { [self] in
                dispatchActivateApplication(action)
            }
        case .moveWindowToAdjacentDisplay(let direction):
            guard phase != .keyUp else { return }
            performUIAction { [self] in
                moveFrontmostWindowToAdjacentDisplay(direction: direction)
            }
        case .maximizeWindow:
            guard phase != .keyUp else { return }
            performUIAction { [self] in
                maximizeFrontmostWindow()
            }
        case .ensureApplicationRunning(let bundleIdentifier):
            guard phase != .keyUp else { return }
            performUIAction { [self] in
                ensureApplicationRunning(bundleIdentifier: bundleIdentifier)
            }
        }
    }

    // MARK: - 目标应用保活

    /// 刚拉起后的抑制窗口：拉起那一刻用户往往还按着手柄键，按键沿会连续
    /// 冒出来，短时间内重复拉起没有意义。
    private var suppressLaunchUntil: [String: Date] = [:]
    private static let launchSuppression: TimeInterval = 1.5

    /// 只做一件事：目标应用不在运行就拉起来。
    /// 在跑的时候完全不动手 —— Home 键由目标应用自己监听处理，
    /// 这里再投一次通知就会变成双触发。
    private func ensureApplicationRunning(bundleIdentifier: String) {
        let now = Date()

        if let until = suppressLaunchUntil[bundleIdentifier], now < until {
            dbg("拉起 \(bundleIdentifier) 忽略：抑制窗口内")
            return
        }

        let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { !$0.isTerminated }

        if running != nil {
            dbg("\(bundleIdentifier) 已在运行，交给它自己处理")
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            dbg("拉起失败：找不到 \(bundleIdentifier)")
            return
        }

        suppressLaunchUntil[bundleIdentifier] = now.addingTimeInterval(Self.launchSuppression)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // 目标应用刚起来是隐藏态，直接要求展开面板
        configuration.arguments = ["--show-deck"]
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                dbg("拉起 \(bundleIdentifier) 失败：\(error.localizedDescription)")
            } else {
                dbg("已拉起 \(bundleIdentifier)")
            }
        }
    }

    static func activationDecision(
        for action: AppAction,
        currentFrontmost: TrackedApplication?,
        previousFrontmost: TrackedApplication?
    ) -> ActivateApplicationDecision? {
        guard case .activateApplication(let bundleIdentifier, let behavior) = action else {
            return nil
        }

        if behavior == .switchToLast,
            currentFrontmost?.bundleIdentifier == bundleIdentifier,
            let previousFrontmost,
            previousFrontmost.bundleIdentifier != bundleIdentifier
        {
            return .switchToPrevious(previousFrontmost)
        }

        return .activate(bundleIdentifier: bundleIdentifier)
    }

    static func windowMoveLogLine(
        direction: DisplayDirection,
        sourceDisplayID: String,
        targetDisplayID: String,
        sourceVisibleFrame: CGRect,
        targetVisibleFrame: CGRect,
        originalFrame: CGRect,
        projectedFrame: CGRect,
        cachedTargetFrame: CGRect?,
        resolvedTargetFrame: CGRect,
        wroteRestoreCache: Bool
    ) -> String {
        let cachedDescription = cachedTargetFrame.map(NSStringFromRect) ?? "<none>"
        return
            "Window move plan: direction=\(direction.rawValue) sourceDisplay=\(sourceDisplayID) targetDisplay=\(targetDisplayID) sourceVisible=\(NSStringFromRect(sourceVisibleFrame)) targetVisible=\(NSStringFromRect(targetVisibleFrame)) original=\(NSStringFromRect(originalFrame)) projected=\(NSStringFromRect(projectedFrame)) cachedTarget=\(cachedDescription) resolved=\(NSStringFromRect(resolvedTargetFrame)) cacheWrite=\(wroteRestoreCache).\n"
    }

    static func windowMoveResultLogLine(requestedFrame: CGRect, appliedFrame: CGRect?) -> String {
        let appliedDescription = appliedFrame.map(NSStringFromRect) ?? "<unavailable>"
        return
            "Window move result: requested=\(NSStringFromRect(requestedFrame)) applied=\(appliedDescription).\n"
    }

    static func windowFrameUpdatePlan(currentFrame: CGRect, targetFrame: CGRect)
        -> [WindowFrameUpdateStep]
    {
        let expandsOnCurrentDisplay =
            targetFrame.width > currentFrame.width || targetFrame.height > currentFrame.height
        // 缩小时先改大小再移动，但跨屏后系统或应用（DPI/缩放切换）可能重设尺寸，
        // 需要在到达目标屏后再补一次 size + position 兜底。
        return expandsOnCurrentDisplay
            ? [.position, .size, .position]
            : [.size, .position, .size, .position]
    }

    static func windowFramePositionStepFrame(currentFrame: CGRect, targetFrame: CGRect) -> CGRect {
        let expandsOnCurrentDisplay =
            targetFrame.width > currentFrame.width || targetFrame.height > currentFrame.height
        guard expandsOnCurrentDisplay else {
            return targetFrame
        }
        // AX 坐标以左上角为原点并向下扩展；若用 AppKit 左下角对齐，放大高度时会顶到屏幕底边被截断。
        // 这里保持顶部（AppKit maxY）对齐目标顶部，让后续 size 向下安全展开。
        return CGRect(
            x: targetFrame.minX,
            y: targetFrame.maxY - currentFrame.height,
            width: currentFrame.width,
            height: currentFrame.height
        )
    }

    func dispatchShortcut(
        keyCode: CGKeyCode, modifiers: CGEventFlags, phase: AppActionDispatchPhase
    ) {
        let source = CGEventSource(stateID: .privateState)
        switch phase {
        case .instant:
            for step in Self.shortcutEventPlan(keyCode: keyCode, modifiers: modifiers) {
                let event = CGEvent(
                    keyboardEventSource: source, virtualKey: step.keyCode, keyDown: step.keyDown)
                event?.flags = step.flags
                event?.post(tap: .cghidEventTap)
            }
        case .keyDown:
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            event?.flags = modifiers
            event?.post(tap: .cghidEventTap)
        case .keyUp:
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            event?.flags = modifiers
            event?.post(tap: .cghidEventTap)
        }
    }

    static func shortcutEventPlan(keyCode: CGKeyCode, modifiers: CGEventFlags)
        -> [KeyboardShortcutEvent]
    {
        let orderedModifierFlags: [CGEventFlags] = [
            .maskControl, .maskAlternate, .maskShift, .maskCommand,
        ]
        let activeModifiers = orderedModifierFlags.filter { modifiers.contains($0) }
        let modifierDownEvents = activeModifiers.compactMap { flag -> KeyboardShortcutEvent? in
            guard let keyCode = KeyConfigSupport.modifierKeyCode(for: flag) else {
                return nil
            }
            let cumulativeFlags =
                activeModifiers
                .prefix(while: { $0 != flag })
                .reduce(into: flag) { result, previousFlag in
                    result.insert(previousFlag)
                }
            return KeyboardShortcutEvent(keyCode: keyCode, flags: cumulativeFlags, keyDown: true)
        }

        let targetDown = KeyboardShortcutEvent(keyCode: keyCode, flags: modifiers, keyDown: true)
        let targetUp = KeyboardShortcutEvent(keyCode: keyCode, flags: modifiers, keyDown: false)

        let modifierUpEvents = activeModifiers.reversed().compactMap {
            flag -> KeyboardShortcutEvent? in
            guard let keyCode = KeyConfigSupport.modifierKeyCode(for: flag) else {
                return nil
            }
            let remainingFlags =
                activeModifiers
                .filter { $0 != flag }
                .reduce(into: CGEventFlags()) { result, remainingFlag in
                    result.insert(remainingFlag)
                }
            return KeyboardShortcutEvent(keyCode: keyCode, flags: remainingFlags, keyDown: false)
        }

        return modifierDownEvents + [targetDown, targetUp] + modifierUpEvents
    }

    private func openMissionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.open(url)
    }

    private func dispatchActivateApplication(_ action: AppAction) {
        guard
            let decision = Self.activationDecision(
                for: action,
                currentFrontmost: currentFrontmost,
                previousFrontmost: previousFrontmost
            )
        else {
            return
        }

        switch decision {
        case .activate(let bundleIdentifier):
            activateApplication(bundleIdentifier: bundleIdentifier)
        case .switchToPrevious(let application):
            if let runningApplication = application.runningApplication,
                !runningApplication.isTerminated
            {
                DispatchQueue.main.async {
                    runningApplication.activate(options: [])
                }
                return
            }
            activateApplication(bundleIdentifier: application.bundleIdentifier)
        }
    }

    private func activateApplication(bundleIdentifier: String) {
        guard
            let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier)
        else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    private func moveFrontmostWindowToAdjacentDisplay(direction: DisplayDirection) {
        guard ensureAccessibilityTrusted(for: "move windows across displays") else {
            return
        }
        guard let focusedWindow = focusedWindowContext() else {
            fputs("Window move skipped: no focused window context available.\n", stderr)
            return
        }
        let displays = currentDisplayLayouts()
        guard
            let sourceDisplay = WindowMovementPlanner.displayContaining(
                frame: focusedWindow.frame, displays: displays)
        else {
            fputs(
                "Window move skipped: unable to determine source display for frame \(NSStringFromRect(focusedWindow.frame)).\n",
                stderr)
            return
        }
        guard
            let targetDisplay = WindowMovementPlanner.adjacentDisplay(
                from: sourceDisplay,
                direction: direction,
                displays: displays
            )
        else {
            fputs(
                "Window move skipped: no adjacent display found in direction \(direction.rawValue) from display \(sourceDisplay.id).\n",
                stderr)
            return
        }

        let sourceLastAutoFrames = windowLastAutoFrames[focusedWindow.restoreKey]?[sourceDisplay.id] ?? []
        let shouldUseCachedTargetFrame = WindowMovementPlanner.shouldUseRestoredFrame(
            currentFrame: focusedWindow.frame,
            lastAutoFramesOnSourceDisplay: sourceLastAutoFrames
        )
        // 若上一跳在源屏的 50ms 补设还没来得及执行就被快速连按打断，只要窗口没被手动改过，
        // 就沿用上一跳的预期目标帧（而非尚未放大到位的物理帧）来计算下一跳。
        let pendingSourceFrame: CGRect? = {
            guard shouldUseCachedTargetFrame,
                  let pending = pendingWindowFrames[focusedWindow.restoreKey],
                  pending.displayID == sourceDisplay.id else {
                return nil
            }
            return pending.frame
        }()
        pendingWindowFrames.removeValue(forKey: focusedWindow.restoreKey)
        let effectiveSourceFrame = pendingSourceFrame ?? focusedWindow.frame

        let projectedFrame = WindowMovementPlanner.project(
            frame: effectiveSourceFrame, from: sourceDisplay, to: targetDisplay)
        let shouldWriteRestoreCache = WindowMovementPlanner.shouldCacheForReturn(
            originalFrame: effectiveSourceFrame,
            projectedFrame: projectedFrame,
            from: sourceDisplay,
            to: targetDisplay
        )
        if shouldWriteRestoreCache {
            var restoreFrames = windowRestoreCache[focusedWindow.restoreKey] ?? [:]
            restoreFrames[sourceDisplay.id] = effectiveSourceFrame
            windowRestoreCache[focusedWindow.restoreKey] = restoreFrames
        }

        let (cachedTargetFrame, updatedCache) = WindowMovementPlanner.consumeRestoredFrame(
            for: focusedWindow.restoreKey,
            targetDisplayID: targetDisplay.id,
            cache: windowRestoreCache
        )
        windowRestoreCache = updatedCache
        let effectiveCachedTargetFrame = shouldUseCachedTargetFrame ? cachedTargetFrame : nil
        let targetFrame = WindowMovementPlanner.resolveTargetFrame(
            frame: effectiveSourceFrame,
            from: sourceDisplay,
            to: targetDisplay,
            cachedTargetFrame: effectiveCachedTargetFrame
        )
        let planLog = Self.windowMoveLogLine(
            direction: direction,
            sourceDisplayID: sourceDisplay.id,
            targetDisplayID: targetDisplay.id,
            sourceVisibleFrame: sourceDisplay.visibleFrame,
            targetVisibleFrame: targetDisplay.visibleFrame,
            originalFrame: focusedWindow.frame,
            projectedFrame: projectedFrame,
            cachedTargetFrame: effectiveCachedTargetFrame,
            resolvedTargetFrame: targetFrame,
            wroteRestoreCache: shouldWriteRestoreCache
        )
        fputs(planLog, stderr)
        dbg(planLog.trimmingCharacters(in: .newlines))

        windowMoveGeneration &+= 1
        let moveGeneration = windowMoveGeneration

        if !setWindowFrame(focusedWindow.element, frame: targetFrame) {
            fputs(
                "Window move failed: AX rejected frame update to \(NSStringFromRect(targetFrame)).\n",
                stderr)
            dbg("Window move failed: AX rejected frame update to \(NSStringFromRect(targetFrame))")
            return
        }
        let appliedFrame = windowFrame(of: focusedWindow.element)
        var autoFrames = windowLastAutoFrames[focusedWindow.restoreKey] ?? [:]
        var recordedFrames = [targetFrame]
        if let appliedFrame {
            recordedFrames.append(appliedFrame)
        }
        autoFrames[targetDisplay.id] = recordedFrames
        windowLastAutoFrames[focusedWindow.restoreKey] = autoFrames
        let resultLog = Self.windowMoveResultLogLine(
            requestedFrame: targetFrame, appliedFrame: appliedFrame)
        fputs(resultLog, stderr)
        dbg(resultLog.trimmingCharacters(in: .newlines))

        // 跨屏放大时，部分应用（如 Chrome）在刚切换屏幕的瞬间仍按旧屏幕约束高度；
        // 若首次设帧后尺寸/位置尚未到位，50ms 后补设一次确保在目标屏生效。
        let needsFollowUp = appliedFrame.map {
            abs($0.minX - targetFrame.minX) > 2 ||
                abs($0.minY - targetFrame.minY) > 2 ||
                abs($0.width - targetFrame.width) > 2 ||
                abs($0.height - targetFrame.height) > 2
        } ?? false
        if needsFollowUp {
            let element = focusedWindow.element
            let restoreKey = focusedWindow.restoreKey
            let targetDisplayID = targetDisplay.id
            pendingWindowFrames[restoreKey] = (
                displayID: targetDisplayID, frame: targetFrame, generation: moveGeneration
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.windowMoveGeneration == moveGeneration else { return }
                if self.pendingWindowFrames[restoreKey]?.generation == moveGeneration {
                    self.pendingWindowFrames.removeValue(forKey: restoreKey)
                }
                _ = self.setWindowFrame(element, frame: targetFrame)
                let settledFrame = self.windowFrame(of: element)
                var updatedAutoFrames = self.windowLastAutoFrames[restoreKey] ?? [:]
                var frames = [targetFrame]
                if let settledFrame {
                    frames.append(settledFrame)
                }
                updatedAutoFrames[targetDisplayID] = frames
                self.windowLastAutoFrames[restoreKey] = updatedAutoFrames
                dbg("Window move follow-up: requested=\(NSStringFromRect(targetFrame)) applied=\(settledFrame.map(NSStringFromRect) ?? "<unavailable>")")
            }
        }
    }

    private func maximizeFrontmostWindow() {
        guard ensureAccessibilityTrusted(for: "resize windows") else {
            return
        }
        guard let windowElement = focusedWindowElement() else {
            fputs("Window maximize skipped: focused window unavailable.\n", stderr)
            return
        }
        let targetVisibleFrame: CGRect?
        if let currentFrame = windowFrame(of: windowElement),
           let display = WindowMovementPlanner.displayContaining(
               frame: currentFrame, displays: currentDisplayLayouts()) {
            targetVisibleFrame = display.visibleFrame
        } else {
            targetVisibleFrame = NSScreen.main?.visibleFrame
        }
        guard let visibleFrame = targetVisibleFrame else {
            fputs("Window maximize skipped: target screen unavailable.\n", stderr)
            return
        }

        if !setWindowFrame(windowElement, frame: visibleFrame) {
            fputs(
                "Window maximize failed: AX rejected frame update to \(NSStringFromRect(visibleFrame)).\n",
                stderr)
        }
    }

    private func performUIAction(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func ensureAccessibilityTrusted(for action: String) -> Bool {
        guard AXIsProcessTrusted() else {
            fputs("Accessibility permission is required to \(action).\n", stderr)
            return false
        }
        return true
    }

    private func focusedWindowElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            fputs("AX lookup skipped: no frontmost application.\n", stderr)
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowRef: CFTypeRef?
        let focusedWindowError = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )
        guard focusedWindowError == .success,
            let focusedWindowRef,
            CFGetTypeID(focusedWindowRef) == AXUIElementGetTypeID()
        else {
            fputs(
                "AX lookup failed: focused window error \(focusedWindowError.rawValue) for \(app.bundleIdentifier ?? "<unknown>").\n",
                stderr)
            return nil
        }
        return unsafeBitCast(focusedWindowRef, to: AXUIElement.self)
    }

    private func focusedWindowContext() -> (
        element: AXUIElement, frame: CGRect, restoreKey: WindowRestoreKey
    )? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = app.bundleIdentifier,
            let windowElement = focusedWindowElement(),
            let frame = windowFrame(of: windowElement)
        else {
            return nil
        }

        let title = windowTitle(of: windowElement) ?? ""
        let restoreKey = restoreKey(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: app.processIdentifier,
            title: title,
            frame: frame
        )
        return (windowElement, frame, restoreKey)
    }

    private func windowPosition(of windowElement: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        let positionError = AXUIElementCopyAttributeValue(
            windowElement,
            kAXPositionAttribute as CFString,
            &positionRef
        )
        guard positionError == .success,
            let positionRef,
            CFGetTypeID(positionRef) == AXValueGetTypeID()
        else {
            fputs("AX lookup failed: position error \(positionError.rawValue).\n", stderr)
            return nil
        }

        let positionValue = unsafeBitCast(positionRef, to: AXValue.self)
        guard AXValueGetType(positionValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func windowSize(of windowElement: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        let sizeError = AXUIElementCopyAttributeValue(
            windowElement,
            kAXSizeAttribute as CFString,
            &sizeRef
        )
        guard sizeError == .success,
            let sizeRef,
            CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else {
            fputs("AX lookup failed: size error \(sizeError.rawValue).\n", stderr)
            return nil
        }

        let sizeValue = unsafeBitCast(sizeRef, to: AXValue.self)
        guard AXValueGetType(sizeValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func windowFrame(of windowElement: AXUIElement) -> CGRect? {
        guard let axOrigin = windowPosition(of: windowElement),
            let size = windowSize(of: windowElement),
            let converter = screenCoordinateConverter()
        else {
            return nil
        }
        let axFrame = CGRect(origin: axOrigin, size: size)
        return converter.appKitFrame(fromAXFrame: axFrame)
    }

    private func windowTitle(of windowElement: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let titleError = AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleRef
        )
        guard titleError == .success,
            let titleRef
        else {
            return nil
        }
        return titleRef as? String
    }

    @discardableResult
    private func setWindowAXPosition(_ windowElement: AXUIElement, point: CGPoint) -> Bool {
        var mutablePoint = point
        guard let newPosition = AXValueCreate(.cgPoint, &mutablePoint) else {
            fputs("AX update failed: unable to create position value.\n", stderr)
            return false
        }
        let error = AXUIElementSetAttributeValue(
            windowElement, kAXPositionAttribute as CFString, newPosition)
        if error != .success {
            fputs("AX update failed: position error \(error.rawValue).\n", stderr)
            dbg("AX update failed: position error \(error.rawValue) point=\(NSStringFromPoint(point))")
            return false
        }
        return true
    }

    @discardableResult
    private func setWindowSize(_ windowElement: AXUIElement, size: CGSize) -> Bool {
        var mutableSize = size
        guard let newSize = AXValueCreate(.cgSize, &mutableSize) else {
            fputs("AX update failed: unable to create size value.\n", stderr)
            return false
        }
        let error = AXUIElementSetAttributeValue(
            windowElement, kAXSizeAttribute as CFString, newSize)
        if error != .success {
            fputs("AX update failed: size error \(error.rawValue).\n", stderr)
            dbg("AX update failed: size error \(error.rawValue) size=\(NSStringFromSize(size))")
            return false
        }
        return true
    }

    @discardableResult
    private func setWindowFrame(_ windowElement: AXUIElement, frame: CGRect) -> Bool {
        guard let converter = screenCoordinateConverter() else {
            fputs("AX update failed: unable to determine screen coordinate converter.\n", stderr)
            return false
        }

        // Chrome/Electron 开启 AXEnhancedUserInterface 时会对 AXPosition/AXSize 做动画或丢弃跨屏尺寸更新，
        // 设帧前临时关闭、结束后恢复，确保尺寸与位置同步生效。
        var pid: pid_t = 0
        let appElement: AXUIElement? =
            AXUIElementGetPid(windowElement, &pid) == .success
            ? AXUIElementCreateApplication(pid)
            : nil
        let enhancedAttr = "AXEnhancedUserInterface" as CFString
        var enhancedRef: CFTypeRef?
        let hadEnhancedUI: Bool = {
            guard let appElement,
                  AXUIElementCopyAttributeValue(appElement, enhancedAttr, &enhancedRef) == .success,
                  let enabled = enhancedRef as? Bool
            else {
                return false
            }
            return enabled
        }()
        if hadEnhancedUI, let appElement {
            AXUIElementSetAttributeValue(appElement, enhancedAttr, kCFBooleanFalse)
        }
        defer {
            if hadEnhancedUI, let appElement {
                AXUIElementSetAttributeValue(appElement, enhancedAttr, kCFBooleanTrue)
            }
        }

        let currentFrame = windowFrame(of: windowElement) ?? frame
        let updatePlan = Self.windowFrameUpdatePlan(currentFrame: currentFrame, targetFrame: frame)
        let positionStepFrame = Self.windowFramePositionStepFrame(
            currentFrame: currentFrame, targetFrame: frame)
        let positionAXOrigin = converter.axFrame(fromAppKitFrame: positionStepFrame).origin
        let finalAXOrigin = converter.axFrame(fromAppKitFrame: frame).origin
        for (index, step) in updatePlan.enumerated() {
            switch step {
            case .position:
                let axOrigin = index == updatePlan.count - 1 ? finalAXOrigin : positionAXOrigin
                guard setWindowAXPosition(windowElement, point: axOrigin) else {
                    return false
                }
            case .size:
                guard setWindowSize(windowElement, size: frame.size) else {
                    return false
                }
            }
        }
        return true
    }

    private func screenCoordinateConverter() -> ScreenCoordinateConverter? {
        ScreenCoordinateConverter.current(screens: NSScreen.screens)
    }

    private func restoreKey(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        title: String,
        frame: CGRect
    ) -> WindowRestoreKey {
        if let windowNumber = WindowIdentityResolver.bestWindowNumber(
            processIdentifier: processIdentifier,
            title: title,
            frame: frame,
            entries: WindowIdentityResolver.entriesFromSystemWindowList()
        ) {
            return WindowRestoreKey(windowID: "cg-window:\(windowNumber)")
        }

        return WindowRestoreKey(windowID: "\(bundleIdentifier):\(processIdentifier):\(title)")
    }

    private func currentDisplayLayouts() -> [DisplayLayout] {
        NSScreen.screens.map { screen in
            let screenNumber =
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .stringValue ?? UUID().uuidString
            return DisplayLayout(
                id: screenNumber, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    private func handleActivatedApplicationNotification(_ notification: Notification) {
        guard
            let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            let bundleIdentifier = runningApplication.bundleIdentifier
        else {
            return
        }

        let next = TrackedApplication(
            bundleIdentifier: bundleIdentifier, runningApplication: runningApplication)
        if currentFrontmost?.bundleIdentifier != next.bundleIdentifier {
            previousFrontmost = currentFrontmost
        }
        currentFrontmost = next
    }
}
