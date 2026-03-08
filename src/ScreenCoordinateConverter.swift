import Foundation
import Cocoa

struct ScreenCoordinateConverter {
    let originX: CGFloat
    let topY: CGFloat

    init(originX: CGFloat, topY: CGFloat) {
        self.originX = originX
        self.topY = topY
    }

    func appKitFrame(fromAXFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + originX,
            y: topY - frame.minY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    func axFrame(fromAppKitFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX - originX,
            y: topY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    static func current(screens: [NSScreen] = NSScreen.screens) -> ScreenCoordinateConverter? {
        guard let menuBarScreen = menuBarScreen(from: screens) else {
            return nil
        }

        return ScreenCoordinateConverter(
            originX: menuBarScreen.frame.minX,
            topY: menuBarScreen.frame.maxY
        )
    }

    private static func menuBarScreen(from screens: [NSScreen]) -> NSScreen? {
        screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsMain(CGDirectDisplayID(screenNumber.uint32Value)) != 0
        } ?? screens.first
    }
}
