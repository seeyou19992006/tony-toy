import Cocoa

/// 所有输入监听器的注册表。
///
/// 存在意义：排查「某个键为什么不生效」时，第一步要能回答——
/// 现在有几个 tap 在跑、各自监听什么事件、有没有被系统禁用。
/// 之前这些信息散在 5 个 controller 的私有属性里，只能靠读代码猜。
///
/// 线程：只在主线程读写（tap 都在主线程创建）。
final class InputRegistry {
    static let shared = InputRegistry()

    struct Entry {
        let name: String
        let kind: Kind
        let events: [CGEventType]
        let isRunning: Bool
        let isEnabled: Bool
    }

    enum Kind: String {
        case eventTap = "CGEvent tap"
        case carbonHotkey = "Carbon 热键"
        case localMonitor = "本地监听"
        case hidDevice = "HID 设备"
    }

    private var entries: [String: Entry] = [:]
    /// EventTap 实例，用于查询实时状态
    private var taps: [String: WeakTap] = [:]

    private struct WeakTap {
        weak var value: EventTap?
    }

    private init() {}

    // MARK: - EventTap

    func register(_ tap: EventTap) {
        taps[tap.name] = WeakTap(value: tap)
        entries[tap.name] = Entry(
            name: tap.name,
            kind: .eventTap,
            events: tap.eventTypes,
            isRunning: tap.isRunning,
            isEnabled: tap.isEnabled
        )
    }

    func unregister(_ tap: EventTap) {
        taps.removeValue(forKey: tap.name)
        entries.removeValue(forKey: tap.name)
    }

    // MARK: - 其它监听器

    /// 登记非 EventTap 的监听器（Carbon 热键、本地监听、HID 设备）。
    /// 这些的生命周期由各自持有者管理，注册表只做展示。
    func note(name: String, kind: Kind, events: [CGEventType] = [], isRunning: Bool = true) {
        entries[name] = Entry(
            name: name, kind: kind, events: events,
            isRunning: isRunning, isEnabled: isRunning)
    }

    func remove(name: String) {
        entries.removeValue(forKey: name)
    }

    // MARK: - 查询

    /// 当前所有监听器的快照（按名字排序，输出稳定便于对比）
    func snapshot() -> [Entry] {
        entries.values
            .map { entry in
                // EventTap 的实时状态以实例为准，Entry 里的是登记时的快照
                guard let tap = taps[entry.name]?.value else { return entry }
                return Entry(
                    name: entry.name, kind: entry.kind, events: entry.events,
                    isRunning: tap.isRunning, isEnabled: tap.isEnabled)
            }
            .sorted { $0.name < $1.name }
    }

    /// 哪些 tap 在监听指定事件类型
    func listeners(for event: CGEventType) -> [String] {
        snapshot()
            .filter { $0.kind == .eventTap && $0.events.contains(event) }
            .map(\.name)
    }

    /// 人类可读的完整快照，用于诊断面板与日志
    func describe() -> String {
        let all = snapshot()
        guard !all.isEmpty else { return "当前没有活跃的输入监听器。" }

        var lines: [String] = []
        for entry in all {
            let status: String
            if !entry.isRunning {
                status = "未运行"
            } else if !entry.isEnabled {
                status = "已运行但被系统禁用"
            } else {
                status = "运行中"
            }
            let eventNames = entry.events.map(\.debugName).joined(separator: ", ")
            let suffix = eventNames.isEmpty ? "" : " | 监听: \(eventNames)"
            lines.append("\(entry.name)  [\(entry.kind.rawValue)]  \(status)\(suffix)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 辅助

extension EventTap {
    /// 监听的事件类型列表（供注册表展示）。
    /// 从掩码反解，避免再存一份数据。
    var eventTypes: [CGEventType] {
        CGEventType.knownCases.filter { type in
            events & (CGEventMask(1) << CGEventMask(type.rawValue)) != 0
        }
    }
}

extension CGEventType {
    /// 常用事件的显示名（诊断面板用）
    var debugName: String {
        switch self {
        case .keyDown: return "keyDown"
        case .keyUp: return "keyUp"
        case .flagsChanged: return "flagsChanged"
        case .leftMouseDown: return "leftMouseDown"
        case .leftMouseUp: return "leftMouseUp"
        case .rightMouseDown: return "rightMouseDown"
        case .rightMouseUp: return "rightMouseUp"
        case .otherMouseDown: return "otherMouseDown"
        case .otherMouseUp: return "otherMouseUp"
        case .scrollWheel: return "scrollWheel"
        case .tapDisabledByTimeout: return "tapDisabledByTimeout"
        case .tapDisabledByUserInput: return "tapDisabledByUserInput"
        default: return "type\(rawValue)"
        }
    }

    /// 可枚举的常用类型（用于反解掩码）
    static let knownCases: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged,
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp, .scrollWheel,
    ]
}
