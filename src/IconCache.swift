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
        let raw = NSWorkspace.shared.icon(forFile: entry.url.path)
        raw.size = NSSize(width: 96, height: 96)
        // 统一裁剪成 96×96 @2x（192×192 像素）Retina 位图并丢弃 512/1024 超大图层，
        // 兼顾切换器（96pt）与启动器（36pt）清晰度，同时大幅减少 CoreAnimation 显存占用。
        let image = rasterize(raw, colorSpace: CGColorSpaceCreateDeviceRGB())
        icons.setObject(image, forKey: key)
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
        rasterize(image, colorSpace: CGColorSpaceCreateDeviceGray())
    }

    private static func rasterize(_ image: NSImage, colorSpace: CGColorSpace) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let scale: CGFloat = 2  // 视网膜屏
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        var proposedRect = CGRect(origin: .zero, size: size)
        guard width > 0, height > 0,
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      // 必须带 alpha：none 会把图标圆角外的透明区域画成黑色
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { return image }
        return NSImage(cgImage: output, size: size)
    }
}
