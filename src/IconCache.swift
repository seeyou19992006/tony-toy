import AppKit

/// 应用图标缓存：使用 NSCache 限制上限，避免长期运行内存只增不减
enum IconCache {
    private static let icons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    private static let grayIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    private static let smallIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    static func icon(for entry: AppEntry, gray: Bool) -> NSImage {
        let key = entry.bundleID as NSString

        if gray {
            if let cached = grayIcons.object(forKey: key) { return cached }
            let base = icon(for: entry, gray: false)
            let result = desaturated(base)
            grayIcons.setObject(result, forKey: key)
            return result
        }

        if let cached = icons.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: entry.url.path)
        image.size = NSSize(width: 96, height: 96)
        icons.setObject(image, forKey: key)
        return image
    }

    /// 启动器列表用的 36×36 小图标，复用同一份缓存池避免双份存储
    static func smallIcon(for entry: AppEntry) -> NSImage {
        let key = entry.bundleID as NSString
        if let cached = smallIcons.object(forKey: key) { return cached }
        let source = icon(for: entry, gray: false)
        let small = NSImage(size: NSSize(width: 36, height: 36))
        small.lockFocus()
        source.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36),
                    from: .zero, operation: .copy, fraction: 1.0)
        small.unlockFocus()
        smallIcons.setObject(small, forKey: key)
        return small
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
