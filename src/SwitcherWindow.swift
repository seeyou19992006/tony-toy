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
        addSubview(iconView)

        nameLabel.stringValue = item.displayTitle
        nameLabel.font = .systemFont(ofSize: 11.5)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        // 没有窗口的应用：图标去色 + 半透明
        iconView.image = item.hasWindow ? icon : Self.desaturated(icon)
        iconView.alphaValue = item.hasWindow ? 1.0 : 0.45
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        addSubview(nameLabel)

        updateHighlight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func layout() {
        super.layout()
        highlight.frame = bounds
        let iconSide: CGFloat = 80
        iconView.frame = NSRect(x: (bounds.width - iconSide) / 2,
                                y: bounds.height - iconSide - 22,
                                width: iconSide, height: iconSide)
        nameLabel.frame = NSRect(x: 2, y: 6, width: bounds.width - 4, height: 16)
    }

    /// 去色 + 压暗，表示该应用没有打开的窗口
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

    private func updateHighlight() {
        highlight.layer?.backgroundColor = isSelected
            ? NSColor(srgbRed: 0.13, green: 0.47, blue: 0.55, alpha: 1).cgColor
            : NSColor.clear.cgColor
        nameLabel.textColor = NSColor.white.withAlphaComponent(isSelected ? 1 : 0.85)
    }
}

/// ⌘Tab 的二维网格切换器
final class SwitcherWindow: NSPanel {
    private let background = NSVisualEffectView()
    private let tintView = NSView()
    private let headerLabel = NSTextField(labelWithString: "")
    private var tiles: [SwitcherTile] = []

    private var items: [SwitcherItem] = []
    private var selected = 0
    private var rows = 1
    private var cols = 1

    private let cellWidth: CGFloat = 140
    private let cellHeight: CGFloat = 134
    private let padding: CGFloat = 20
    private let headerHeight: CGFloat = 46

    init() {
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

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        contentView = background

        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.09, alpha: 0.88).cgColor
        background.addSubview(tintView)

        // 顶部标题栏：显示当前选中项的完整标题
        headerLabel.font = .systemFont(ofSize: 15, weight: .medium)
        headerLabel.textColor = .white
        headerLabel.lineBreakMode = .byTruncatingMiddle
        headerLabel.alignment = .center
        background.addSubview(headerLabel)

        let separator = NSBox()
        separator.boxType = .separator
        separator.identifier = NSUserInterfaceItemIdentifier("headerSeparator")
        background.addSubview(separator)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 展示

    func show(items: [SwitcherItem]) {
        self.items = items
        guard !items.isEmpty else { return }

        (rows, cols) = Self.grid(for: items.count)
        // 与系统切换器一致：初次弹出选中第二个，第一个通常是当前应用
        selected = items.count > 1 ? 1 : 0

        rebuildTiles()
        layoutWindow()
        applySelection()
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    /// 横向 x+2 列，取最小的 x 容纳全部磁贴；行数按实际需要计算
    static func grid(for count: Int) -> (rows: Int, cols: Int) {
        guard count > 0 else { return (1, 3) }
        var x = 1
        while x * (x + 2) < count { x += 1 }
        let cols = x + 2
        let rows = (count + cols - 1) / cols
        return (rows, cols)
    }

    private func rebuildTiles() {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = items.map { item in
            let icon = NSWorkspace.shared.icon(forFile: item.entry.url.path)
            icon.size = NSSize(width: 80, height: 80)
            return SwitcherTile(item: item, icon: icon)
        }
        tiles.forEach { background.addSubview($0) }
    }

    private func layoutWindow() {
        let width = CGFloat(cols) * cellWidth + padding * 2
        let gridHeight = CGFloat(rows) * cellHeight
        let height = headerHeight + gridHeight + padding * 2

        let screen = targetScreen()
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)

        background.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        tintView.frame = background.bounds

        headerLabel.frame = NSRect(x: padding, y: height - headerHeight + 12,
                                   width: width - padding * 2, height: 22)
        if let separator = background.subviews.first(where: {
            $0.identifier?.rawValue == "headerSeparator"
        }) {
            separator.frame = NSRect(x: padding, y: height - headerHeight,
                                     width: width - padding * 2, height: 1)
        }

        for (index, tile) in tiles.enumerated() {
            let row = index / cols
            let column = index % cols
            let x = padding + CGFloat(column) * cellWidth
            // 首行紧贴标题栏下方
            let y = height - headerHeight - padding - CGFloat(row + 1) * cellHeight + padding
            tile.frame = NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
        }
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - 选择

    private func applySelection() {
        for (index, tile) in tiles.enumerated() {
            tile.isSelected = index == selected
        }
        if items.indices.contains(selected) {
            headerLabel.stringValue = items[selected].fullTitle
        }
    }

    var current: SwitcherItem? {
        items.indices.contains(selected) ? items[selected] : nil
    }

    /// 某个格子的一维下标；该列在该行不存在时回退到该行最后一个
    private func index(row: Int, column: Int) -> Int? {
        let start = row * cols
        guard start < items.count else { return nil }
        let end = min(start + cols, items.count) - 1
        return min(start + column, end)
    }

    /// 横向移动：按阅读顺序，行末接下一行行首
    func moveHorizontal(by delta: Int) {
        guard !items.isEmpty else { return }
        let row = selected / cols
        let rowStart = row * cols
        let rowEnd = min(rowStart + cols, items.count) - 1

        if delta > 0 {
            if selected < rowEnd {
                selected += 1
            } else {
                let nextStart = rowEnd + 1
                selected = nextStart < items.count ? nextStart : 0
            }
        } else {
            if selected > rowStart {
                selected -= 1
            } else if rowStart > 0 {
                let prevStart = (row - 1) * cols
                selected = min(prevStart + cols, items.count) - 1
            } else {
                selected = items.count - 1
            }
        }
        applySelection()
    }

    /// 纵向移动：同列跨行；该列在目标行不存在时落到目标行末尾
    func moveVertical(by delta: Int) {
        guard !items.isEmpty else { return }
        let row = selected / cols
        let column = selected % cols
        let totalRows = (items.count + cols - 1) / cols

        var targetRow = row + (delta > 0 ? 1 : -1)
        if targetRow < 0 { targetRow = totalRows - 1 }
        if targetRow >= totalRows { targetRow = 0 }

        if let target = index(row: targetRow, column: column) {
            selected = target
        }
        applySelection()
    }

    /// Tab 顺序前进/后退
    func moveSequential(by delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
        applySelection()
    }
}
