import AppKit
import CoreImage

/// 应用图标缓存：避免每次弹出切换器都重新读盘和做去色
enum IconCache {
    private static var icons: [String: NSImage] = [:]
    private static var grayIcons: [String: NSImage] = [:]

    static func icon(for entry: AppEntry, gray: Bool) -> NSImage {
        let key = entry.bundleID

        if gray {
            if let cached = grayIcons[key] { return cached }
            let base = icon(for: entry, gray: false)
            let result = desaturated(base)
            grayIcons[key] = result
            return result
        }

        if let cached = icons[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: entry.url.path)
        image.size = NSSize(width: 96, height: 96)
        icons[key] = image
        return image
    }

    /// 去色，表示该应用没有打开的窗口
    private static func desaturated(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let ci = CIImage(data: tiff),
              let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return image }
        let result = NSImage(size: image.size)
        result.addRepresentation(NSCIImageRep(ciImage: output))
        return result
    }
}
