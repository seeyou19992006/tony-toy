import Cocoa

/// 切换器磁贴标题显示模式
enum SwitcherTitleMode: String {
    case all
    case selectedOnly
}

/// 单个磁贴：图标 + 窗口标题
final class SwitcherTile: NSView {
    private let highlight = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    private let boxSide: CGFloat = 99
    private let iconSide: CGFloat = 106
    private let titleMode: SwitcherTitleMode

    var isSelected = false {
        didSet { updateHighlight() }
    }

    init(item: SwitcherItem, icon: NSImage, titleMode: SwitcherTitleMode = .all) {
        self.titleMode = titleMode
        super.init(frame: .zero)

        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 28.2
        highlight.layer?.cornerCurve = .continuous
        addSubview(highlight)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        // 没有窗口的应用：图标去色 + 半透明（缓存里已含去色版本）
        iconView.image = icon
        iconView.alphaValue = item.hasWindow ? 1.0 : 0.45
        addSubview(iconView)

        nameLabel.stringValue = item.displayTitle
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        let textShadow = NSShadow()
        textShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        textShadow.shadowOffset = NSSize(width: 0, height: -1)
        textShadow.shadowBlurRadius = 3
        nameLabel.shadow = textShadow
        addSubview(nameLabel)

        updateHighlight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlight()
    }

    override func layout() {
        super.layout()
        let boxX = (bounds.width - boxSide) / 2
        let boxY = bounds.height - boxSide - 6
        highlight.frame = NSRect(x: boxX, y: boxY, width: boxSide, height: boxSide)

        iconView.frame = NSRect(
            x: boxX + (boxSide - iconSide) / 2,
            y: boxY + (boxSide - iconSide) / 2,
            width: iconSide,
            height: iconSide
        )
        let expand: CGFloat = (titleMode == .selectedOnly) ? 17 : -5
        nameLabel.frame = NSRect(x: -expand, y: 6, width: bounds.width + expand * 2, height: 20)
    }

    private func updateHighlight() {
        highlight.layer?.backgroundColor = isSelected
            ? NSColor(white: 1.0, alpha: 0.56).cgColor
            : NSColor.clear.cgColor
        nameLabel.isHidden = (titleMode == .selectedOnly && !isSelected)
        let fontSize: CGFloat = (titleMode == .selectedOnly) ? 15 : 13.8
        nameLabel.font = .systemFont(ofSize: fontSize, weight: isSelected ? .semibold : .regular)
        nameLabel.textColor = isSelected ? .white : NSColor.white.withAlphaComponent(0.75)
    }
}

/// 单个显示器上的切换器面板（纯渲染，状态由 SwitcherController 持有）
final class SwitcherWindow: NSPanel {
    private let rootView = NSView()
    private let contentContainer = NSView()
    private let scrimView = NSView()
    private let blurView = NSVisualEffectView()
    private var glassView: NSView?
    private var tiles: [SwitcherTile] = []

    private var items: [SwitcherItem] = []
    private var selected = 0
    private var rows = 1
    private var cols = 1
    private var titleMode: SwitcherTitleMode = .all

    private let hostScreen: NSScreen
    private let cellWidth: CGFloat = 125
    private let cellHeight: CGFloat = 137
    private let padding: CGFloat = 17

    init(screen: NSScreen) {
        self.hostScreen = screen
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        // 切换器固定使用深色外观，避免浅色模式下玻璃过亮影响白字和选框对比度
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        contentView = rootView

        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.layer?.masksToBounds = true
        blurView.autoresizingMask = [.width, .height]

        scrimView.wantsLayer = true
        scrimView.layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.29).cgColor
        scrimView.autoresizingMask = [.width, .height]
        contentContainer.addSubview(scrimView)
        contentContainer.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            // macOS 26+：底层 .popover(0.71) + 29% 灰调遮罩 + 顶层 Liquid Glass (.clear)
            hasShadow = false
            blurView.material = .popover
            blurView.alphaValue = 0.71
            rootView.addSubview(blurView)

            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.contentView = contentContainer
            glass.autoresizingMask = [.width, .height]
            rootView.addSubview(glass)
            glassView = glass
        } else {
            hasShadow = true
            scrimView.isHidden = true
            blurView.material = .hudWindow
            blurView.alphaValue = 1.0
            rootView.addSubview(blurView)
            blurView.addSubview(contentContainer)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS 26 的 NSGlassEffectView 依据窗口的 `_hasActiveAppearance` 决定是否渲染完整液态玻璃效果；
    /// 多屏展示时系统仅让单个 keyWindow 为 active，重写此属性让所有屏幕上的切换器保持一致的液态玻璃质感。
    @objc var _hasActiveAppearance: Bool { true }

    // MARK: - 展示

    func present(items: [SwitcherItem], rows: Int, cols: Int, selected: Int, titleMode: SwitcherTitleMode = .all) {
        self.items = items
        self.rows = rows
        self.cols = cols
        self.selected = selected
        self.titleMode = titleMode

        rebuildTiles()
        layoutWindow()
        applySelection()
    }

    func updateSelection(_ index: Int) {
        selected = index
        applySelection()
    }

    func hide() {
        orderOut(nil)
    }

    private func rebuildTiles() {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = items.map { item in
            SwitcherTile(
                item: item,
                icon: IconCache.icon(for: item.entry, gray: !item.hasWindow),
                titleMode: titleMode
            )
        }
        tiles.forEach { contentContainer.addSubview($0) }
    }

    private func layoutWindow() {
        let width = CGFloat(cols) * cellWidth + padding * 2
        let gridHeight = CGFloat(rows) * cellHeight
        let height = gridHeight + padding * 2

        let radius: CGFloat = rows == 1 ? 43 : 31
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            glass.cornerRadius = radius
        }
        blurView.layer?.cornerRadius = radius

        let visible = hostScreen.visibleFrame
        let origin = NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)

        rootView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        blurView.frame = rootView.bounds
        glassView?.frame = rootView.bounds
        contentContainer.frame = rootView.bounds
        scrimView.frame = contentContainer.bounds

        let gridTop = height - padding
        for (index, tile) in tiles.enumerated() {
            let row = index / cols
            let column = index % cols
            let x = padding + CGFloat(column) * cellWidth
            let y = gridTop - CGFloat(row + 1) * cellHeight
            tile.frame = NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
        }
    }

    private func applySelection() {
        for (index, tile) in tiles.enumerated() {
            tile.isSelected = index == selected
        }
    }
}
