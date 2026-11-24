import Foundation
import CoreGraphics

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message)\n  actual:   \(actual)\n  expected: \(expected)\n", stderr)
        exit(1)
    }
}

private func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private let bigScreen1 = DisplayLayout(
    id: "S1",
    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415)
)

private let bigScreen2 = DisplayLayout(
    id: "S2",
    frame: CGRect(x: 2560, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 2560, y: 0, width: 2560, height: 1415)
)

private let smallScreen = DisplayLayout(
    id: "s",
    frame: CGRect(x: 5120, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 5120, y: 0, width: 1512, height: 944)
)

private func testMaximizedRoundTripBigToSmallToBig() {
    let key = WindowRestoreKey(windowID: "win-1")
    var cache: [WindowRestoreKey: [String: CGRect]] = [:]

    // S1 (最大化) -> s
    let onBig = bigScreen1.visibleFrame
    let projectedToSmall = WindowMovementPlanner.project(frame: onBig, from: bigScreen1, to: smallScreen)
    assertEqual(projectedToSmall, smallScreen.visibleFrame, "最大化窗口移到小屏应继续最大化")
    assertTrue(
        WindowMovementPlanner.shouldCacheForReturn(
            originalFrame: onBig, projectedFrame: projectedToSmall, from: bigScreen1, to: smallScreen),
        "最大化窗口从大屏移到小屏应缓存原帧"
    )
    cache[key] = [bigScreen1.id: onBig]

    // s (最大化) -> S1
    let (cached, updated) = WindowMovementPlanner.consumeRestoredFrame(
        for: key, targetDisplayID: bigScreen1.id, cache: cache)
    cache = updated
    let resolvedBack = WindowMovementPlanner.resolveTargetFrame(
        frame: smallScreen.visibleFrame, from: smallScreen, to: bigScreen1, cachedTargetFrame: cached)
    assertEqual(resolvedBack, bigScreen1.visibleFrame, "最大化窗口从小屏移回大屏应恢复最大化")

    // s (最大化) -> S2 (无缓存，也应最大化)
    let projectedToS2 = WindowMovementPlanner.project(
        frame: smallScreen.visibleFrame, from: smallScreen, to: bigScreen2)
    assertEqual(projectedToS2, bigScreen2.visibleFrame, "最大化窗口从小屏移到另一个大屏也应最大化")

    print("testMaximizedRoundTripBigToSmallToBig passed")
}

private func testNonMaximizedSizeAndPositionClampedRoundTrip() {
    let key = WindowRestoreKey(windowID: "win-2")
    var cache: [WindowRestoreKey: [String: CGRect]] = [:]

    // 高度超出小屏、且 X 靠右边界的非最大化窗口
    let original = CGRect(x: 1600, y: 100, width: 800, height: 1200)
    let projected = WindowMovementPlanner.project(frame: original, from: bigScreen1, to: smallScreen)

    assertTrue(projected.width <= smallScreen.visibleFrame.width, "宽度不能超出小屏")
    assertTrue(projected.height <= smallScreen.visibleFrame.height, "高度不能超出小屏")
    assertTrue(projected.minX >= smallScreen.visibleFrame.minX, "左边界不能超出小屏")
    assertTrue(projected.maxX <= smallScreen.visibleFrame.maxX, "右边界不能超出小屏")
    assertTrue(projected.minY >= smallScreen.visibleFrame.minY, "下边界不能超出小屏")
    assertTrue(projected.maxY <= smallScreen.visibleFrame.maxY, "上边界不能超出小屏")

    assertTrue(
        WindowMovementPlanner.shouldCacheForReturn(
            originalFrame: original, projectedFrame: projected, from: bigScreen1, to: smallScreen),
        "被夹紧的非最大化窗口应缓存原位置和大小"
    )
    cache[key] = [bigScreen1.id: original]

    let (cached, _) = WindowMovementPlanner.consumeRestoredFrame(
        for: key, targetDisplayID: bigScreen1.id, cache: cache)
    let restored = WindowMovementPlanner.resolveTargetFrame(
        frame: projected, from: smallScreen, to: bigScreen1, cachedTargetFrame: cached)
    assertEqual(restored, original, "非最大化窗口移回大屏应恢复原始位置和大小")

    print("testNonMaximizedSizeAndPositionClampedRoundTrip passed")
}

