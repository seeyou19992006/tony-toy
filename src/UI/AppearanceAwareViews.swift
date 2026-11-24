import AppKit

/// 跟随系统/应用外观的着色层。
///
/// `CALayer.backgroundColor` 存的是 `CGColor` 快照，不会随 appearance
/// 自动更新——必须重写 `updateLayer()` 在每次外观变化时重设。
/// 用 `wantsUpdateLayer` + `updateLayer` 而不是在 `init` 里设一次，
/// 否则切主题后只有窗口框架变、遮罩还是旧颜色。
final class AppearanceAwareTintView: NSView {
    /// 遮罩不透明度。亮色主题下毛玻璃本身够亮，压淡一点保证文字可读；
    /// 深色主题下压浓一点，避免背景透太多。
    private let dimAlpha: CGFloat

    init(dimAlpha: CGFloat = 0.75) {
        self.dimAlpha = dimAlpha
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(dimAlpha)
            .cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // 触发 updateLayer 重算颜色
        needsDisplay = true
    }
}

/// 跟随外观的描边视图。
///
/// 和 `AppearanceAwareTintView` 同样的理由：`layer.borderColor` 是
/// `CGColor` 快照，必须每次外观变化重设。
final class AppearanceAwareBorderView: NSView {
    private let borderAlpha: CGFloat

    init(borderAlpha: CGFloat = 0.25) {
        self.borderAlpha = borderAlpha
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderColor = NSColor.separatorColor
            .withAlphaComponent(borderAlpha)
            .cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
