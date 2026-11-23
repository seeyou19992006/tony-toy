import Cocoa

/// 单个磁贴：图标 + 窗口标题 + 窗口角标
final class SwitcherTile: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let highlight = NSView()
    private let badge = NSView()

    var isSelected = false {
        didSet { updateHighlight() }
    }

    init(item: SwitcherItem, icon: NSImage) {
        super.init(frame: .zero)

        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 10
        addSubview(highlight)

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        nameLabel.stringValue = item.displayTitle
        nameLabel.font = .systemFont(ofSize: 11.5)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        // 角标：绿点=有窗口，灰点=仅后台运行
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.borderWidth = 2
        badge.layer?.borderColor = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.09, alpha: 1).cgColor
        badge.layer?.backgroundColor = (item.hasWindow
            ? NSColor.systemGreen
            : NSColor(white: 0.62, alpha: 1)).cgColor
        addSubview(badge)

        updateHighlight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func layout() {
        super.layout()
        highlight.frame = bounds
        let iconSide: CGFloat = 52
        iconView.frame = NSRect(x: (bounds.width - iconSide) / 2,
                                y: bounds.height - iconSide - 22,
                                width: iconSide, height: iconSide)
        nameLabel.frame = NSRect(x: 4, y: 6, width: bounds.width - 8, height: 16)
        badge.frame = NSRect(x: iconView.frame.maxX - 12, y: iconView.frame.maxY - 12,
                             width: 10, height: 10)
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

    private let cellWidth: CGFloat = 104
    private let cellHeight: CGFloat = 100
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

    /// 竖向 x 行、横向 x+2 列，取最小的 x 容纳全部磁贴
    static func grid(for count: Int) -> (rows: Int, cols: Int) {
        guard count > 0 else { return (1, 3) }
        var x = 1
        while x * (x + 2) < count { x += 1 }
        return (x, x + 2)
    }

    private func rebuildTiles() {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = items.map { item in
            let icon = NSWorkspace.shared.icon(forFile: item.entry.url.path)
            icon.size = NSSize(width: 52, height: 52)
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

    /// 横向移动：行内循环
    func moveHorizontal(by delta: Int) {
        guard !items.isEmpty else { return }
        let row = selected / cols
        let column = selected % cols
        let newColumn = (column + delta + cols) % cols
        let candidate = row * cols + newColumn
        selected = candidate < items.count ? candidate : selected
        applySelection()
    }

    /// 纵向移动：整行跨越，越界则跳到首行/末行的同一列
    func moveVertical(by delta: Int) {
        guard !items.isEmpty else { return }
        let column = selected % cols

        if delta < 0 {
            let candidate = selected - cols
            if candidate >= 0 {
                selected = candidate
            } else {
                guard column < items.count else { return }
                let lastRow = (items.count - 1 - column) / cols
                selected = lastRow * cols + column
            }
        } else {
            let candidate = selected + cols
            if candidate < items.count {
                selected = candidate
            } else {
                selected = column < items.count ? column : 0
            }
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