private func testNonMaximizedPositionOnlyClampedRoundTrip() {
    // 宽高都小于小屏，但 X 靠大屏右侧，移到小屏时 X 会被夹紧
    let original = CGRect(x: 2000, y: 200, width: 500, height: 500)
    let projected = WindowMovementPlanner.project(frame: original, from: bigScreen1, to: smallScreen)
    assertEqual(projected.size, original.size, "宽高未超限时应保持原始大小")
    assertTrue(projected.maxX <= smallScreen.visibleFrame.maxX, "位置应被夹紧在小屏右边界内")
    assertTrue(
        WindowMovementPlanner.shouldCacheForReturn(
            originalFrame: original, projectedFrame: projected, from: bigScreen1, to: smallScreen),
        "仅位置被夹紧时也应缓存原位置以便无损移回"
    )

    print("testNonMaximizedPositionOnlyClampedRoundTrip passed")
}

private func testFrameUpdatePlanAndAXTopAlignment() {
    // 大屏 -> 小屏（缩小）：到达目标屏后仍需再设一次 size + position
    let shrinkPlan = AppActionExecutor.windowFrameUpdatePlan(
        currentFrame: bigScreen1.visibleFrame, targetFrame: smallScreen.visibleFrame)
    assertEqual(shrinkPlan, [.size, .position, .size, .position], "缩小跨屏应在移动后再校验一次 size 和 position")

    // 小屏 -> 大屏（放大）：第一步 position 必须对齐目标顶部（AppKit maxY），避免 AX 向下扩展时顶到屏幕底边被截断
    let expandPlan = AppActionExecutor.windowFrameUpdatePlan(
        currentFrame: smallScreen.visibleFrame, targetFrame: bigScreen1.visibleFrame)
    assertEqual(expandPlan, [.position, .size, .position], "放大跨屏应先移动再放大再对齐")

    let stepFrame = AppActionExecutor.windowFramePositionStepFrame(
        currentFrame: smallScreen.visibleFrame, targetFrame: bigScreen1.visibleFrame)
    assertEqual(stepFrame.minX, bigScreen1.visibleFrame.minX, "第一步 X 应与目标一致")
    assertEqual(stepFrame.maxY, bigScreen1.visibleFrame.maxY, "第一步顶部（AX origin.y）应与目标顶部一致")
    assertEqual(stepFrame.size, smallScreen.visibleFrame.size, "第一步尺寸应保持当前尺寸")

    print("testFrameUpdatePlanAndAXTopAlignment passed")
}

private func testShouldUseRestoredFrameMatchesAnyRecorded() {
    let target = CGRect(x: 5120, y: 0, width: 1512, height: 944)
    let intermediate = CGRect(x: 5120, y: 100, width: 1512, height: 844)
    assertTrue(
        WindowMovementPlanner.shouldUseRestoredFrame(
            currentFrame: target, lastAutoFramesOnSourceDisplay: [target, intermediate]),
        "当前帧匹配目标帧时应允许使用恢复缓存"
    )
    assertTrue(
        !WindowMovementPlanner.shouldUseRestoredFrame(
            currentFrame: CGRect(x: 5200, y: 50, width: 1000, height: 700),
            lastAutoFramesOnSourceDisplay: [target, intermediate]),
        "用户手动改过窗口位置大小后不应使用旧缓存"
    )

    print("testShouldUseRestoredFrameMatchesAnyRecorded passed")
}

@main
struct WindowMovementTestsMain {
    static func main() {
        testMaximizedRoundTripBigToSmallToBig()
        testNonMaximizedSizeAndPositionClampedRoundTrip()
        testNonMaximizedPositionOnlyClampedRoundTrip()
        testFrameUpdatePlanAndAXTopAlignment()
        testShouldUseRestoredFrameMatchesAnyRecorded()
        print("WindowMovementTests all passed")
    }
}
