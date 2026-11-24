import AppKit

/// 跟随系统/应用外观的着色层。
///
/// `CALayer.backgroundColor` 存的是 `CGColor` 快照，不会随 appearance
/// 自动更新——必须重写 `updateLayer()` 在每次外观变化时重设。
/// 用 `wantsUpdateLayer` + `updateLayer` 而不是在 `init` 里设一次，
/// 否则切主题后只有窗口框架变、遮罩还是旧颜色。
final class AppearanceAwareTintView: NSView {
    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // 两套主题的诉求相反，必须分开调：
        //  - 深色：压暗毛玻璃，否则背后窗口透上来、白字对比度不够
        //  - 浅色：`windowBackgroundColor` 在浅色下是 #ECECEC 这种近白，
        //    再叠高不透明度就成了一块白板。用明显更深的灰（#DBDBDB）
        //    加中等不透明度，让毛玻璃纹理和背后内容透出来，
        //    接近系统 Spotlight / ⌘Tab 那种「半透明灰片」的观感。
        let white: CGFloat = isDark ? 0.08 : 0.86
        let alpha: CGFloat = isDark ? 0.86 : 0.60

        layer?.backgroundColor = NSColor(white: white, alpha: alpha).cgColor
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
    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
