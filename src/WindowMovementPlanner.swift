import Foundation
import CoreGraphics

struct DisplayLayout: Equatable {
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
}

struct WindowRestoreKey: Hashable {
    let windowID: String
}

enum WindowMovementPlanner {
    static func adjacentDisplay(
        from source: DisplayLayout,
        direction: DisplayDirection,
        displays: [DisplayLayout]
    ) -> DisplayLayout? {
        let candidates = displays.filter { $0.id != source.id }.compactMap { display -> (DisplayLayout, CGFloat, CGFloat)? in
            let sourceCenter = CGPoint(x: source.frame.midX, y: source.frame.midY)
            let displayCenter = CGPoint(x: display.frame.midX, y: display.frame.midY)

            switch direction {
            case .left:
                guard displayCenter.x < sourceCenter.x else { return nil }
                let primaryGap = max(0, source.frame.minX - display.frame.maxX)
                let secondaryDistance = abs(displayCenter.y - sourceCenter.y)
                return (display, primaryGap, secondaryDistance)
            case .right:
                guard displayCenter.x > sourceCenter.x else { return nil }
                let primaryGap = max(0, display.frame.minX - source.frame.maxX)
                let secondaryDistance = abs(displayCenter.y - sourceCenter.y)
                return (display, primaryGap, secondaryDistance)
            case .up:
                guard displayCenter.y > sourceCenter.y else { return nil }
                let primaryGap = max(0, display.frame.minY - source.frame.maxY)
                let secondaryDistance = abs(displayCenter.x - sourceCenter.x)
                return (display, primaryGap, secondaryDistance)
            case .down:
                guard displayCenter.y < sourceCenter.y else { return nil }
                let primaryGap = max(0, source.frame.minY - display.frame.maxY)
                let secondaryDistance = abs(displayCenter.x - sourceCenter.x)
                return (display, primaryGap, secondaryDistance)
            }
        }

        return candidates.min {
            if $0.1 == $1.1 {
                return $0.2 < $1.2
            }
            return $0.1 < $1.1
        }?.0
    }

    static func displayContaining(frame: CGRect, displays: [DisplayLayout]) -> DisplayLayout? {
        guard let best = displays.max(by: { lhs, rhs in
            intersectionArea(frame, lhs.visibleFrame) < intersectionArea(frame, rhs.visibleFrame)
        }) else {
            return nil
        }
        if intersectionArea(frame, best.visibleFrame) > 0 {
            return best
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.min {
            distanceSquared(from: center, to: CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY)) <
            distanceSquared(from: center, to: CGPoint(x: $1.visibleFrame.midX, y: $1.visibleFrame.midY))
        }
    }

    static func project(frame: CGRect, from source: DisplayLayout, to target: DisplayLayout) -> CGRect {
        let sourceVisible = source.visibleFrame
        let targetVisible = target.visibleFrame

        if isNearVisibleFrame(frame, visibleFrame: sourceVisible) {
            return targetVisible
        }

        let relativeX = frame.minX - sourceVisible.minX
        let relativeTopInset = sourceVisible.maxY - frame.maxY
        let targetWidth = min(frame.width, targetVisible.width)
        let targetHeight = min(frame.height, targetVisible.height)
        let targetX = targetVisible.minX + relativeX
        let targetY = targetVisible.maxY - relativeTopInset - targetHeight

        return clamp(frame: CGRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight), to: targetVisible)
    }

    static func resolveTargetFrame(
        frame: CGRect,
        from source: DisplayLayout,
        to target: DisplayLayout,
        cachedTargetFrame: CGRect?
    ) -> CGRect {
        let projected = project(frame: frame, from: source, to: target)
        guard let cachedTargetFrame else {
            return projected
        }
        return clamp(frame: cachedTargetFrame, to: target.visibleFrame)
    }

    static func shouldUseRestoredFrame(
        currentFrame: CGRect,
        lastAutoFrameOnSourceDisplay: CGRect?
    ) -> Bool {
        guard let lastAutoFrameOnSourceDisplay else {
            return false
        }
        let tolerance: CGFloat = 16
        return abs(currentFrame.minX - lastAutoFrameOnSourceDisplay.minX) <= tolerance &&
            abs(currentFrame.minY - lastAutoFrameOnSourceDisplay.minY) <= tolerance &&
            abs(currentFrame.width - lastAutoFrameOnSourceDisplay.width) <= tolerance &&
            abs(currentFrame.height - lastAutoFrameOnSourceDisplay.height) <= tolerance
    }

    static func restoredFrame(
        for key: WindowRestoreKey,
        targetDisplayID: String,
        cache: [WindowRestoreKey: [String: CGRect]]
    ) -> CGRect? {
        cache[key]?[targetDisplayID]
    }

    static func consumeRestoredFrame(
        for key: WindowRestoreKey,
        targetDisplayID: String,
        cache: [WindowRestoreKey: [String: CGRect]]
    ) -> (CGRect?, [WindowRestoreKey: [String: CGRect]]) {
        guard var displayFrames = cache[key] else {
            return (nil, cache)
        }

        let restored = displayFrames.removeValue(forKey: targetDisplayID)
        var updatedCache = cache
        if displayFrames.isEmpty {
            updatedCache.removeValue(forKey: key)
        } else {
            updatedCache[key] = displayFrames
        }
        return (restored, updatedCache)
    }

    static func shouldCacheForReturn(originalFrame: CGRect, projectedFrame: CGRect) -> Bool {
        let tolerance: CGFloat = 16
        return projectedFrame.width < originalFrame.width - tolerance ||
            projectedFrame.height < originalFrame.height - tolerance
    }

    static func clamp(frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - height
        let x = min(max(frame.minX, minX), maxX)
        let y = min(max(frame.minY, minY), maxY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        lhs.intersection(rhs).isNull ? 0 : lhs.intersection(rhs).width * lhs.intersection(rhs).height
    }

    private static func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private static func isNearVisibleFrame(_ frame: CGRect, visibleFrame: CGRect) -> Bool {
        let tolerance: CGFloat = 8
        return abs(frame.minX - visibleFrame.minX) <= tolerance &&
            abs(frame.minY - visibleFrame.minY) <= tolerance &&
            abs(frame.width - visibleFrame.width) <= tolerance &&
            abs(frame.height - visibleFrame.height) <= tolerance
    }
}
