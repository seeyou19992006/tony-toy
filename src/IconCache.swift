import AppKit

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

    /// 后台预热：提前读盘并生成灰度版本，避免首次弹出时才计算
    static func prewarm(_ entries: [AppEntry], windowedIDs: Set<String>) {
        DispatchQueue.global(qos: .utility).async {
            for entry in entries {
                _ = icon(for: entry, gray: !windowedIDs.contains(entry.bundleID))
            }
        }
    }

    /// 去色。
    /// 不用 CIFilter——CoreImage 上下文初始化首次接近 5 秒；
    /// 交给 CoreGraphics 在灰度色彩空间里绘制，单次不到 1 毫秒。
    private static func desaturated(_ image: NSImage) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let scale: CGFloat = 2  // 视网膜屏
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      // 必须带 alpha：none 会把图标圆角外的透明区域画成黑色
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let gray = context.makeImage() else { return image }
        return NSImage(cgImage: gray, size: size)
    }
}
