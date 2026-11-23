import Cocoa
import CoreImage

/// 单个磁贴：图标 + 窗口标题
final class SwitcherTile: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let highlight = NSView()

    var isSelected = false {
        didSet { updateHighlight() }
    }

    init(item: SwitcherItem, icon: NSImage) {
        super.init(frame: .zero)

        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 10
        addSubview(highlight)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        // 没有窗口的应用：图标去色 + 半透明
        iconView.image = item.hasWindow ? icon : Self.desaturated(icon)
        iconView.alphaValue = item.hasWindow ? 1.0 : 0.45
        addSubview(iconView)

        nameLabel.stringValue = item.displayTitle
        nameLabel.font = .systemFont(ofSize: 11.5)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        updateHighlight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func layout() {
        super.layout()
        highlight.frame = bounds.insetBy(dx: 6, dy: 6)
        let iconSide: CGFloat = 96
        iconView.frame = NSRect(x: (bounds.width - iconSide) / 2,
                                y: bounds.height - iconSide - 22,
                                width: iconSide, height: iconSide)
        nameLabel.frame = NSRect(x: 12, y: 7, width: bounds.width - 24, height: 16)
    }

    private func updateHighlight() {
        highlight.layer?.backgroundColor = isSelected
            ? NSColor(srgbRed: 0.13, green: 0.47, blue: 0.55, alpha: 1).cgColor
            : NSColor.clear.cgColor
        nameLabel.textColor = NSColor.white.withAlphaComponent(isSelected ? 1 : 0.85)
    }

    /// 去色 + 半透明，表示该应用没有打开的窗口
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

/// 单个显示器上的切换器面板（纯渲染，状态由 SwitcherController 持有）
final class SwitcherWindow: NSPanel {
    private let background = NSVisualEffectView()
    private let container = NSView()
    private let tintView = NSView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let separator = NSBox()
    private var tiles: [SwitcherTile] = []

    private var items: [SwitcherItem] = []
    private var selected = 0
    private var rows = 1
    private var cols = 1

    private let hostScreen: NSScreen
    private let cellWidth: CGFloat = 156
    private let cellHeight: CGFloat = 152
    private let padding: CGFloat = 20
    private let headerHeight: CGFloat = 46
    private let gridGap: CGFloat = 12

    init(screen: NSScreen) {
        self.hostScreen = screen
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        // 毛玻璃材质由窗口服务端合成，不响应自身圆角；
        // 用一层 layer-backed 容器做裁剪，否则圆角外会露出矩形底色
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        contentView = container

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.frame = container.bounds
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)

        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.09, alpha: 0.88).cgColor
        background.addSubview(tintView)

        headerLabel.font = .systemFont(ofSize: 15, weight: .medium)
        headerLabel.textColor = .white
        headerLabel.lineBreakMode = .byTruncatingMiddle
        headerLabel.alignment = .center
        background.addSubview(headerLabel)

        separator.boxType = .separator
        background.addSubview(separator)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 展示

    func present(items: [SwitcherItem], rows: Int, cols: Int, selected: Int) {
        self.items = items
        self.rows = rows
        self.cols = cols
        self.selected = selected

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
            let icon = NSWorkspace.shared.icon(forFile: item.entry.url.path)
            icon.size = NSSize(width: 96, height: 96)
            return SwitcherTile(item: item, icon: icon)
        }
        tiles.forEach { background.addSubview($0) }
    }

    private func layoutWindow() {
        let width = CGFloat(cols) * cellWidth + padding * 2
        let gridHeight = CGFloat(rows) * cellHeight
        let height = headerHeight + gridGap + gridHeight + padding * 2

        let visible = hostScreen.visibleFrame
        let origin = NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)

        background.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        tintView.frame = background.bounds

        headerLabel.frame = NSRect(x: padding, y: height - headerHeight + 12,
                                   width: width - padding * 2, height: 22)
        separator.frame = NSRect(x: padding, y: height - headerHeight,
                                 width: width - padding * 2, height: 1)

        for (index, tile) in tiles.enumerated() {
            let row = index / cols
            let column = index % cols
            let x = padding + CGFloat(column) * cellWidth
            let gridTop = height - headerHeight - gridGap
            let y = gridTop - CGFloat(row + 1) * cellHeight
            tile.frame = NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
        }
    }

    private func applySelection() {
        for (index, tile) in tiles.enumerated() {
            tile.isSelected = index == selected
        }
        if items.indices.contains(selected) {
            headerLabel.stringValue = items[selected].fullTitle
        }
    }
}
